# LuaJIT launcher for Android

This is going to do as minimum as possible in Android before running the `/data/data/io.github.thenumbernine.LuaJIT/files/main.lua`.

From there, a classloader into the assets will allow loading [lua-java](https://github.com/thenumbernine/lua-java).

This is a spinoff of my [SDL-LuaJIT-in-Android](https://github.com/thenumbernine/SDLLuaJIT-android) project but trying to be as bare-bones as possible.
That repo is 5MB of source code, but Android Stupido compiles it to 1GB of bloat.  So I'm cutting out Android Studio.
