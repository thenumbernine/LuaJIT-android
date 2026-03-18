-- this is the LuaJIT app's main.lua is currently pointed
-- it is distinct of the SDLLuaJIT in that it has a minimal bootstrap that points it squarely to lua-java and the assets apk loader
-- from there I will load more files from here
-- and then write stupid android apps
local ffi = require 'ffi'
local J = require 'java'

--print('_G='..tostring(_G)..', jniEnv='..tostring(J._ptr))
--print('Android API:', J.android.os.Build.VERSION.SDK_INT)


--[=======[ directory image gallery example

local Intent = J.android.content.Intent
local Activity = J.android.app.Activity
local LinearLayout = J.android.widget.LinearLayout
local ViewGroup = J.android.view.ViewGroup
local ImageView = J.android.widget.ImageView

local MENU_CHOOSE_FOLDER = 1

local gridLayout

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

		gridLayout = J.android.widget.GridLayout(activity)
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

--]=======]
-- [=======[ attempt at just outputting the out.txt file

local observer
local callbacks = {
	onCreate = function(activity, savedInstanceState)
		activity.super:onCreate(savedInstanceState)

		local ViewGroup = J.android.view.ViewGroup

        local textView = J.android.widget.TextView(activity)
        textView:setLayoutParams(ViewGroup.LayoutParams(
			ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT
		))
        textView:setTypeface(J.android.graphics.Typeface.MONOSPACE)
		textView:setPadding(16, 16, 16, 16)

        local scrollView = J.android.widget.ScrollView(activity)
        scrollView:setLayoutParams(ViewGroup.LayoutParams(
			ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT
		))
        scrollView:addView(textView)

        activity:setContentView(scrollView)

		--[=[
print('creating ObserverRunnable...')
		local ObserverRunnable = J.Runnable:_subclass{
			isPublic = true,
			fields = {
				textView = {
					isPublic = true,
					isStatic = true,
					sig = textView._classpath,
				},
			},
			methods = {
				run = {
					isPublic = true,
					sig = {'void'},
					newLuaState = true,	-- back to the old thread but let's be safe?
					value = function(J, this)
						-- refreshFileContent:
						this.textView:setText(require 'ext.path' 'out.txt':read() or '')
					end,
				},
			}
		}
		ObserverRunnable.textView = textView
print('created ObserverRunnable.')

print('activity._classpath', activity._classpath)
print('ObserverRunnable._classpath', ObserverRunnable._classpath)
print('creating FileObserver...')
		local Observer = J.android.os.FileObserver:_subclass{
			isPublic = true,
			fields = {
				activity = {
					isPublic = true,
					sig = activity._classpath,
				},
				-- if I pass runnable in here, lua-java tries to query its class's reflection and android segfaults because android is retarded
				runnableClass = {
					isPublic = true,
					sig = 'java.lang.Class',
				},
			},
			methods = {
				onEvent = {
					isPublic = true,
					sig = {'void', 'int', 'java.lang.String'},
					newLuaState = true,	-- new thread, new lua state
					value = function(J, this, event, path)	-- newLuaState means 'J' first

						--[[
						this.activity:runOnUiThread(this.runnable)
						--]]
						-- [[ hmm segfaulting but outside of this call
						local ctor = this.runnableClass:getDeclaredConstructor()
						local runnable = ctor:newInstance()
						this.activity:runOnUiThread(runnable:_cast'java.lang.Runnable')
						--]]
					end,
				},
			},
		}
print('created FileObserver.')
		local fileToWatch = J.java.io.File(activity:getFilesDir(), 'out.txt')
		local observer = Observer(fileToWatch:getPath(), Observer.MODIFY)
		observer.activity = activity
		observer.runnableClass = ObserverRunnable.class

		-- refreshFileContent:
		textView:setText(require 'ext.path' 'out.txt':read() or '')

		-- this gets a weird error:
		-- luajit: [string "java.jnienv"]:531: JVM java.lang.NullPointerException: Attempt to invoke interface method 'int java.util.List.size()' on a null object reference
		observer:startWatching()

print"onCreate DONE"
		--]=]
		-- [=[ same but without FileObserver, just run a callback and watch the file and update
		local logFile = J.java.io.File'out.txt'
		local lastTextTime = logFile:lastModified()
		textView:setText(require 'ext.path' 'out.txt':read() or '')
		local Looper = J.android.os.Looper
		handler = J.android.os.Handler(Looper:getMainLooper())

		local ScrollToBottomRunnable = J.Runnable:_cbClass(function()
			scrollView:fullScroll(J.android.view.View.FOCUS_DOWN)
		end)

		logUpdater = J.Runnable(function()
			local thisTextTime = logFile:lastModified()
			if thisTextTime > lastTextTime then
				lastTextTime = thisTextTime

				local isAtBottom = scrollView:canScrollVertically(1)

				textView:setText(require 'ext.path' 'out.txt':read() or '')

				if isAtBottom then
					scrollView:post(ScrollToBottomRunnable())
				end
			end
			handler:postDelayed(this, 2000)
		end)
		--]=]
	end,

	onResume = function(activity)
		activity.super:onResume()
		handler:post(logUpdater)
	end,

	onPause = function(activity)
		activity.super:onPause()
		handler:removeCallbacks(logUpdater)
	end,

	onDestroy = function(activity)
		activity.super:onDestroy()
		if observer then observer:stopWatching() end
	end,
}
--]=======]
--[=======[ bluetooth scanner example ... gets back nothing and no errors *shrug*
local BluetoothDevice = J.android.bluetooth.BluetoothDevice

local receiver, bluetoothAdapter

local callbacks = {
	onCreate = function(activity, savedInstanceState)
		activity.super:onCreate(savedInstanceState)

		bluetoothAdapter = J.android.bluetooth.BluetoothAdapter:getDefaultAdapter()

		local BroadcastReceiver = J.android.content.BroadcastReceiver
		local Receiver = BroadcastReceiver:_subclass{
			isPublic = true,
			methods = {
				{
					name = 'onReceive',
					isPublic = true,
					sig = {'void', 'android.content.Context', 'android.content.Intent'},
					value = function(this, context, intent)
						local action = intent:getAction()
						if BluetoothDevice.ACTION_FOUND:equals(action) then
							local device = intent:getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
							local deviceName = device:getName()
							local deviceHardwareAddress = device:getAddress() -- MAC address
							-- Hidden devices will appear here if they are transmitting
print('found', deviceHardwareAddress, deviceName)
						end
					end,
				},
			},
		}
		receiver = Receiver()
print('registering receiver', receiver)

		local filter = J.android.content.IntentFilter(BluetoothDevice.ACTION_FOUND)
		activity:registerReceiver(receiver, filter)

		if not (bluetoothAdapter
		and bluetoothAdapter:isEnabled())
		then
			print('BLUETOOTH IS NOT ENABLED')
			return
		end

		bluetoothAdapter:startDiscovery()
print('onCreate DONE')
	end,

	onDestroy = function(activity)
		activity.super:onDestroy()

print('unregistering receiver', receiver)
		activity:unregisterReceiver(receiver)

		if bluetoothAdapter then
			bluetoothAdapter:cancelDiscovery()
		end
	end,
}
--]=======]
--[=======[  bluetooth le scanner example
local callbacks = {
	onCreate = function(activity, savedInstanceState)
		activity.super:onCreate(savedInstanceState)

BluetoothManager bluetoothManager = (BluetoothManager) getSystemService(Context.BLUETOOTH_SERVICE);
BluetoothAdapter bluetoothAdapter = bluetoothManager.getAdapter();
BluetoothLeScanner bluetoothLeScanner = bluetoothAdapter.getBluetoothLeScanner();

private ScanCallback leScanCallback = new ScanCallback() {
    @Override
    public void onScanResult(int callbackType, ScanResult result) {
        BluetoothDevice device = result.getDevice();
        // Access device name, MAC address, and signal strength (RSSI)
        String name = device.getName();
        String address = device.getAddress();
        int rssi = result.getRssi();

        Log.d("BLE_SCAN", "Found: " + name + " [" + address + "] RSSI: " + rssi);
    }

    @Override
    public void onScanFailed(int errorCode) {
        Log.e("BLE_SCAN", "Scan failed with error: " + errorCode);
    }
};

private boolean mScanning;
private Handler handler = new Handler();
private static final long SCAN_PERIOD = 10000; // 10 seconds

private void scanLeDevice() {
    if (!mScanning) {
        // Stop scanning after the defined period
        handler.postDelayed(() -> {
            mScanning = false;
            bluetoothLeScanner.stopScan(leScanCallback);
        }, SCAN_PERIOD);

        mScanning = true;
        // Optionally pass ScanFilters and ScanSettings for better efficiency
        bluetoothLeScanner.startScan(leScanCallback);
    } else {
        mScanning = false;
        bluetoothLeScanner.stopScan(leScanCallback);
    }
}

print('onCreate DONE')
	end,
}
--]=======]
return function(methodName, activity, ...)
	print('BEGIN', methodName, activity, ...)
	local callback = callbacks[methodName]
	local result
	if callback then
		result = callback(activity, ...)
	else
		local super = activity.super
		result = super[methodName](super, ...)
	end
	print('END', methodName)
	return result
end
