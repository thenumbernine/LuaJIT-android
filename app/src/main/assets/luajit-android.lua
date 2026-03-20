-- this is the LuaJIT app's main.lua is currently pointed
-- it is distinct of the SDLLuaJIT in that it has a minimal bootstrap that points it squarely to lua-java and the assets apk loader
-- from there I will load more files from here
-- and then write stupid android apps
local assert = require 'ext.assert'
local table = require 'ext.table'
local path = require 'ext.path'
local ffi = require 'ffi'
local J = require 'java'

--print('_G='..tostring(_G)..', jniEnv='..tostring(J._ptr))
--print('Android API:', J.android.os.Build.VERSION.SDK_INT)


local callbacks = {}

-- maybe I should by default make all handlers that call through to super ...
do
	local Activity = J.android.app.Activity
	local callbackNames = {}
	for name,methodsForName in pairs(Activity._methods) do
		for _,method in ipairs(methodsForName) do
			if method._class == 'android.app.Activity' then
				callbackNames[name] = true	-- do as a set so multiple signature methods will only get one callback (since lua invokes it by name below)
			end
		end
	end
	for name in pairs(callbackNames) do
		-- set up default callback handler to run super() of whatever args we are given
		callbacks[name] = function(activity, ...)
			local super = activity.super
			return super[name](super, ...)
		end
	end
end


----------- some support functions

local nextMenuID = 0
local function getNextMenu()
	nextMenuID = nextMenuID + 1
	return nextMenuID
end

local nextActivityID = J.android.app.Activity.RESULT_FIRST_USER
local function getNextActivity()
	nextActivityID = nextActivityID + 1
	return nextActivityID
end

local function getFilesForFolderChooserData(activity, data)
	local files = {}
	local treeUri = data:getData()
	activity:getContentResolver():takePersistableUriPermission(treeUri, J.android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)

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
	-- build string from Lua table...
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
			type = fileType and tostring(fileType),
			uri = fileUri,
		})
	end
	cursor:close()
	--]]

	return files
end

-- [=======[ attempt at just outputting the out.txt file
do
	local logScrollView
	--local viewSwitcher
	local logObserver
	local logUpdater

	local prevOnCreate = callbacks.onCreate
	callbacks.onCreate = function(activity, savedInstanceState, ...)
		prevOnCreate(activity, savedInstanceState, ...)

		local ViewGroup = J.android.view.ViewGroup

		local textView = J.android.widget.TextView(activity)
		textView:setLayoutParams(ViewGroup.LayoutParams(
			ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT
		))
		textView:setPadding(16, 16, 16, 16)
		textView:setTypeface(J.android.graphics.Typeface.MONOSPACE)
		textView:setTextSize(J.android.util.TypedValue.COMPLEX_UNIT_SP, 12)

		logScrollView = J.android.widget.ScrollView(activity)
		logScrollView:setLayoutParams(ViewGroup.LayoutParams(
			ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT
		))
		logScrollView:addView(textView)

		local ScrollToBottomRunnable = J.Runnable:_cbClass(function()
			logScrollView:fullScroll(J.android.view.View.FOCUS_DOWN)
		end)

		--[=[ still segfaulting
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
						this.textView:setText(path'out.txt':read() or '')
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
		logObserver = Observer(fileToWatch:getPath(), Observer.MODIFY)
		logObserver.activity = activity
		logObserver.runnableClass = ObserverRunnable.class

		-- refreshFileContent:
		textView:setText(path'out.txt':read() or '')

		-- this gets a weird error:
		-- luajit: [string "java.jnienv"]:531: JVM java.lang.NullPointerException: Attempt to invoke interface method 'int java.util.List.size()' on a null object reference
		logObserver:startWatching()
		--]=]
		-- [=[ same but without FileObserver, just run a callback and watch the file and update
		local logFile = J.java.io.File'out.txt'
		local lastTextTime = logFile:lastModified()
		textView:setText(path'out.txt':read() or '')
		local Looper = J.android.os.Looper
		handler = J.android.os.Handler(Looper:getMainLooper())

		logUpdater = J.Runnable(function()
			local thisTextTime = logFile:lastModified()
			if thisTextTime > lastTextTime then
				lastTextTime = thisTextTime

				local isAtBottom = logScrollView:canScrollVertically(1)

				textView:setText(path'out.txt':read() or '')

				if isAtBottom then
					logScrollView:post(ScrollToBottomRunnable())
				end
			end
			handler:postDelayed(this, 2000)
		end)
		--]=]


		--[[ single view
		activity:setContentView(logScrollView)
		--]]
		--[[ view switcher
		viewSwitcher = J.android.widget.ViewSwitcher(activity)
		viewSwitcher:addView(logScrollView)
		--]]

print"onCreate DONE"
	end

	local prevOnResume = callbacks.onResume
	callbacks.onResume = function(activity)
		prevOnResume(activity)
		if logUpdater then
			handler:post(logUpdater)
		end
	end

	local prevOnPause = callbacks.onPause
	callbacks.onPause = function(activity)
		prevOnPause(activity)
		if logUpdater then
			handler:removeCallbacks(logUpdater)
		end
	end

	local prevOnDestroy = callbacks.onDestroy
	callbacks.onDestroy = function(activity)
		prevOnDestroy(activity)
		if logObserver then
			logObserver:stopWatching()
		end
	end

	local menuOpenLog = getNextMenu()
	local prevOnCreateOptionsMenu = callbacks.onCreateOptionsMenu
	callbacks.onCreateOptionsMenu = function(activity, menu, ...)
		prevOnCreateOptionsMenu(activity, menu, ...)
		menu:add(0, menuOpenLog, 0, 'Log...')
			:setShowAsAction(J.android.view.MenuItem.SHOW_AS_ACTION_ALWAYS)
		return true
	end


	local prevOnOptionsItemSelected = callbacks.onOptionsItemSelected
	callbacks.onOptionsItemSelected = function(activity, item, ...)
		if item:getItemId() == menuOpenLog then
			-- [[ open the log ... but doesn't use back buttons
			activity:setContentView(logScrollView)
			--]]
			--[[ open ?
			viewSwitcher:showNext()	-- do you have any control over what view is going to be shown, or did retards make Android?
			--]]
		end

		return prevOnOptionsItemSelected(activity, item, ...)
	end
end
--]=======]
--[=======[ bluetooth scanner example ... gets back nothing and no errors *shrug*
do
	local BluetoothDevice = J.android.bluetooth.BluetoothDevice

	local receiver, bluetoothAdapter

	local prevOnCreate = callbacks.onCreate
	callbacks.onCreate = function(activity, savedInstanceState, ...)
		prevOnCreate(activity, savedInstanceState, ...)

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
	end

	local prevOnDestroy = callbacks.onDestroy
	callbacks.onDestroy = function(activity, ...)
print('unregistering receiver', receiver)
		activity:unregisterReceiver(receiver)

		if bluetoothAdapter then
			bluetoothAdapter:cancelDiscovery()
		end

		prevOnDestroy(activity, ...)
	end
end
--]=======]
-- [=======[ directory image gallery example
do
	local Intent = J.android.content.Intent
	local Activity = J.android.app.Activity
	local LinearLayout = J.android.widget.LinearLayout
	local ViewGroup = J.android.view.ViewGroup
	local ImageView = J.android.widget.ImageView

	local menuPickGalleryFolder = getNextMenu()
	local menuPickGalleryFolderOpen = getNextActivity()

	local galleryRootLayout
	local gridLayout

	-- these callbacks are centered around the original activity
	-- you can make a new activity and then provide its callbacks in Lua
		-- in order of how Android handles it:
	local prevOnCreate = callbacks.onCreate
	callbacks.onCreate = function(activity, ...)
		prevOnCreate(activity, ...)

		galleryRootLayout = LinearLayout(activity)
		galleryRootLayout:setLayoutParams(ViewGroup.LayoutParams(-1, -1))

		local toolbar = J.android.widget.Toolbar(activity)
		toolbar:setTitle'Image Preview Grid'
		toolbar:setBackgroundColor(0xFF6200EE)
		toolbar:setTitleTextColor(0xFFFFFFFF)
		galleryRootLayout:addView(toolbar)

		local scrollView = J.android.widget.ScrollView(activity)
		scrollView:setLayoutParams(LinearLayout.LayoutParams(-1, -1))

		gridLayout = J.android.widget.GridLayout(activity)
		gridLayout:setColumnCount(3)
		gridLayout:setLayoutParams(ViewGroup.LayoutParams(-1, -2))	-- WRAP_CONTENT height

		scrollView:addView(gridLayout)
		galleryRootLayout:addView(scrollView)

		--[[
		activity:setContentView(galleryRootLayout)
		--]]
	end

	local prevOnCreateOptionsMenu = callbacks.onCreateOptionsMenu
	callbacks.onCreateOptionsMenu = function(activity, menu, ...)
		menu:add(0, menuPickGalleryFolder, 0, 'Pictures...')
			:setShowAsAction(J.android.view.MenuItem.SHOW_AS_ACTION_IF_ROOM)
		return prevOnCreateOptionsMenu(activity, menu, ...)
	end

	local prevOnOptionsItemSelected = callbacks.onOptionsItemSelected
	callbacks.onOptionsItemSelected = function(activity, item, ...)
		if item:getItemId() == menuPickGalleryFolder then
			local intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
			intent:addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
			activity:startActivityForResult(intent, menuPickGalleryFolderOpen)
			return true
		end

		return prevOnOptionsItemSelected(activity, item, ...)
	end

	local prevOnActivityResult = callbacks.onActivityResult
	callbacks.onActivityResult = function(activity, requestCode, resultCode, data)
		prevOnActivityResult(activity, requestCode, resultCode, data)

		if requestCode:intValue() == menuPickGalleryFolderOpen
		and resultCode:intValue() == Activity.RESULT_OK
		then
			local files = getFilesForFolderChooserData(activity, data)

			gridLayout:removeAllViews()
			local size = activity:getResources():getDisplayMetrics().widthPixels / 3
			for _,file in ipairs(files) do
				local fileType = file.type
				if fileType and fileType:match'^image/' then
					-- ... do something here
					local img = ImageView(activity)
					img:setLayoutParams(ViewGroup.LayoutParams(size, size))
					img:setScaleType(ImageView.ScaleType.CENTER_CROP)
					img:setImageURI(file.uri)
					gridLayout:addView(img)
				end
			end

			-- finally, show the galleryRootLayout
			activity:setContentView(galleryRootLayout)
		end
	end
end
--]=======]
-- [=======[ audio player also?
do
	local Activity = J.android.app.Activity
	local Intent = J.android.content.Intent
	local LinearLayout = J.android.widget.LinearLayout

	local menuPickMusicFolder = getNextMenu()
	local menuPickMusicFolderOpen = getNextActivity()

	local musicListView

	local prevOnCreate = callbacks.onCreate
	callbacks.onCreate = function(activity, ...)
		prevOnCreate(activity, ...)

		musicListView = J.android.widget.ListView(activity)
	end

	local prevOnCreateOptionsMenu = callbacks.onCreateOptionsMenu
	callbacks.onCreateOptionsMenu = function(activity, menu, ...)
		menu:add(0, menuPickMusicFolder, 0, 'Music...')
			:setShowAsAction(J.android.view.MenuItem.SHOW_AS_ACTION_IF_ROOM)
		return prevOnCreateOptionsMenu(activity, menu, ...)
	end

	local prevOnOptionsItemSelected = callbacks.onOptionsItemSelected
	callbacks.onOptionsItemSelected = function(activity, item, ...)
		if item:getItemId() == menuPickMusicFolder then
			local intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
			intent:addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
			activity:startActivityForResult(intent, menuPickMusicFolderOpen)
			return true
		end

		return prevOnOptionsItemSelected(activity, item, ...)
	end

	local prevOnActivityResult = callbacks.onActivityResult
	callbacks.onActivityResult = function(activity, requestCode, resultCode, data)
		prevOnActivityResult(activity, requestCode, resultCode, data)

		if requestCode:intValue() == menuPickMusicFolderOpen
		and resultCode:intValue() == Activity.RESULT_OK
		then
			-- clear old files
			musicListView:setAdapter(nil)
			
			-- do your thing
			local files = getFilesForFolderChooserData(activity, data)

			local audios = table()
_G.audios = audios	-- don't gc			
			for _,file in ipairs(files) do
				local fileType = file.type
				if fileType and fileType:match'^audio/' then
					audios:insert(file)
				end
			end
			audios:sort(function(a,b) return tostring(a.uri) < tostring(b.uri) end)
			if #audios == 0 then
				print"COULDN'T FIND ANY AUDIO"
			else
				local MediaPlayer = J.android.media.MediaPlayer

				local mediaPlayer

				local isPaused 			-- because mediaplayer doesn't even know if it is paused. jk it does but whoever desigend the API didn't care to let you know.
				local audioIndex = 0	-- bump and play
				local currentPlayingIndex 
				local function playNextTrack()
					if mediaPlayer then mediaPlayer:release() end

					-- load the next track from audios
					audioIndex = audioIndex + 1
					if audioIndex > #audios then return end

					currentPlayingIndex = audioIndex

					-- I guess you have to remake it for each song
					isPaused = false
					mediaPlayer = MediaPlayer:create(activity, audios[audioIndex].uri)
					mediaPlayer:setOnCompletionListener(MediaPlayer.OnCompletionListener(playNextTrack))
					mediaPlayer:start()
				end
				
				local ListViewAdapter = J.android.widget.BaseAdapter:_subclass{
					isPublic = true,
					methods = {
						getCount = {
							isPublic = true,
							sig = {'int'},
							value = function(this) return #audios end,
						},
						getItem = {
							isPublic = true,
							sig = {'java.lang.Object', 'int'},
							value = function(this, position) return audios[position+1].uri end,
						},
						getItemId = {
							isPublic = true,
							sig = {'long', 'int'},
							value = function(this, position) return position end,
						},
						getView = {
							isPublic = true,
							sig = {'android.view.View', 'int', 'android.view.View', 'android.view.ViewGroup'},
							value = function(this, position, convertView, parent)
								local View = J.android.view.View
								local ViewGroup = J.android.view.ViewGroup
								local Button = J.android.widget.Button
								
								local layout = LinearLayout(activity)
								layout:setOrientation(LinearLayout.HORIZONTAL)
								layout:setPadding(20, 20, 20, 20)

								local textView = J.android.widget.TextView(activity)
								textView:setText(tostring(audios[position+1].uri))
								textView:setLayoutParams(LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1))
								layout:addView(textView)

								local playButton = Button(activity)
								playButton:setText("Play")
								playButton:setOnClickListener(View.OnClickListener(function()
									if position+1 == currentPlayingIndex 
									and mediaPlayer
									then
										if isPaused then
											isPaused = false
											mediaPlayer:start()
										else
											isPaused = true
											mediaPlayer:pause()
										end
									else
										audioIndex = position	-- index-1, but index is 1-based and position is 0-based
										playNextTrack()
									end
								end))
								layout:addView(playButton)
							
								return layout
							end,
						},
					},
				}

				musicListView:setAdapter(ListViewAdapter())

				playNextTrack()

				activity:setContentView(musicListView)
			end
		end
	end
end
--]=======]
-- [=======[ GLES view?
do
	local Activity = J.android.app.Activity
	local Intent = J.android.content.Intent
	local GLSurfaceView = J.android.opengl.GLSurfaceView

	local glMenuPickFolder = getNextMenu()

	local glView

	local prevOnCreate = callbacks.onCreate
	callbacks.onCreate = function(activity, ...)
		prevOnCreate(activity, ...)
		
		glView = GLSurfaceView(activity)
		glView:setEGLContextClientVersion(3) -- GLES3.0
	
		_G.Renderer = GLSurfaceView.Renderer:_subclass{
			isPublic = true,
			methods = {
				onSurfaceCreated = {
					isPublic = true,
					newLuaState = true,	-- TODO new lua state management ... one per method or one per class etc? or automatically detect/generate with pthread_self ?
					sig = {'void', 'javax.microedition.khronos.opengles.GL10', 'javax.microedition.khronos.egl.EGLConfig'},
					value = function(J, this, gl, config)
						local GLES30 = J.android.opengl.GLES30
						GLES30:glClearColor(0,.5,1,1)
					end,
				},
				onSurfaceChanged = {
					isPublic = true,
					newLuaState = true,	-- TODO new lua state management ... one per method or one per class etc?
					sig = {'void', 'javax.microedition.khronos.opengles.GL10', 'int', 'int'},
					value = function(J, this, gl, width, height)
						local GLES30 = J.android.opengl.GLES30
						GLES30:glViewport(0,0,width,height)
					end,
				},
				onDrawFrame = {
					isPublic = true,
					newLuaState = true,	-- TODO new lua state management ... one per method or one per class etc?
					sig = {'void', 'javax.microedition.khronos.opengles.GL10'},
					value = function(J, this, gl)
						local GLES30 = J.android.opengl.GLES30
						GLES30:glClear(GLES30.GL_COLOR_BUFFER_BIT)
					
						-- do something GL here
					end,
				},
			},
		}
		_G.render = Renderer()
		glView:setRenderer(renderer)
	end

	local prevOnCreateOptionsMenu = callbacks.onCreateOptionsMenu
	callbacks.onCreateOptionsMenu = function(activity, menu, ...)
		menu:add(0, glMenuPickFolder, 0, 'GLES...')
			:setShowAsAction(J.android.view.MenuItem.SHOW_AS_ACTION_IF_ROOM)
		return prevOnCreateOptionsMenu(activity, menu, ...)
	end

	local prevOnOptionsItemSelected = callbacks.onOptionsItemSelected
	callbacks.onOptionsItemSelected = function(activity, item, ...)
		if item:getItemId() == glMenuPickFolder then
			activity:setContentView(glView)
			return true
		end

		return prevOnOptionsItemSelected(activity, item, ...)
	end

	local prevOnPause = callbacks.onPause
	callbacks.onPause = function(activity, ...)
		prevOnPause(activity, ...)
		glView:onPause()
	end

	local prevOnResume = callbacks.onResume
	callbacks.onResume = function(activity, ...)
		prevOnResume(activity, ...)
		glView:onResume()
	end
end
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
	return assert.index(callbacks, methodName)(activity, ...)
end
