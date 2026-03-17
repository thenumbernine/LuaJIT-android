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

/*
I couldve done this better I'm sure
here's the Lua code I was implementing:

	table.insert(package.loaders, function(modname)
		local reg = debug.getregistry()
		local java_readAssetPath = reg.java_readAssetPath
		local java_isAssetPathDir = reg.java_isAssetPathDir
		-- return function on success, string on failure
		local reasons = {}
		for opt in ('?.lua;?/?.lua'):gmatch'[^;]+' do
			local fn = opt:gsub('%?', (modname:gsub('%.', '/')))
			if java_isAssetPathDir(fn) then
				table.insert(reasons, 'is an asset dir: '..fn)
			else
				local data = java_readAssetPath(fn)
				if not data then
					table.insert(reasons, 'not an asset path: '..fn)
				else
					local res, err = load(data, modname)
					if res then return res end
					table.insert(reasons, fn..' '..tostring(err))
				end
			end
		end
		return "module '"..modname.."' not found:\n\t"
			..table.concat(reasons, '\n\t')
	end)
*/
int androidAssetLoader(lua_State *L) {
	if (!lua_isstring(L, 1)) {		// stack: args:[mod]
		luaL_error(L, "expected string");
	}
	lua_settop(L, 1);
	int modloc = 1;	//lua_gettop(L);

	lua_getglobal(L, "string");		// stack: [mod], string
	lua_getfield(L, -1, "gsub");	// stack: [mod], string, gsub
	lua_remove(L, -2);				// stack: [mod], gsub
	int gsubloc = lua_gettop(L);

	{
		lua_getglobal(L, "table");		// stack: [mod], gsub, table
		int tableloc = lua_gettop(L);
		lua_getfield(L, tableloc, "insert");	// stack: [mod], gsub, table, table.insert
		lua_getfield(L, tableloc, "concat");	// stack: [mod], gsub, table, table.insert, table.concat
		lua_remove(L, tableloc);				// stack: [mod], gsub, insert, concat
	}
	int concatloc = lua_gettop(L);
	int insertloc = concatloc-1;

	lua_newtable(L);				// stack: [mod], [gsub, insert, concat, reasons]
	int reasonsloc = lua_gettop(L);

	// stack: args:[mod], locals:[gsub, insert, concat, reasons]
	char const * patterns[] = {
		"?.lua",
		"?/?.lua",
	};
#define countof(x)	(sizeof(x)/sizeof(*(x)))
	for (int i = 0; i < countof(patterns); ++i) {
		lua_pushvalue(L, gsubloc);		// stack: [args&locals], gsub
		lua_pushstring(L, patterns[i]);	// stack: [args&locals], gsub, patterns[i]
		lua_pushliteral(L, "%?");		// stack: [args&locals], gsub, patterns[i], "%?"

		lua_pushvalue(L, gsubloc);		// stack: [args&locals], gsub, patterns[i], "%?", gsub
		lua_pushvalue(L, 1);			// stack: [args&locals], gsub, patterns[i], "%?", gsub, mod
		lua_pushliteral(L, "%.");		// stack: [args&locals], gsub, patterns[i], "%?", gsub, mod, "%."
		lua_pushliteral(L, "/");		// stack: [args&locals], gsub, patterns[i], "%?", gsub, mod, "%.", "/"
		lua_call(L, 3, 1);				// stack: [args&locals], gsub, patterns[i], "%?", mod:gsub('%.','/')

		lua_call(L, 3, 1);				// stack: [args&locals], fn = opt:gsub('%?',(modname:gsub('%.','/')))
		int fnloc = lua_gettop(L);

		lua_pushcfunction(L, java_isAssetPathDir);	// stack: [args&locals], fn, java_isAssetPathDir
		lua_pushvalue(L, fnloc);					// stack: [args&locals], fn, java_isAssetPathDir, fn
		lua_call(L, 1, 1);							// stack: [args&locals], fn, isdir?
		if (lua_toboolean(L, -1)) {
			// is directory
			lua_pop(L, 1);							// stack: [args&locals], fn
			
			char const * errmsg = "is an asset dir: ";
			lua_pushvalue(L, insertloc);			// stack: [args&locals], fn, insert
			lua_pushvalue(L, reasonsloc);			// stack: [args&locals], fn, insert, reasons
			lua_pushstring(L, errmsg);				// stack: [args&locals], fn, insert, reasons, "is an asset dir: "
			lua_pushvalue(L, fnloc);				// stack: [args&locals], fn, insert, reasons, "is an asset dir: ", fn
			lua_concat(L, 2);						// stack: [args&locals], fn, insert, reasons, "is an asset dir: "..fn
			lua_call(L, 2, 0);						// stack: [args&locals], fn 	| table.insert(reasons, "is an asset dir: "..fn)
			lua_pop(L, 1);							// stack: [args&locals]
		} else {
			// is file
			lua_pop(L, 1);								// stack: [args&locals], fn
			lua_pushcfunction(L, java_readAssetPath);	// stack: [args&locals], fn, java_readAssetPath
			lua_pushvalue(L, fnloc);					// stack: [args&locals], fn, java_readAssetPath, fn
			lua_call(L, 1, 1);							// stack: [args&locals], fn, data = java_readAssetPath(fn)
			if (!lua_toboolean(L, -1)) {
				// not a file
				lua_pop(L, 1);							// stack: [args&locals], fn
				
				char const * errmsg = "not an asset path: ";
				lua_pushvalue(L, insertloc);
				lua_pushvalue(L, reasonsloc);
				lua_pushstring(L, errmsg);
				lua_pushvalue(L, fnloc);
				lua_concat(L, 2);
				lua_call(L, 2, 0);
				lua_pop(L, 1);
			} else {
				// is a file
				lua_getglobal(L, "load");				// stack: [args&locals], fn, data, load
				lua_insert(L, -2);						// stack: [args&locals], fn, load, data
				lua_pushvalue(L, modloc);				// stack: [args&locals], fn, load, data, mod
				lua_call(L, 2, 2);						// stack: [args&locals], fn, result, errmsg
				if (lua_toboolean(L, -2)) {
					// got a result
					lua_pop(L, 1);
					return 1;
				} else {
					// got an error
					int errmsgloc = lua_gettop(L);

					lua_pushvalue(L, insertloc);			// stack: [args&locals], fn, result, errmsg, insert
					lua_pushvalue(L, reasonsloc);			// stack: [args&locals], fn, result, errmsg, insert, reasons
					lua_pushvalue(L, fnloc);				// stack: [args&locals], fn, result, errmsg, insert, reasons, fn
					lua_pushliteral(L, " ");				// stack: [args&locals], fn, result, errmsg, insert, reasons, fn, " "

					lua_getglobal(L, "tostring");			// stack: [args&locals], fn, result, errmsg, insert, reasons, fn, " ", tostring
					lua_pushvalue(L, errmsgloc);			// stack: [args&locals], fn, result, errmsg, insert, reasons, fn, " ", tostring, errmsg
					lua_call(L, 1, 1);						// stack: [args&locals], fn, result, errmsg, insert, reasons, fn, " ", tostring(errmsg)
					
					lua_concat(L, 3);						// stack: [args&locals], fn, result, errmsg, insert, reasons, fn.." "..tostring(errmsg)
					lua_call(L, 2, 0);						// stack: [args&locals], fn, result, errmsg 	| table.insert(reasons, fn.." "..tostring(errmsg))
					lua_pop(L, 3);							// stack: [args&locals]
				}
			}
		}
	}

	// stack: [args&locals]

	lua_pushliteral(L, "module '");				// stack: [args&locals] "module '"
	lua_pushvalue(L, modloc);					// stack: [args&locals] "module '", mod
	lua_pushliteral(L, "' not found:\n\t");		// stack: [args&locals] "module '", mod, "' not found:\n\t"

	lua_pushvalue(L, concatloc);		// stack: [args&locals] "module '", mod, "' not found:\n\t", concat
	lua_pushvalue(L, reasonsloc);		// stack: [args&locals] "module '", mod, "' not found:\n\t", concat, reasons
	lua_pushliteral(L, "\n\t");			// stack: [args&locals] "module '", mod, "' not found:\n\t", concat, reasons, "\n\t"
	lua_call(L, 2, 1);					// stack: [args&locals] "module '", mod, "' not found:\n\t", reasons:concat'\n\t'

	lua_concat(L, 4);					// stack: [args&locals] "module '"..mod.."' not found:\n\t"..reasons:concat'\n\t'
	return 1;
}

/*
run this per new Lua state
it does the following:
- setup initial libs
- set ffi.os = Android
- add the asset loader

so I'm doing this in lua-lua's Lua:init to make sure all new sub-Lua-states have the asset loader:

	-- BEGIN PATCH for luajit-android to insert the android asset loader into any newly created Lua states
	do
		local main = ffi.load'main'
		ffi.cdef[[int androidLuajitInitState(void *L);]]
		main.androidLuajitInitState(self.L)

		-- now that the asset loader is setup,
		-- load JNI and set the android JNI as our `require "java"`
		self[=[
require 'java.ffi.jni'	-- cdef for JNIEnv
ffi.cdef[[JNIEnv * jniEnv;]]
local JNIEnv = require 'java.jnienv'
local main = ffi.load'main'
local J = JNIEnv{
	ptr = main.jniEnv,
	usingAndroidJNI = true,
}
print('J', J)
package.loaded.java = J
package.loaded['java.java'] = J
]=]
	end
	-- END PATCH for luajit-android

*/
int androidLuajitInitState(lua_State *L) {
	// change ffi.os to Android
	//dolibrary clears the result so...
	lua_getglobal(L, "require");	// stack: require
	lua_pushstring(L, "ffi");		// stack: require ffi
	int status = safecall(L, 1, 1);	// stack: ffi
	if (status != LUA_OK) {
		report(L, status);
		return 0;
	}

	lua_pushliteral(L, "Android");	// stack: ffi Android
	lua_setfield(L, -2, "os");		// stack: ffi

	lua_pop(L, 1);					// stack:

	lua_getglobal(L, "table");					// stack: table
	lua_getfield(L, -1, "insert");				// stack: table, table.insert
	lua_remove(L, -2);							// stack: table.insert
	lua_getglobal(L, "package");				// stack: table.insert, package
	lua_getfield(L, -1, "loaders");				// stack: table.insert, package, package.loaders
	lua_remove(L, -2);							// stack: table.insert, package.loaders
	lua_pushcfunction(L, androidAssetLoader);	// stack: table.insert, package.loaders, androidAssetLoader
	lua_call(L, 2, 0);							// stack:

	return 0;
}

/* 
run this once per app starting
it launches main.lua and gets the callback for the Activity methods
*/
static int androidLuajitStartApp(lua_State *L) {
	struct Smain *s = &smain;
	mainL = L;

	lua_gc(L, LUA_GCSTOP, 0);
	luaL_openlibs(L);				// stack:
	lua_gc(L, LUA_GCRESTART, -1);

	androidLuajitInitState(L);

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

	int status = lua_cpcall(L, androidLuajitStartApp, NULL);
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
