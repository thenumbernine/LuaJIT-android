-- this is the LuaJIT app's main.lua is currently pointed
-- it is distinct of the SDLLuaJIT in that it has a minimal bootstrap that points it squarely to lua-java and the assets apk loader
-- from there I will load more files from here
-- and then write stupid android apps
local ffi = require 'ffi'
local J = require 'java'
local pthread = require 'ffi.req' 'c.pthread'

print('Android API:', J.android.os.Build.VERSION.SDK_INT)

-- rebuild args cast to their instanciated class
local function recastArgs(...)
	if select('#', ...) == 0 then return end
	local arg = ...
	if arg ~= nil then arg = J:_fromJObject(arg._ptr) end
	return arg, recastArgs(select(2, ...))
end

print(
	'_G='..tostring(_G)
	..', pthread_self='..tostring(pthread.pthread_self())
	..', jniEnv='..tostring(J._ptr)
)

-- these callbacks are centered around the original activity
-- you can make a new activity and then provide its callbacks in Lua
	-- in order of how Android handles it:
local callbacks = {
	onCreate = function(activity, ...)
		activity.super:onCreate(...)

		local LinearLayout = J.android.widget.LinearLayout

		-- can't programmatically switch to a subclass...
		-- "Unable to find explicit activity ...; have you declared this activity in your AndroidManifest.xml?
		--[[ immediately switch to a new jetpack activity:
		local ImageDetailActivity = require 'java.luaclass'{
			env = J,
			extends = 'androidx.appcompat.app.AppCompatActivity',
			methods = {
				{
					name = 'onCreate',
					sig = {'void', 'android.os.Bundle'},
					value = function(this, savedInstanceState)
						print('in onCreate of new Activity')
						print('this', this)
						print('savedInstanceState', savedInstanceState)
					end,
				},
			},
		}
		print('ImageDetailActivity', ImageDetailActivity)
		activity:startActivity(J.android.content.Intent(activity, ImageDetailActivity.class))
		do return end
		--]]

		--[[ hello world?
		local mainLayout = LinearLayout(activity)
		activity:setContentView(mainLayout)
		mainLayout:setOrientation(LinearLayout.VERTICAL)		-- android:orientation
		mainLayout:setLayoutParams(LinearLayout.LayoutParams(
			LinearLayout.LayoutParams.MATCH_PARENT,				-- android:layout_width
			LinearLayout.LayoutParams.MATCH_PARENT				-- android:layout_height
		))
		mainLayout:setGravity(J.android.view.Gravity.CENTER)	-- android:layout_gravity

		local textView = J.android.widget.TextView(activity)
		mainLayout:addView(textView)
		textView:setLayoutParams(LinearLayout.LayoutParams(
			LinearLayout.LayoutParams.WRAP_CONTENT,
			LinearLayout.LayoutParams.WRAP_CONTENT
		))
		textView:setText("TESTING TESTING ONE TWO THREE")
		textView:setTextSize(20)
		textView:setPadding(10, 10, 10, 10)
		--]]

		--[[ document tree
		local openDirectoryLauncher = activity:registerForActivityResult(
			ActivityResultContracts.OpenDocumentTree(),
			ActivityResultCallback:_subclass{
				methods = {
					{
						name = 'onActivityResult',
						sig = {'void', 'Uri'},
						value = function(this, uri)
							if uri ~= nil then
								local takeFlags = bit.bor(
									Intent.FLAG_GRANT_READ_URI_PERMISSION,
									Intent.FLAG_GRANT_WRITE_URI_PERMISSION
								)
								activity:getContentResolver():takePersistableUriPermission(uri, takeFlags)
							end
						end,
					},
				},
			}
		)
		--]]

		--button:setOnClickListener(function(v) openDirectoryLauncher:launch(nil) end)

		-- [[
		local coordinatorLayout = J.androidx.coordinatorlayout.widget.CoordinatorLayout(activity)
		coordinatorLayout:setLayoutParams(LinearLayout.LayoutParams(
			LinearLayout.LayoutParams.MATCH_PARENT,				-- android:layout_width
			LinearLayout.LayoutParams.MATCH_PARENT				-- android:layout_height
		))
		coordinatorLayout:setFitsSystemWindows(true)

		-- or else AppBarLayout ctor will throw
		-- but this only accepts integers that are generated into the static class "R" at compile time...
		--activity:setTheme()
		local materialContext = J.android.view.ContextThemeWrapper(
			activity,
			--J.com.google.android.material.R.style.Theme_MaterialComponents_DayNight_NoActionBar
			J.androidx.appcompat.R.style.Theme_AppCompat_Light
		)

		local AppBarLayout = J.com.google.android.material.appbar.AppBarLayout
		--local appBarLayout = assert(AppBarLayout(activity))	-- req app theme to be Theme.AppCompat...
		local appBarLayout = assert(AppBarLayout(materialContext))	-- giving me the same error
		appBarLayout:setLayoutParams(AppBarLayout.LayoutParams(
			AppBarLayout.LayoutParams.MATCH_PARENT,
			AppBarLayout.LayoutParams.WRAP_CONTENT
		))
		appBarLayout:setBackgroundColor(J.android.graphics.Color:parseColor'#6200EE')

		local toolbar = J.androidx.appcompat.widget.Toolbar(activity)
		local TypedValue = J.android.util.TypedValue
		local toolbarLayoutParams = AppBarLayout.LayoutParams(
			AppBarLayout.LayoutParams.MATCH_PARENT,
			TypedValue:applyDimension(TypedValue.COMPLEX_UNIT_DIP, 56, activity:getResources():getDisplayMetrics())
		)
		toolbarLayoutParams:setScrollFlags(bit.bor(
			AppBarLayout.LayoutParams.SCROLL_FLAG_SCROLL,
			AppBarLayout.LayoutParams.SCROLL_FLAG_ENTER_ALWAYS
		))
		toolbar:setLayoutParams(toolbarLayoutParams)
		toolbar:setTitle'Programmatic App Bar'
		toolbar:setTitleTextColor(J.android.graphics.Color.WHITE)
		--[[ doesn't work without xml modifications
		activity:setSupportActionBar(toolbar)
		--]]
		--[[
		activity:setNavigationOnClickListener(function(v) end)
		toolbar:inflateMenu(something)
		toolbar:setOnMenuItemClickListener(function(item) end)
		--]]

		appBarLayout:addView(toolbar)

		local nestedScrollView = J.androidx.core.widget.NestedScrollView(activity)
		local CoordinatorLayout = J.androidx.coordinatorlayout.widget.CoordinatorLayout
		local contentLayoutParams = CoordinatorLayout.LayoutParams(
			CoordinatorLayout.LayoutParams.MATCH_PARENT,
			CoordinatorLayout.LayoutParams.MATCH_PARENT
		)
		contentLayoutParams:setBehavior(AppBarLayout.ScrollingViewBehavior())
		nestedScrollView:setLayoutParams(contentLayoutParams)

		local contentText = J.android.widget.TextView(activity)
		contentText:setText[[title is here]]
		contentText:setPadding(16, 16, 16, 16)
		contentText:setTextSize(18)
		nestedScrollView:addView(contentText)

		coordinatorLayout:addView(appBarLayout)
		coordinatorLayout:addView(nestedScrollView)

		activity:setContentView(coordinatorLayout)


		local ImageView = J.android.widget.ImageView
		local galleryPreview = ImageView(activity)
		--galleryPreview:setImageResource(smoe placeholder in teh resource file)
		galleryPreview:setScaleType(ImageView.ScaleType.CENTER_CROP)

		local galleryParams = AppBarLayout.LayoutParams(
			AppBarLayout.LayoutParams.MATCH_PARENT,
			TypedValue:applyDimension(TypedValue.COMPLEX_UNIT_DIP, 200, activity:getResources():getDisplayMetrics())
		)
		galleryParams:setScrollFlags(bit.bor(
			AppBarLayout.LayoutParams.SCROLL_FLAG_SCROLL,
			AppBarLayout.LayoutParams.SCROLL_FLAG_EXIT_UNTIL_COLLAPSED
		))
		galleryPreview:setLayoutParams(galleryParams)

		appBarLayout:addView(galleryPreview)

		local recyclerView = J.androidx.recyclerview.widget.RecyclerView(activity)
		--recyclerView:setLayoutManager(J.androidx.recyclerview.widget.LinearLayoutManager(activity))
		local recyclerParams = CoordinatorLayout.LayoutParams(
			CoordinatorLayout.LayoutParams.MATCH_PARENT,				-- android:layout_width
			CoordinatorLayout.LayoutParams.MATCH_PARENT				-- android:layout_height
		)
		recyclerParams:setBehavior(AppBarLayout.ScrollingViewBehavior())
		recyclerView:setLayoutParams(recyclerParams)
		coordinatorLayout:addView(recyclerView)

		local numberOfColumns = 3
		local gridLayoutManager = J.androidx.recyclerview.widget.GridLayoutManager(activity, numberOfColumns)
		recyclerView:setLayoutManager(gridLayoutManager)

		--[=[ I can't find this class so
		local spacingInPixels = TypedValue:applyDimension(TyepdValue.COMPLEX_UNIT_DIP, 8, activity:getResources():getDisplayMetrics())
		recyclerView:addItemDecoration(GridSpacingItemDecoration(numberOfColumns, spacingInPixels))
		--]=]

		local GalleryAdapter = require 'java.luaclass'{
			env = J,
			extends = RecyclerView.Adapter,
			methods = {
				{
					name = 'onCreateViewHolder',
					sig = {'ViewHolder', 'ViewGroup', 'int'},
					value = function(this, parent, viewType)
						local imageView = ImageView(activity)
						local params = RecyclerView.LayoutParams(
							ViewGroup.LayoutParams.MATCH_PARENT,
							ViewGroup.LayoutParams.WRAP_CONTENT
						)
						imageView:setLayoutParams(params)
						imageView:setScaleType(ImageView.ScaleType.CENTER_CROP)
						return ViewHolder(imageView)
					end,
				},
				{
					name = 'onBindViewHolder',
					sig = {'void', 'ViewHolder', 'int'},
					value = function(this, holder, position)
						local imageView = holder.itemView:_cast(ImageView)
						-- fun fact, whereas Java would compile this once, because its hit per image at runtime, LuaJIT will make a new Java class per image
						imageView:post(function()
							local width = imageView:getWidth()
							if width > 0
							and imageView:getLayoutParams().height ~= width
							then
								imageView:getLayoutParams().height = width
								imageView:requestLayout()
							end
						end)

						Glide:with(activity)
						:load(imageUrls:get(position))
						:placeholder(android.R.drawable.ic_menu_gallery)
						:error(android.R.drawable.stat_notify_error)
						:into(imageView)
					end,
				},
				{
					name = 'getItemCount',
					sig = {'int'},
					value = function(this)
						return imageUrls:size()
					end,
				},
			},
		}

		-- [=[
		--local myImages = Array.asList( list of images )
		local adapter = GalleryAdapter(activity, myImages)
		recyclerView:setAdapter(adapter)
		--]=]

		--]]
	end,

	onBackPressed = function(activity, ...)
		--activity.super:onBackPressed(...)
		activity:finish()
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
	local callback = callbacks[methodName]
	if callback then
		result = callback(activity, recastArgs(args:_unpack()))
	else
		result = activity.super[methodName](activity, recastArgs(args:_unpack()))
	end

print('java:', methodName, 'returning', result)
	return result
end
