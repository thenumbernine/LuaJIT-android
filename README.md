# LuaJIT launcher for Android

This is going to do as minimum as possible in Android before running the `/data/data/io.github.thenumbernine.LuaJIT/files/main.lua`.

From there, a classloader into the assets will allow loading [lua-java](https://github.com/thenumbernine/lua-java).

This is a spinoff of my [SDL-LuaJIT-in-Android](https://github.com/thenumbernine/SDLLuaJIT-android) project but trying to be as bare-bones as possible.
That repo is 5MB of source code, but Android Stupido compiles it to 1GB of bloat, and Gradle makes another 5GB of cache files.  So I'm cutting out Android Studio and Gradle.

# How it works.

All Activity calls are forwarded to the main.lua file in the assets folder.

main.lua will then initialize lua-java and call its method handlers based on the Activity method being called.  All Java method arguments are properly forwarded and returned.

I would straight up use a single lua-java generated class for the Activity instead of a bunch of wrapping methods, but Android won't let me, because lua-java makes classes at runtime and Android only allows Activities of classes declared at compile time.

# Limitations (of Android's design)

My lua-java library can create classes at runtime.  Problem solved.  Not so fast.  Android won't let you switch to any Activity at runtime that hasn't already been specified in the AndroidManifest.xml at compile time.

Same is true for themes.  They have to all be present in xml files at compile time.  Why.  Why such a stupid design limitation.  It is as if the people designing the Android platform had a first priority of thinking up how to restrict things and a second priority of allowing people to develop on their OS.

# Build:

1) The gradlew script works.  But Gradle sucks

2) The Makefile works.  It runs on a few MB instead of a few GB, that's why I use it over Gradle.

# TODO:

- write a script to replace the classnames and app name and rename the .java file.
- then compile the one java file to dex, and the one c file to .so, and package the apk
- - oh wait, i've got a dex compiler. so just use my lua-java library.
- if only there was a way to mount and edit files directly on the `/data/data/classname/files/` folder of the phone..
