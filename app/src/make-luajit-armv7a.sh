#!/bin/sh
cd luajit/src
#NDKDIR=$HOME/Android/Sdk/ndk/29.0.14206865
NDKDIR=$HOME/Android/Sdk/ndk/28.2.13676358

NDKBIN=$NDKDIR/toolchains/llvm/prebuilt/linux-x86_64/bin
NDKCROSS=$NDKBIN/arm-linux-androideabi-
NDKCC=$NDKBIN/armv7a-linux-androideabi35-clang

make clean

# Chris: the first batch are env vars I usu modify directly in Makefile.  Here's hoping I can in fact override them with this.  I don't want to fork luajit. 
# Chris: would be nice to override LJ_OS_NAME=Android ...
make \
	Q= \
	E="@:" \
	XCFLAGS=-DLUAJIT_ENABLE_LUA52COMPAT \
	TARGET_SONAME=libluajit.so \
	TARGET_DYLIBNAME=libluajit.dylib \
	TARGET_DLLNAME=luajit.dll \
	TARGET_DLLDOTANAME=libluajit.dll.a \
	\
	HOST_CC="gcc -m32" \
	CROSS=$NDKCROSS \
	STATIC_CC=$NDKCC \
	DYNAMIC_CC="$NDKCC -fPIC" \
	TARGET_LD=$NDKCC \
	TARGET_AR="$NDKBIN/llvm-ar rcus" \
	TARGET_STRIP=$NDKBIN/llvm-strip

ANDROID_ABI=armeabi-v7a

# copy lib
DESTLIBDIR=../../main/jniLibs/$ANDROID_ABI/
mkdir -p $DESTLIBDIR
cp libluajit.so $DESTLIBDIR
cp libluajit.a $DESTLIBDIR
cp luajit $DESTLIBDIR

# copy headers
DESTINCDIR=../../main/cpp/include/$ANDROID_ABI/
mkdir -p $DESTINCDIR
cp lauxlib.h $DESTINCDIR
cp luaconf.h $DESTINCDIR
cp lua.h $DESTINCDIR
cp lua.hpp $DESTINCDIR
cp luajit.h $DESTINCDIR
cp lualib.h $DESTINCDIR
cp lj_arch.h $DESTINCDIR

# copy jit/ folder ... TODO this should go in the per-arch assets ...
JITDIR=../../main/cpp/jit/$ANDROID_ABI/
mkdir -p $JITDIR
cp jit/*.lua $JITDIR
