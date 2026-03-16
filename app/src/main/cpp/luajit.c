#include <jni.h>
#include <android/log.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>	//chdir

#define luajit_c

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include "luajit.h"
#include "lj_arch.h"

lua_State *mainL = NULL;

static void l_message(const char *msg)
{
	fputs("luajit: ", stderr);
	fputs(msg, stderr);
	fputc('\n', stderr);
	fflush(stderr);
}

static int report(lua_State *L, int status)
{
	if (status && !lua_isnil(L, -1)) {
		const char *msg = lua_tostring(L, -1);
		if (msg == NULL) msg = "(error object is not a string)";
		l_message(msg);
		lua_pop(L, 1);
	}
	return status;
}

static int traceback(lua_State *L)
{
	if (!lua_isstring(L, 1)) { /* Non-string error object? Try metamethod. */
		if (lua_isnoneornil(L, 1) ||
			!luaL_callmeta(L, 1, "__tostring") ||
			!lua_isstring(L, -1))
			return 1;  /* Return non-string error object. */
		lua_remove(L, 1);  /* Replace object by result of __tostring metamethod. */
	}
	luaL_traceback(L, L, lua_tostring(L, 1), 1);
	return 1;
}

static int safecall(lua_State *L, int narg, int nret)
{
	int status;
	int base = lua_gettop(L) - narg;  /* function index */
	lua_pushcfunction(L, traceback);  /* push traceback function */
	lua_insert(L, base);  /* put it under chunk and args */
	status = lua_pcall(L, narg, nret, base);
	lua_remove(L, base);  /* remove traceback function */
	/* force a complete garbage collection in case of errors */
	if (status != LUA_OK) lua_gc(L, LUA_GCCOLLECT, 0);
	return status;
}

static struct Smain {
	char **argv;
	int argc;
	int status;
} smain;

JNIEnv * jniEnv = NULL;
jobject androidActivity = NULL;

int java_isAssetPathDir(lua_State *L) {
	if (!androidActivity) luaL_error(L, "androidActivity is uninitialized");
	if (!lua_isstring(L, 1)) luaL_error(L, "expected string");
	char const * path = lua_tostring(L, 1);

	jclass activityClass = jniEnv[0]->GetObjectClass(jniEnv, androidActivity);
	jmethodID method = jniEnv[0]->GetMethodID(jniEnv, activityClass, "isAssetPathDir", "(Ljava/lang/String;)Z");
	if (!method) luaL_error(L, "failed to get method");

	jstring pathStr = jniEnv[0]->NewStringUTF(jniEnv, path);
	jboolean result = jniEnv[0]->CallBooleanMethod(jniEnv, androidActivity, method, pathStr);

	lua_pushboolean(L, result);
	return 1;
}

int java_readAssetPath(lua_State *L) {
	if (!androidActivity) luaL_error(L, "androidActivity is uninitialized");
	if (!lua_isstring(L, 1)) luaL_error(L, "expected string");
	char const * path = lua_tostring(L, 1);

	jclass activityClass = jniEnv[0]->GetObjectClass(jniEnv, androidActivity);
	jmethodID method = jniEnv[0]->GetMethodID(jniEnv, activityClass, "readAssetPath", "(Ljava/lang/String;)[B");
	if (!method) luaL_error(L, "failed to get method");

	jstring pathStr = jniEnv[0]->NewStringUTF(jniEnv, path);
	jbyteArray bytes = jniEnv[0]->CallObjectMethod(jniEnv, androidActivity, method, pathStr);
	if (!bytes) return 0;

	jsize bytesLen = jniEnv[0]->GetArrayLength(jniEnv, bytes);

	jbyte * bytesPtr = jniEnv[0]->GetByteArrayElements(jniEnv, bytes, NULL);
	if (!bytesPtr) luaL_error(L, "GetByteArrayElements failed");

	lua_pushlstring(L, (char const *)bytesPtr, bytesLen);

	jniEnv[0]->ReleaseByteArrayElements(jniEnv, bytes, bytesPtr, 0);

	return 1;
}

static int androidLuajitInit(lua_State *L) {
	struct Smain *s = &smain;
	mainL = L;

	lua_gc(L, LUA_GCSTOP, 0);
	luaL_openlibs(L);				//
	lua_gc(L, LUA_GCRESTART, -1);

	// change ffi.os to Android
	//dolibrary clears the result so...
	lua_getglobal(L, "require");	// require
	lua_pushstring(L, "ffi");		// require ffi
	s->status = safecall(L, 1, 1);	// ffi
	if (s->status != LUA_OK) {
		report(L, s->status);
		return 0;
	}

	lua_pushliteral(L, "Android");	// ffi Android
	lua_setfield(L, -2, "os");		// ffi

#if 0
	lua_getfield(L, -1, "typeof");
	lua_pushliteral(L, "void*");
	s->status = safecall(L, 1, 1);	// ffi.typeof'void*' is on the stack
	if (s->status != LUA_OK) return 0;
	lua_setfield(L, LUA_REGISTRYINDEX, "void*");

	lua_getfield(L, -1, "typeof");
	lua_pushliteral(L, "uintptr_t");
	s->status = safecall(L, 1, 1);	// ffi.typeof'uintptr_t' is on the stack
	if (s->status != LUA_OK) return 0;
	lua_setfield(L, LUA_REGISTRYINDEX, "uintptr_t");
#endif

	lua_pop(L, 1);					//

	// while we're here, let's make a function that calls into java and pulls down files from the apk
	lua_pushcfunction(L, java_readAssetPath);		// java_readAssetPath
	lua_setfield(L, LUA_REGISTRYINDEX, "java_readAssetPath");

	lua_pushcfunction(L, java_isAssetPathDir);		// java_isAssetPathDir
	lua_setfield(L, LUA_REGISTRYINDEX, "java_isAssetPathDir");

	s->status = luaL_loadfile(L, "main.lua");		// main.lua's callback
	if (s->status != LUA_OK) {
		report(L, s->status);
		return 0;
	}

	// call the loaded function, expect it to return our per-method callback
	s->status = safecall(L, 0, 1);				// main.lua's result
//printf("main.lua compiled with this on top: %s\n", luaL_typename(L, -1));
	if (s->status != LUA_OK) {
		report(L, s->status);
		return 0;
	}

	int functype = lua_type(L, -1);
	if (functype != LUA_TFUNCTION) {
		luaL_error(L, "main.lua callback needs to return a function, got %s", lua_typename(L, functype));
	}

	// store the callback somewhere
	//lua_pushvalue(L, -1);						// main
	lua_setfield(L, LUA_REGISTRYINDEX, "main");

	return 0;
}

JNIEXPORT jlong JNICALL Java_io_github_thenumbernine_LuaJIT_Activity_nativeLuajitInit(
	JNIEnv * jniEnv_,
	jobject this,
	jstring wd
) {
	jniEnv = jniEnv_;
	
	// only used for java_readAssetPath / java_isAssetPathDir, i wanna replace this with a function arg
	androidActivity = this;

	// this doesn't/shouldn't block, or else it'll freeze the UI

	//chdir to our /data/data/package folder
	{
		char const * wdstr = jniEnv_[0]->GetStringUTFChars(jniEnv_, wd, NULL);
		if (wdstr) {
			chdir(wdstr);
		}
		jniEnv_[0]->ReleaseStringUTFChars(jniEnv_, wd, wdstr);
	}

	/*
	TODO
	I would like to redirect output somewhere I can see it besides bloated logcat
	and besides a file in the super super secret impossible-to-access /data/data/package folder.
	In fact, preference would be to a buffered location that this app itself can read, display, clear, etc.
	Hmm maybe I'll settle with here for now.
	Be sure to do this before creating the Lua state (so it uses the correct stdout).
	*/
	{
#if 0	// using two separate files for stdout and stderr:
		freopen("out.txt", "w+", stdout);
		freopen("err.txt", "w+", stderr);
#else	// using one file:
		if (freopen("out.txt", "w+", stdout) == NULL) {
			l_message("freopen failed");
			return 0;
		}

		if (dup2(fileno(stdout), fileno(stderr)) == -1) {
			l_message("dup2 stderr failed");
			return 0;
		}
#endif
		setvbuf(stdout, NULL, _IONBF, 0);
		setvbuf(stderr, NULL, _IONBF, 0);
	}

	lua_State *L;
	L = lua_open();
	if (L == NULL) {
		l_message("cannot create state: not enough memory");
		return 0;
	}

	int status = lua_cpcall(L, androidLuajitInit, NULL);
	report(L, status);

	return (jlong)L;
}

JNIEXPORT jobject JNICALL Java_io_github_thenumbernine_LuaJIT_Activity_nativeLuajitCall(
	JNIEnv * jniEnv_,
	jobject this,
	jlong _L,
	jstring msg,
	jobjectArray args
) {
	int status;

	jniEnv = jniEnv_;
	androidActivity = this;

	lua_State * L = (lua_State*)_L;
	if (!L) return NULL;
	lua_getfield(L, LUA_REGISTRYINDEX, "main");	// main

	char const * msgstr = jniEnv_[0]->GetStringUTFChars(jniEnv_, msg, NULL);
	lua_pushstring(L, msgstr);				// main, msg

	lua_pushlightuserdata(L, this);			// main, msg, this
	lua_pushlightuserdata(L, args);			// main, msg, this, args
	status = safecall(L, 3, 1);

	if (status != LUA_OK) {
		report(L, status);
		return NULL;
	}

#if 0
	// this gets a cdata, so ...
	// first cast it to uintptr_t (otherwise tonumber will fail)
	lua_getfield(L, LUA_REGISTRYINDEX, "uintptr_t");		// number, uintptr_t
	lua_insert(L, -2);										// uintptr_t, number
	status = safecall(L, 1, 1);								// uintptr_t-value
	if (status != LUA_OK) {
		report(L, status);
		return NULL;
	}
#endif

	jobject objres = NULL;
	if (!lua_isnil(L, -1)) {
		// TODO there has to be a way to do this easily
		objres = (jobject)(uintptr_t)lua_tonumber(L, -1);
	}
	lua_pop(L, 1);
//printf("JNI C: %s returning %p\n", msgstr, objres);
	jniEnv_[0]->ReleaseStringUTFChars(jniEnv_, msg, msgstr);
	return objres;
}
