[![Donate via Stripe](https://img.shields.io/badge/Donate-Stripe-green.svg)](https://buy.stripe.com/00gbJZ0OdcNs9zi288)<br>
[![BuyMeACoffee](https://img.shields.io/badge/BuyMeA-Coffee-tan.svg)](https://buymeacoffee.com/thenumbernine)<br>

# LuaJIT launcher for Android

This is going to do as minimum as possible in Android before running the `/data/data/io.github.thenumbernine.LuaJIT/files/main.lua`.

From there, a classloader into the assets will allow loading [lua-java](https://github.com/thenumbernine/lua-java).

This is a spinoff of my [SDL-LuaJIT-in-Android](https://github.com/thenumbernine/SDLLuaJIT-android) project but trying to be as bare-bones as possible.
That repo is 5MB of source code, but Android Stupido compiles it to 1GB of bloat, and Gradle makes another 5GB of cache files.  So I'm cutting out Android Studio and Gradle.

# How it works.

All Activity calls are forwarded to the main.lua file in the assets folder.

main.lua will then initialize lua-java and call its method handlers based on the Activity method being called.  All Java method arguments are properly forwarded and returned.

I would straight up use a single lua-java generated class for the Activity instead of a bunch of wrapping methods, but Android won't let me, because lua-java makes classes at runtime and Android only allows Activities of classes declared at compile time.

# But I don't want to install Android SDK!

You can get by with just adb.  Push and pull the files `/data/data/io.github.thenumbernine.LuaJIT/main.lua` or `/data/data/io.github.thenumbernine.LuaJIT/luajit-android.lua`.  Or uncomment that top block in `main.lua` to chdir to the sdcard and do all your programming from there -- no more need for adb, and no more need for wait times to rebuild and reinstall the APK!

# Limitations (of Android's design)

My lua-java library can create classes at runtime.  Problem solved.  Not so fast.  Android won't let you switch to any Activity at runtime that hasn't already been specified in the AndroidManifest.xml at compile time.

Same is true for themes.  They have to all be present in xml files at compile time.  Why.  Why such a stupid design limitation.  It is as if the people designing the Android platform had a first priority of thinking up how to restrict things and a second priority of allowing people to develop on their OS.

# Requirements

This still uses Android SDK.  I can't cut out all the middle-men.

But if you really want you can get by with just ADB.

And if you really really want, you can use ADB once and only once to redirect to the sdcard, and then do all your coding forever with your favorite Android text editor.  From your Android device.  Make Android apps on Android without using desktop again.

# Build:

1) The Makefile works.  It runs on a few MB instead of a few GB, that's why I use it over Gradle.

2) The `make.rua` works.  It is written in my [langfix-lua](http://github.com/thenumbernine/langfix-lua) script.  If you want a full script to do your building and if you want better error debugging than GNU Make then it is nice.

3) ~~The gralde script works~~ haha not any more.  I hate gradle.  Stop using trash.

Also instead of a trendy bloated and slow all-in-one repo, I split off the android luajit `.so` cross-compiling into a new repo: https://github.com/thenumbernine/LuaJIT-android-lib .  Now you just build the library once for all derived project, not once per project. 

# Different App Package/Name?

Use the `rename.rua` script alongside either a `config.rua` or your own hardcoded values to replace everything all at once.

# TODO:

- compile the one java file to dex, and the one c file to .so, and package the apk
- - oh wait, i've got a dex compiler. so just use my lua-java library.
- if only there was a way to mount and edit files directly on the `/data/data/classname/files/` folder of the phone..
- lua-java runtime sideloaded dex JNI subclasses that call into luajit closures works, threads work, but threads with certain android classes will cause segfaults, and Android is not the most helpful platform in the world to debug a segfault.

# Similar Projects:

- [koreader luajit-android](https://github.com/koreader/android-luajit-launcher) uses Android NativeActivity, so it can do Vulkan stuff just fine, but NativeActivity restricts you to the world of C, so it will be more difficult (but not impossible) to do Java / Android-UI stuff, which is not necessarily a bad thing considering how antequated Android-Java is, and what a bad design decision it was for Google to build everything off Java.
