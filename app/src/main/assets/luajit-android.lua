-- this is the LuaJIT app's main.lua is currently pointed
-- it is distinct of the SDLLuaJIT in that it has a minimal bootstrap that points it squarely to lua-java and the assets apk loader
-- from there I will load more files from here
-- and then write stupid android apps
local ffi = require 'ffi'
local J = require 'java'
local JavaCallResolve = require 'java.callresolve'
local infoForPrims = require 'java.util'.infoForPrims

local M = {}
--print('_G='..tostring(_G)..', jniEnv='..tostring(J._ptr))
--print('Android API:', J.android.os.Build.VERSION.SDK_INT)

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
		
			local files = {}
			--[[ androidx method
			local directory = J.androidx.documentfile.provider.DocumentFile:fromTreeUri(activity, treeUri)
			for file in directory:listFiles():_iter() do
				table.insert(files, {
					type = file:getType(),
					uri = file:getUri(),
				})
			end
			--]]
			-- [[
			local DocumentsContract = J.android.provider.DocumentsContract
			local childrenUri = DocumentsContract:buildChildDocumentsUriUsingTree(
				treeUri,
				DocumentsContract:getTreeDocumentId(treeUri)
			)
			-- TODO build string from Lua table...
			local cols = J:_newArray(J.String, 3);
			cols[0] = DocumentsContract.Document.COLUMN_DISPLAY_NAME;
			cols[1] = DocumentsContract.Document.COLUMN_DOCUMENT_ID;
			cols[2] = DocumentsContract.Document.COLUMN_MIME_TYPE;
			local cursor = activity:getContentResolver():query(childrenUri, cols, nil, nil, nil)
			while cursor:moveToNext() do
				local displayName = cursor:getString(0)
				local docId = cursor:getString(1)
				local fileType = cursor:getString(2)
				local fileUri = DocumentsContract:buildDocumentUriUsingTree(treeUri, docId)
				table.insert(files, {
					type = fileType,
					uri = fileUri,
				})
			end
			cursor:close()
			--]]

			local gridLayout = M.gridLayout
			gridLayout:removeAllViews()
			local size = activity:getResources():getDisplayMetrics().widthPixels / 3
			for _,file in ipairs(files) do
				local fileType = file.type
				if fileType ~= nil then
					fileType = tostring(fileType)
					if fileType:match'^image/' then
						-- ... do something here
						local img = ImageView(activity)
						img:setLayoutParams(ViewGroup.LayoutParams(size, size))
						img:setScaleType(ImageView.ScaleType.CENTER_CROP)
						img:setImageURI(file.uri)
						gridLayout:addView(img)
					end
				end
			end
		end
	end,
}

return function(methodName, activity, ...)
	print(methodName, activity, ...)
	local callback = callbacks[methodName]
	if callback then
		return callback(activity, ...)
	end
	local super = activity.super
	return super[methodName](super, ...)
end
