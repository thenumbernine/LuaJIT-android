-- this is the LuaJIT app's main.lua is currently pointed
-- it is distinct of the SDLLuaJIT in that it has a minimal bootstrap that points it squarely to lua-java and the assets apk loader
-- from there I will load more files from here
-- and then write stupid android apps
local ffi = require 'ffi'
local J = require 'java'

--print('_G='..tostring(_G)..', jniEnv='..tostring(J._ptr))
--print('Android API:', J.android.os.Build.VERSION.SDK_INT)

-- rebuild args cast to their instanciated class
local function recastArgs(...)
	if select('#', ...) == 0 then return end
	local arg = ...
	if arg ~= nil then arg = J:_fromJObject(arg._ptr) end
	return arg, recastArgs(select(2, ...))
end

local MENU_CHOOSE_FOLDER = 1

-- these callbacks are centered around the original activity
-- you can make a new activity and then provide its callbacks in Lua
	-- in order of how Android handles it:
local callbacks = {
	onCreate = function(activity, ...)
		activity.super:onCreate(...)

		local LinearLayout = J.android.widget.LinearLayout
		local root = LinearLayout(activity)
		local ViewGroup = J.android.view.ViewGroup
		root:setLayoutParams(ViewGroup.LayoutParams(-1, -1))

		local toolbar = J.android.widget.Toolbar(activity)
		toolbar:setTitle'Image Preview Grid'
		toolbar:setBackgroundColor(0xFF6200EE)
		toolbar:setTitleTextColor(0xFFFFFFFF)
		root:addView(toolbar)

		local scrollView = J.android.widget.ScrollView(activity)
		scrollView:setLayoutParams(LinearLayout.LayoutParams(-1, -1))

		local GridLayout = J.android.widget.GridLayout
		local gridLayout = GridLayout(activity)
		gridLayout:setColumnCount(3)
		gridLayout:setLayoutParams(ViewGroup.LayoutParams(-1, -2))	-- WRAP_CONTENT height

		local function populateGridWithImages(grid)
			local imageDir = J.java.io.File(J.android.os.Environment:getExternalStorageDirectory(), 'Pictures')
			if imageDir:exists() and imageDir:isDirectory() then
				local files = imageDir:listFiles()
				if files ~= nil then
					local screenWidth = activity:getResources():getDisplayMetrics().widthPixels
					local imageSize = screenWidth / 3
					for file in files:_iter() do
						local ImageView = J.android.widget.ImageView
						local imageView = ImageView(activity)

						local params = GridLayout.LayoutParams()
						params.width = imageSize
						params.height = imageSize
						imageView:setLayoutParams(params)

						imageView:setScaleType(ImageView.ScaleType.CENTER_CROP)
						imageView:setPadding(4,4,4,4)
						imageView:setImageURI(J.android.net.Uri:fromFile(file))
						grid:addView(imageView)
					end
				end
			end
		end

		populateGridWithImages(gridLayout)

		scrollView:addView(gridLayout)
		root:addView(scrollView)
		activity:setContentView(root)
	end,

	onBackPressed = function(activity, ...)
		--activity.super:onBackPressed(...)
		activity:finish()
	end,

	-- TODO why doesn't this work below?
	onTrimMemory = function(activity, level)
		return activity.super:onTrimMemory(level)
	end,

	onCreateOptionsMenu = function(activity, menu)
		menu:add(0, MENU_CHOOSE_FOLDER, 0, 'Choose Folder')
			:setShowAsAction(J.android.view.MenuItem.SHOW_AS_ACTION_IF_ROOM)
		return true
	end,

	onOptionsItemSelected = function(activity, item)
		if item:getItemId() == MENU_CHOOSE_FOLDER then
			activity:openFolderPicker()
			return true
		end
		return activity.super:onOptionsItemSelected(item)
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
	local result

	-- get the return type / what I'll need to cast this to
	local method = require 'java.callresolve'.resolve(
		methodName,
		activity:_getClass()._methods[methodName],
		activity,
		recastArgs(args:_unpack()))
	if method == nil then
		print("!!! WARNING !!! couldn't get activity method for "..methodName)
	end

	local callback = callbacks[methodName]
	if callback then
		result = callback(activity, recastArgs(args:_unpack()))
	else
		local super = activity.super
		result = super[methodName](super, recastArgs(args:_unpack()))
	end

print('java:', methodName, 'returning', result)
	local infoForPrims = require 'java.util'.infoForPrims
	local primInfo = method and infoForPrims[method._sig[1]]
	if primInfo then
		result = J[primInfo.boxedType](result)
print('...boxed and returning', result._ptr)
	end
	return result
end
