# LuaJIT launcher for Android

This is going to do as minimum as possible in Android before running the `/data/data/io.github.thenumbernine.LuaJIT/files/main.lua`.

From there, a classloader into the assets will allow loading [lua-java](https://github.com/thenumbernine/lua-java).

This is a spinoff of my [SDL-LuaJIT-in-Android](https://github.com/thenumbernine/SDLLuaJIT-android) project but trying to be as bare-bones as possible.
That repo is 5MB of source code, but Android Stupido compiles it to 1GB of bloat.  So I'm cutting out Android Studio.


# TODO:

- no-gradle build
- write a script to replace the classnames and app name and rename the .java file.
- then compile the one java file to dex, and the one c file to .so, and package the apk
- - oh wait, i've got a dex compiler. just use lua-java.
- then have the app run main.lua.  I guess always always copy the main.lua file across.
- also, before running, stdout/stderr should be redirected.  either to logcat or to some temp buffer that can be queried.
- then main.lua should return a table that has fields of functions for callbacks for the Activity.java
- - on lua side, lua-java can re-wrap all args
- - then on lua side we can set up View etc.
- now if only there was a way to mount and edit files directly on the `/data/data/classname/files/` folder of the phone..
