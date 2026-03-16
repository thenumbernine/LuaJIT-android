local ffi = require 'ffi'

-- [=[
-- chdir to our lua projects root
-- tempting ot make this dir configurable in the app
ffi.cdef[[int chdir(const char *path);]]
local function chdir(s)
	local res = ffi.C.chdir((assert(s)))
	assert(res==0, 'chdir '..tostring(s)..' failed')
end
--[[
The biggest pain point of this entire project is the /data app folder.
Android has designed itself to make accessing it as painful as possible. For no reason.
So here's me redirecting everything to sdcard upon init.
--]]
local projectDir = '/sdcard/Documents/Projects/lua'
chdir(projectDir)
--]=]


-- setup LUA_PATH and LUA_CPATH here
package.path = table.concat({
	'./?.lua',
	projectDir..'/?.lua',
	projectDir..'/?/?.lua',
}, ';')
package.cpath = table.concat({
	'./?.so',
	projectDir..'/?.so',
	projectDir..'/?/init.so',
}, ';')

-- TODO this in C?
ffi.cdef[[int setenv(const char*,const char*,int);]]
ffi.C.setenv('LUA_PATH', package.path, 1)
ffi.C.setenv('LUA_CPATH', package.cpath, 1)


-- [=[
-- setup the asset based package loader:
local reg = debug.getregistry()
local java_readAssetPath = reg.java_readAssetPath
local java_isAssetPathDir = reg.java_isAssetPathDir
table.insert(package.loaders, function(modname)
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
				local res, err = load(data)
				if res then return res end
				table.insert(reasons, fn..' '..tostring(err))
			end
		end
	end
	return "module '"..modname.."' not found:\n\t"
		..table.concat(reasons, '\n\t')
end)

-- setup the JNI env object:

require 'java.ffi.jni'	-- cdef for JNIEnv
local ffi = require 'ffi'
local main = ffi.load'main'
ffi.cdef[[JNIEnv * jniEnv;]]
local JNIEnv = require 'java.jnienv'
local J = JNIEnv{
	ptr = main.jniEnv,
	usingAndroidJNI = true,
}
print('J', J)
package.loaded.java = J
package.loaded['java.java'] = J
--]=]

print('BEGIN android main.lua')
local activityMethodHandler = require 'luajit-android'
print('DONE android main.lua')


-- return our callback, with wrapper for jni to lua-java args
-- handle unpacking vararg Object[] to its individual args' proper JavaObject classes
-- and handle packing/unpacking to/from boxed types


local function recastObj(obj)
	if obj == nil then return nil end
	return J:_fromJObject(obj._ptr) or nil
end

local function recastObjs(...)
	if select('#', ...) == 0 then return end
	return recastObj(...), recastObjs(select(2, ...))
end

local infoForPrims = require 'java.util'.infoForPrims
local JavaCallResolve = require 'java.callresolve'
local Activity = J.android.app.Activity

-- TODO this will go bad if J changes
return function(methodName, activity, args)
	activity = J:_fromJObject(ffi.cast('jobject', activity))
	args = J:_fromJObject(ffi.cast('jobject', args))
	
	-- get the return type / what I'll need to cast this to
	local activityMethodsForName = Activity._methods[methodName]
	-- [[
	local method = JavaCallResolve.resolve(
		methodName,
		activityMethodsForName,
		activity,
		recastObjs(args:_unpack()))
	--]]
	if method == nil then
		print("!!! WARNING !!! couldn't get activity method for "..methodName)
		print('...based on args...')
		print('#args', select('#', recastObjs(args:_unpack())))
		for i=0,#args-1 do
			print('arg['..i..'] =', (recastObj(args[i]) or {})._classpath, recastObj(args[i]))
		end

		print('and options for Activity.'..methodName)
		for _,option in ipairs(activityMethodsForName) do
			print('', option._name, require 'ext.tolua'(option._sig), option._class)
		end

		-- it says it can convert, so why isn't it when picking the method signature for call resolve?
		--print(J:_canConvertLuaToJavaArg(J.Boolean(true), 'boolean'))	-- true
		--print(J:_canConvertLuaToJavaArg(recastObj(args[0]), activityMethodsForName[1]._sig[2]))	-- also true
	end

	local result = activityMethodHandler(methodName, activity, recastObjs(args:_unpack()))

print('java:', methodName, 'returning', result)
	-- now prepare the result for the JNI layer
	if result == nil then return 0 end
	local primInfo = method and infoForPrims[method._sig[1]]
	if primInfo then
		result = J[primInfo.boxedType](result)._ptr
print('...boxed and returning', result)
	end
	return assert(tonumber(ffi.cast('uintptr_t', result)))
end
