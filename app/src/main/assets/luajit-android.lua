-- this is the LuaJIT app's main.lua is currently pointed
-- it is distinct of the SDLLuaJIT in that it has a minimal bootstrap that points it squarely to lua-java and the assets apk loader
-- from there I will load more files from here
-- and then write stupid android apps
local ffi = require 'ffi'
local assert = require 'ext.assert'
local J = require 'java'
local JavaCallResolve = require 'java.callresolve'
local infoForPrims = require 'java.util'.infoForPrims

local M = {}
--print('_G='..tostring(_G)..', jniEnv='..tostring(J._ptr))
--print('Android API:', J.android.os.Build.VERSION.SDK_INT)

-- rebuild args cast to their instanciated class
local function recastObj(obj)
	if obj == nil then return nil end
	return J:_fromJObject(obj._ptr) or nil
end
local function recastObjs(...)
	if select('#', ...) == 0 then return end
	return recastObj(...), recastObjs(select(2, ...))
end

local Intent = J.android.content.Intent
local Activity = J.android.app.Activity
local LinearLayout = J.android.widget.LinearLayout
local ViewGroup = J.android.view.ViewGroup
local ImageView = J.android.widget.ImageView

local MENU_CHOOSE_FOLDER = 1

-- these callbacks are centered around the original activity
-- you can make a new activity and then provide its callbacks in Lua
	-- in order of how Android handles it:
local callbacks = {
	onCreate = function(activity, ...)
		activity.super:onCreate(...)

		local root = LinearLayout(activity)
		root:setLayoutParams(ViewGroup.LayoutParams(-1, -1))

		local toolbar = J.android.widget.Toolbar(activity)
		toolbar:setTitle'Image Preview Grid'
		toolbar:setBackgroundColor(0xFF6200EE)
		toolbar:setTitleTextColor(0xFFFFFFFF)
		root:addView(toolbar)

		local scrollView = J.android.widget.ScrollView(activity)
		scrollView:setLayoutParams(LinearLayout.LayoutParams(-1, -1))

		local gridLayout = J.android.widget.GridLayout(activity)
M.gridLayout = gridLayout
		gridLayout:setColumnCount(3)
		gridLayout:setLayoutParams(ViewGroup.LayoutParams(-1, -2))	-- WRAP_CONTENT height

		scrollView:addView(gridLayout)
		root:addView(scrollView)
		activity:setContentView(root)
	end,

	onBackPressed = function(activity, ...)
		--activity.super:onBackPressed(...)
		activity:finish()
	end,

	onCreateOptionsMenu = function(activity, menu)
		menu:add(0, MENU_CHOOSE_FOLDER, 0, 'Choose Folder')
			:setShowAsAction(J.android.view.MenuItem.SHOW_AS_ACTION_IF_ROOM)
		return true
	end,

	onOptionsItemSelected = function(activity, item)
		local function openFolderPicker()
			local intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
			intent:addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
			activity:startActivityForResult(intent, 9999)
		end

		if item:getItemId() == MENU_CHOOSE_FOLDER then
			openFolderPicker()
			return true
		end
		return activity.super:onOptionsItemSelected(item)
	end,

	onActivityResult = function(activity, requestCode, resultCode, data)
		activity.super:onActivityResult(requestCode, resultCode, data)

		if requestCode:intValue() == 9999
		and resultCode:intValue() == Activity.RESULT_OK
		then
			local treeUri = data:getData()
			activity:getContentResolver():takePersistableUriPermission(treeUri, Intent.FLAG_GRANT_READ_URI_PERMISSION)

			local pickedDir = J.androidx.documentfile.provider.DocumentFile:fromTreeUri(activity, treeUri)

			local function loadImagesFromDocument(directory)
				local gridLayout = M.gridLayout
				gridLayout:removeAllViews()
				local size = activity:getResources():getDisplayMetrics().widthPixels / 3
				for file in directory:listFiles():_iter() do
					local fileType = file:getType()
					if fileType ~= nil then
						fileType = tostring(fileType)
						if fileType:match'^image/' then
							-- ... do something here
							local img = ImageView(activity)
							img:setLayoutParams(ViewGroup.LayoutParams(size, size))
							img:setScaleType(ImageView.ScaleType.CENTER_CROP)

							img:setImageURI(file:getUri())

							gridLayout:addView(img)
						end
					end
				end
			end
			loadImagesFromDocument(pickedDir)
		end
	end,
}

return function(methodName, activity, args)
	activity = J:_fromJObject(ffi.cast('jobject', activity))
	args = J:_fromJObject(ffi.cast('jobject', args))
print()
print(methodName, activity, args:_unpack())
--[[
print('arg classes:')
for i=0,#args-1 do
	local argi = args[i]
	print(i, argi and J:_fromJObject(argi._ptr)._classpath or 'null')
end
--]]
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
		for _,prim in ipairs(require 'java.util'.prims) do
			local info = infoForPrims[prim]
			print('', info.name..' <=> '..info.boxedType)
		end

		print('and options for Activity.'..methodName)
		for _,option in ipairs(activityMethodsForName) do
			print('', option._name, require 'ext.tolua'(option._sig), option._class)
		end

		-- it says it can convert, so why isn't it when picking the method signature for call resolve?
		--print(J:_canConvertLuaToJavaArg(J.Boolean(true), 'boolean'))	-- true
		--print(J:_canConvertLuaToJavaArg(recastObj(args[0]), activityMethodsForName[1]._sig[2]))	-- also true
	end

	-- TODO here now we might have to unbox primitives ...

	local callback = callbacks[methodName]
	local result
	if callback then
		result = callback(activity, recastObjs(args:_unpack()))
	else
		local super = activity.super
		result = super[methodName](super, recastObjs(args:_unpack()))
	end
print('java:', methodName, 'returning', result)

	-- now prepare the result for the JNI layer
	if result == nil then return 0 end
	local primInfo = method and infoForPrims[method._sig[1]]
	if primInfo then
		result = J[primInfo.boxedType](result)._ptr
print('...boxed and returning', result)
	end
	assert.type(result, 'cdata')
	return assert(tonumber(ffi.cast('uintptr_t', result)))
end
