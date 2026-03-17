-- instead of a bootstrap io loader, how about the old fashioned SDLLuaJIT way of just copying files across?
-- it works a lot cleaner
-- but we still need the bootstrap loader to load lua-java to then do this
-- (unless I want to do the copying in java)

local ffi = require 'ffi'


--[=[
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
--]=]


local main = ffi.load'main'

--[=[ I don't need to copy all files over for sub-lua-states if I can shim in the asset loader into the sub-lua-states ...
do

	local lualib = require 'lua.ffi'	-- needed for lua_State def
	ffi.cdef[[
int java_isAssetPathDir(lua_State *L);
int java_readAssetPath(lua_State *L);
]]

	--[[ 
	in order for lite-thread to work, the new lua state needs to require files
	but currently all files are retrieved using the assets/ reader
	and a new lua state won't have it
	so hand it off with a subclass
	(you have to do this before ever requiring any lite-threads, i.e. before requiring 
	--]]

	local LiteThread = require 'thread.lite'
	local NewLiteThread = LiteThread:subclass()
	function NewLiteThread:init(args, ...)
		if type(args) == 'string' then
			args = {code=args}
		elseif type(args) == 'function' then
			args = {func=args}
		end
		
		local oldinit = args.init
		args.init = function(thread, ...)
			local lua = thread.lua
			local L = lua.L

			lualib.lua_pushcclosure(L, main.java_readAssetPath, 0)
			lualib.lua_setfield(L, lualib.LUA_REGISTRYINDEX, 'java_readAssetPath')
			lualib.lua_pushcclosure(L, main.java_isAssetPathDir, 0)
			lualib.lua_setfield(L, lualib.LUA_REGISTRYINDEX, 'java_isAssetPathDir')

			lua[[
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
]]
			return oldinit(thread, ...)
		end

		return LiteThread.init(self, args, ...)
	end
	package.loaded['thread.lite'] = NewLiteThread 
end
--]=]


-- setup the JNI env object:

require 'java.ffi.jni'	-- cdef for JNIEnv
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


--[=[
-- now that we're here with lua-java, copy assets into files unless told otherwise
-- pro: now sub-lua-states can load files correctly
-- con: few seconds initial load time.  have to wipe files/ or at least the lock file when you update things.
-- hmm, this is a few seconds that I don't want ... and the asset loader works fine except that it isn't auto-added into new sub Lua states ... how to work around this ...
do
	ffi.cdef[[jobject androidActivity;]]
	local activity = J:_fromJObject(main.androidActivity)
	local filesDir = activity:getFilesDir()
	local File = J.java.io.File
	local lockFile = File(filesDir, 'dontcopyfromassets')
	if not lockFile:exists() then
		local function copyAssets(assets, f, appFilesDir)
			local toFile = File(appFilesDir .. '/' .. f)
			local list = assets:list(f)
			local n = #list
			if n == 0 then
				local is = assets:open(f)
				local os = J.java.io.FileOutputStream(toFile)

				local buf = J:_newArray('byte', 16384)
				while true do
					local res = is:read(buf)
					if res <= 0 then break end
					os:write(buf, 0, res)
				end

				is:close()
				os:flush()
				os:close()
			else
				toFile:mkdirs()
				for subf in list:_iter() do
					copyAssets(
						assets,
						f == '' and subf or f .. '/' .. subf,
						appFilesDir
					)
				end
			end
		end
		copyAssets(
			activity:getAssets(),
			'',
			tostring(filesDir:getAbsolutePath())
		)
		lockFile:createNewFile()
	end
	-- tada, now we have file access
	-- now sub lua states don't need the asset loader
	-- now this lua state doesn't even need it.
	table.remove(package.loaders)

	local projectDir = tostring(filesDir:getAbsolutePath())

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

	-- switch to pure-lua require so i can see errors from files that fail
	--require 'ext.require'(_G)

	ffi.cdef[[int setenv(const char*,const char*,int);]]
	-- let subsequent invoked lua processes know where to find things
	ffi.C.setenv('LUA_PATH', package.path, 1)
	ffi.C.setenv('LUA_CPATH', package.cpath, 1)
end
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
---DEBUG:print('activity.L', '0x'..bit.tohex(activity.L, 8))

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

---DEBUG:print('java:', methodName, 'returning', result)
	-- now prepare the result for the JNI layer
	if result == nil then return 0 end
	local primInfo = method and infoForPrims[method._sig[1]]
	if primInfo then
		result = J[primInfo.boxedType](result)._ptr
---DEBUG:print('...boxed and returning', result)
	end
	return assert(tonumber(ffi.cast('uintptr_t', result)))
end
