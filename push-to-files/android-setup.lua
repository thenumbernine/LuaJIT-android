--[[ these are set upon app init:
local function showenvvar(var)
	print(var, os.getenv(var))
end
showenvvar'APP_PACKAGE_NAME'
--
showenvvar'APP_FILES_DIR' -- /data/user/0/$APP_PACKAGE_NAME
showenvvar'APP_CACHE_DIR'
showenvvar'APP_DATA_DIR'
-- both /data/app/~~sagOtG7hLwKdTrVfctEkIw==/io.github.thenumbernine.SDLLuaJIT-TabWhHRksmn0DykywPgr_w==/base.apk
showenvvar'APP_RES_DIR'
showenvvar'APP_PACKAGE_CODE_DIR'
-- folder on sdcard?
showenvvar'APP_EXTERNAL_CACHE_DIR'
--exec'set'

-- nothing there
--exec('ls -al '..os.getenv'APP_RES_DIR')

TODO now that LuaJIT has Java access, I don't need to set the env vars anymore!
--]]

-- LuaJIT access to JNI ...
require 'java.ffi.jni'	-- cdef for JNIEnv

local ffi = require 'ffi'
local main = ffi.load'main'
print('main', main)

ffi.cdef[[JNIEnv * jniEnvSDLMain;]]
local JNIEnv = require 'java.jnienv'
local J = JNIEnv{
	ptr = main.jniEnvSDLMain,
	usingAndroidJNI = true,
}
print('J', J)
package.loaded.java = J	-- make `require 'java'` return our Android JNIEnv

--[[ mostly works. mostly.
local path = require 'ext.path'
path'java/tests/luaclass':cd()
dofile'test.lua'
do return end
--]]

-- alright at this point ...
-- this is just as well 'main()'
-- I could launch the org.libsdl.app.SDLActivity myself and not even bother with the rest
-- TODO this eventually, circumvent all SDL if possible ...
-- but for now I'm using SDL to set things up at least.

-- now why did I even bother with this?
-- because I wanted to access the assets/ folder
local SDLActivity = J.org.libsdl.app.SDLActivity
assert(SDLActivity._exists)
print('verison', SDLActivity:nativeGetVersion())

-- TODO better way to get our running app's activity?
local context = SDLActivity:getContext()
print('context', context)

local M = {}

M.packageName = tostring(context:getPackageName())
print('packageName', M.packageName)

local appFilesDir = context:getFilesDir():getAbsolutePath()
M.appFilesDir = appFilesDir
print('appFilesDir', appFilesDir)

M.appResDir = context:getPackageResourcePath()
print('appResDir', M.appResDir)

M.appCacheDir = context:getCacheDir():getAbsolutePath()
print('appCacheDir', M.appCacheDir)

M.appDataDir = context:getDataDir():getAbsolutePath()
print('appDataDir', M.appDataDir)

M.appExtCacheDir = context:getExternalCacheDir():getAbsolutePath()
print('appExtCacheDir', M.appExtCacheDir)

M.appPackageCodeDir = context:getPackageCodePath()
print('appPackageCodeDir', M.appPackageCodeDir)

-- [===[ don't need to do this snice I *must* do it on apk startup
function M.copyAssetsToFiles()
	local dontCopyFromAssetsFilename = appFilesDir..'/dontcopyfromassets'
	local dontCopyFromAssetsExists = io.open(dontCopyFromAssetsFilename, 'r')
	if not dontCopyFromAssetsExists then
		local assets = context:getAssets()
		print('assets', assets)

		local File = J.java.io.File
		local FileOutputStream = J.java.io.FileOutputStream

		local function copyAssets(f)
			local toPath = appFilesDir..'/'..f
			local toFile = File(toPath)
			local list = assets:list(f)	-- root is ''
			local n = #list
			if n == 0 then
print(f)--, 'is', is, is_close)
				-- no files?  its either not a dir, or its an empty dir
				-- no way to tell in Android, fucking retarded

				local is = asserts:open(f)
				local os = FileOutputStream(toFile)
				-- is:transferTo(os) ... not available in my version?
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
				-- is dir so we can mkdirs
				toFile:mkdirs()

				for i=0,n-1 do
					-- how to determine subfolder?
					-- official way?
					-- try to query it with list()
					local subf = list[i]
					local path = f == '' and subf or f..'/'..subf
--DEBUG:print(path)
					copyAssets(path)
				end
			end
		end
		copyAssets''

		-- write that we did copy the files
		assert(io.open(dontCopyFromAssetsFilename, 'w')):close()
	end
end
--]===]

-- while we're here, can we do FFM?

print('J:_version()', ('0x%x'):format(J:_version()))
local props = J.System:getProperties()
for key in props:keySet():_iter() do
	print('', key, ('%q'):format(tostring(props:getProperty(key))))
end
-- iterator only had 3 props: java.io.tmpdir, http.agent, user.home

print('java.version', J.System:getProperty'java.version')	-- 0
print('java.specification.version', J.System:getProperty'java.specification.version')
print('java.runtime.version', J.System:getProperty'java.runtime.version')
print('os.version', J.System:getProperty'os.version')	-- 0
print('java.vm.specification.version', J.System:getProperty'java.vm.specification.version')
print('java.vm.version', J.System:getProperty'java.vm.version')
print('java.class.version', J.System:getProperty'java.class.version')

--[[ works
assert(J.Runnable._exists)
J.Runnable(function(this)
	print('hello from within Lua') --this)
end):run()
do return end
--]]

--[[ works
local NativeCallback = require 'java.nativecallback'(J)
print('NativeCallback', NativeCallback)
print('NativeCallback.run', NativeCallback.run)
function func(arg)
	print('hello from lua->java->lua!', arg)
end
closure = ffi.cast('void*(*)(void*)', func)
-- hmm, callback not working yet
--NativeCallback:run(ffi.cast('jlong', closure), nil)	-- ./java/jnienv.lua:502: JVM java.lang.VerifyError: Verifier rejected class io.github.thenumbernine.SDLLuaJIT.NativeCallback: void io.github.thenumbernine.SDLLuaJIT.NativeCallback.<init>(): [0xFFFFFFFF] invalid arg count (0) in non-range invoke (declaration of 'io.github.thenumbernine.SDLLuaJIT.NativeCallback' appears in /data/user/0/io.github.thenumbernine.SDLLuaJIT/Anonymous-DexFile@3943120431.jar)	
--NativeCallback:run(ffi.cast('jlong', closure), NativeCallback.class)
local run = NativeCallback._methods.run[1]
--run(NativeCallback, ffi.cast('jlong', closure), J.Object())
run(NativeCallback, J.Long:valueOf(ffi.cast('jlong', closure)), J.Object())
--]]


--[[ can I make a new Activity?
local NewActivity = require 'java.luaclass'{
	superClass = 'android.app.Activity',
}
startActivity(
	J.android.content.Intent(
		context? SDLActivity.class ?,--MainActivity.this,
		NewActivity.class
	)
)
--]]
-- [[ or make a new view?
local activity = context:_cast'android.app.Activity'	-- because its a subclass, right?
print('activity', activity)
local LinearLayout = J.android.widget.LinearLayout
assert(LinearLayout._exists)
local mainLayout = LinearLayout(activity)
mainLayout:setOrientation(LinearLayout.VERTICAL)
local ViewGroup = J.android.view.ViewGroup
assert(ViewGroup._exists)
local layoutParams = LinearLayout.LayoutParams(
	ViewGroup.LayoutParams.MATCH_PARENT,
	ViewGroup.LayoutParams.MATCH_PARENT
)
mainLayout:setLayoutParams(layoutParams)
-- "JVM android.view.ViewRootImpl$CalledFromWrongThreadException: Only the original thread that created a view hierarchy can touch its views."
activity:setContentView(mainLayout)
--]]

return M
