local ffi = require 'ffi'

--[=[
-- chdir to our lua projects root
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
local f = require 'luajit-android'
print('DONE android main.lua')

-- return our callback
return f
