# because Gradle sucks so much ,I'm tired of slow builds, tired of 5mb source projects exploding to 1gb of cache files, tired of cache sync mismatches and mysterious runtime link fails
# going off this script, but converting to GNU Make: https://github.com/WanghongLin/miscellaneous/blob/master/tools/build-apk-manually.sh
.PHONY: default
default: all


ANDROID_STUDIO_ROOT = $(HOME)/android-studio
ANDROID_SDK_ROOT = $(HOME)/Android/Sdk

ANDROID_PLATFORM_VERSION = $(shell ls $(ANDROID_SDK_ROOT)/platforms | sort -nr | tail -1)
ANDROID_PLATFORM_DIR = $(ANDROID_SDK_ROOT)/platforms/$(ANDROID_PLATFORM_VERSION)

BUILD_TOOLS_VERSION = $(shell ls $(ANDROID_SDK_ROOT)/build-tools | sort -n |tail -1)
BUILD_TOOLS_DIR = $(ANDROID_SDK_ROOT)/build-tools/$(BUILD_TOOLS_VERSION)

ANDROID_JAR = $(ANDROID_PLATFORM_DIR)/android.jar

NDK_VERSION = $(shell ls $(ANDROID_SDK_ROOT)/ndk | sort -nr | tail -1)
NDK_DIR=$(ANDROID_SDK_ROOT)/ndk/$(NDK_VERSION)
NDK_BIN=$(NDK_DIR)/toolchains/llvm/prebuilt/linux-x86_64/bin


JAVAC_FLAGS = -classpath $(ANDROID_JAR)
JAVAC_FLAGS += -Xlint:deprecation

D8_FLAGS = --classpath $(ANDROID_JAR)


CP = cp
RM = rm
MKDIR = mkdir
ZIP = zip
JAVAC = $(ANDROID_STUDIO_ROOT)/jbr/bin/javac
NDKCC = $(NDK_BIN)/$(NDK_ARCH)-linux-androideabi35-clang
AAPT2 = $(BUILD_TOOLS_DIR)/aapt2
D8 = $(BUILD_TOOLS_DIR)/d8
ZIPALIGN = $(BUILD_TOOLS_DIR)/zipalign
APKSIGNER = $(BUILD_TOOLS_DIR)/apksigner
ADB = adb


APK_TITLE = LuaJIT
PACKAGE_NAME = io.github.thenumbernine.LuaJIT
PACKAGE_NAME_PATH = $(subst .,/,$(PACKAGE_NAME))


# arch folder in lib/
LIB_ARCH=armeabi-v7a
# arch prefix in NDK
NDK_ARCH=armv7a


# Use aapt2 to compile resources into compiled_resources.zip
# This produces a bunch of files $(dir)_$(file).xml.flat based on res/$(dir)/$(file).xml ... smfh what a stupid build process
# NOTICE `aapt2 compile` works on a normie AndroidManifest.xml while `aapt2 link` does not
#RESOURCE_DIR = app/src/main/res
RESOURCE_DIR = nogradle/res
RESOURCE_FILES = $(shell find $(RESOURCE_DIR) -type f)
COMPILED_RESOURCES = _compiled_resources.zip
$(COMPILED_RESOURCES): $(RESOURCE_FILES)
	$(AAPT2) compile \
		--dir $(RESOURCE_DIR) \
		-o $(COMPILED_RESOURCES)

# merge manifests
# nah it's too stupid.  can't find dependencies, docs don't help, Google AI doesn't help ...
#ANDROID_MANIFEST = app/src/main/AndroidManifest.xml
#MergedAndroidManifest.xml: $(ANDROID_MANIFEST)
#	java \
#		-$(CP) $(ANDROID_STUDIO_ROOT)/plugins/android/lib/manifest-merger.jar \
#		com.android.manifmerger.ManifestMerger2 \
#		--main $(ANDROID_MANIFEST) \
#		--out MergedAndroidManifest.xml
# --libs comes next but I have no libs, so this is a worthless step, except that passing a merged-manifold itno gradle gets warnings, and passing an unmerged manifold into aapt2 gets errors, so overall Google is retarded.
# so I'll just hack it myself, bypass their slow and retarded tool
ANDROID_MANIFEST = nogradle/AndroidManifest.xml

ASSETS_DIR = app/src/main/assets
ASSETS_FILES = $(shell find $(ASSETS_DIR) -type f)

# update assets patched contents:
ASSETS_PATCH_DIR = assets_patch
$(ASSETS_DIR)/%: $(ASSETS_PATCH_DIR)/%
	$(MKDIR) -p $(dir $@)
	$(CP) $< $@

# also add it to our assets/ target list so our apkOfResources can reference even new files for timestamps for build updates
ASSETS_FILES += $(patsubst \
	$(ASSETS_PATCH_DIR)/%, \
	$(ASSETS_DIR)/%, \
	$(shell find $(ASSETS_PATCH_DIR) -type f) \
)

# use aapt2 again to make $(APK_TITLE)-resources.apk
# this errors that the manifest is missing package, because it's not a merged-manifest
# this populates _gen/ with $(PACKAGE_NAME_PATH)/ Manifest.java and R.java
# _gen/ is the final location
# but to spare timestamps, first copy to _gentmp/ then cp -ru, then rm _gentmp/
APK_DIR = _apk
AAPT_GEN_DIR = _gen
AAPT_GEN_TMP_DIR = _gentmp
APK_OF_RESOURCES = $(APK_DIR)/$(APK_TITLE)-resources.apk
$(APK_OF_RESOURCES): $(ANDROID_MANIFEST) $(COMPILED_RESOURCES) $(ASSETS_FILES)
	$(MKDIR) -p $(AAPT_GEN_DIR)
	$(MKDIR) -p $(AAPT_GEN_TMP_DIR)
	$(MKDIR) -p $(APK_DIR)
	$(AAPT2) link \
		-o $(APK_OF_RESOURCES) \
		-A $(ASSETS_DIR) \
		-I $(ANDROID_JAR) \
		--manifest $(ANDROID_MANIFEST) \
		--java $(AAPT_GEN_TMP_DIR) \
		$(COMPILED_RESOURCES)
	@for f in `cd $(AAPT_GEN_TMP_DIR) && find . -type f`; do\
		cmp -s $(AAPT_GEN_TMP_DIR)/$$f $(AAPT_GEN_DIR)/$$f \
			&& echo "up to date: $$f" \
			|| ($(MKDIR) -p `dirname $(AAPT_GEN_DIR)/$$f` && $(CP) $(AAPT_GEN_TMP_DIR)/$$f $(AAPT_GEN_DIR)/$$f); \
	done
	-$(RM) -fr $(AAPT_GEN_TMP_DIR)

# there has to be an easier way to copy files without fucking up their timestamp even if the source and destination are identical


$(AAPT_GEN_DIR)/$(PACKAGE_NAME_PATH)/Manifest.java: $(APK_OF_RESOURCES)
$(AAPT_GEN_DIR)/$(PACKAGE_NAME_PATH)/R.java: $(APK_OF_RESOURCES)


JAVA_SRC_DIR = app/src/main/java

# search in JAVA_SRC_DIR and remove the relative search dir prefix
# JAVA_SRC_REL_FILES is the .java files relative to JAVA_SRC_DIR ... which is just one file
JAVA_SRC_REL_FILES = $(patsubst $(JAVA_SRC_DIR)/%, %, $(shell find $(JAVA_SRC_DIR) -type f -name "*.java"))

CLASS_DIR = _class
# JAVA_SRC_CLASS_FILES holds classes of known .java files
# javac will make extra .class files for internal classes
# JAVA_SRC_CLASS_FILES is relative to project
# dependencies should be all .class files, but that list isn't made until after javac is run, so I'll just go with the files i know it makes
JAVA_SRC_CLASS_FILES = $(patsubst %.java, $(CLASS_DIR)/%.class, $(JAVA_SRC_REL_FILES))

# TODO TODO I just broke make
JAVA_SRC_FILES = $(patsubst %, $(JAVA_SRC_DIR)/%, $(JAVA_SRC_REL_FILES)) $(JAVA_GEN_FILES)

# JAVA_SRC_CLASS_FILES just has one entry anyways, so...
$(JAVA_SRC_CLASS_FILES): $(JAVA_SRC_FILES)
	$(MKDIR) -p $(CLASS_DIR)
	$(JAVAC) \
		$(JAVAC_FLAGS) \
		-d $(CLASS_DIR) \
		$^

# compile .class to classes.dex

CLASSES_DEX_DIR = _dex
CLASSES_DEX = $(CLASSES_DEX_DIR)/classes.dex
$(CLASSES_DEX): $(JAVA_SRC_CLASS_FILES)
	$(MKDIR) -p $(CLASSES_DEX_DIR)
	$(D8) \
		$(D8_FLAGS) \
		--output $(CLASSES_DEX_DIR) \
		$(shell find $(CLASS_DIR) -type f -name "*.class")

# compile C files as well

LIB_DIR = lib
LIB_ARCH_DIR = $(LIB_DIR)/$(LIB_ARCH)

# make sure luajit.so is there

LUAJIT_SO = $(LIB_ARCH_DIR)/libluajit.so
# dependencies? a lot?
$(LUAJIT_SO): $(shell find app/src/luajit -type f -name "*.c")
	$(shell cd app/src && ./make-luajit-$(NDK_ARCH).sh)
	mkdir -p $(dir $(LUAJIT_SO))
	$(CP) app/src/main/jniLibs/$(LIB_ARCH)/libluajit.so $(LUAJIT_SO)
	$(CP) -R app/src/main/cpp/jit/$(LIB_ARCH) app/src/main/assets/jit


CPP_SRC_DIR = app/src/main/cpp
OBJ_DIR = _obj
# notice the include/ folder is created from the build scripts sitting in app/src/make-luajit-*.sh,
#  which maybe I'll merge into this someday
CFLAGS = -m32 -fPIC -Wall -I app/src/main/cpp/include/$(LIB_ARCH)
$(OBJ_DIR)/luajit.o: $(CPP_SRC_DIR)/luajit.c $(LUAJIT_SO)
	$(MKDIR) -p $(OBJ_DIR)
	$(NDKCC) $(CFLAGS) $^ -c -o $@

# compile all ndk .o files into our .so file
LIBMAIN_SO = $(LIB_ARCH_DIR)/libmain.so
$(LIBMAIN_SO): $(OBJ_DIR)/luajit.o
	$(MKDIR) -p $(LIB_ARCH_DIR)
	$(NDKCC) -shared -L$(LIB_ARCH_DIR) -lluajit -o $@ $^

# now add the dex to the apk

APK_UNALIGNED_PATH = $(APK_DIR)/$(APK_TITLE)-unaligned-unsigned.apk
$(APK_UNALIGNED_PATH): $(APK_OF_RESOURCES) $(CLASSES_DEX) $(LIBMAIN_SO) $(LUAJIT_SO)
	$(CP) $(APK_OF_RESOURCES) $(APK_UNALIGNED_PATH)
	$(ZIP) -j $(APK_UNALIGNED_PATH) $(CLASSES_DEX)
	$(ZIP) -r -0 -u $(APK_UNALIGNED_PATH) $(LIB_DIR)/

# use zipalign to align the unsigned apk
APK_ALIGNED_PATH = $(APK_DIR)/$(APK_TITLE)-aligned-unsigned.apk
$(APK_ALIGNED_PATH): $(APK_UNALIGNED_PATH)
	-$(RM) $(APK_ALIGNED_PATH)
	$(ZIPALIGN) -p 4 $(APK_UNALIGNED_PATH) $(APK_ALIGNED_PATH)

APK_SIGNED_PATH = $(APK_DIR)/$(APK_TITLE)-signed-debug.apk
KEYSTORE = $(HOME)/.android/debug.keystore
$(APK_SIGNED_PATH): $(APK_ALIGNED_PATH)
	$(CP) $(APK_ALIGNED_PATH) $(APK_SIGNED_PATH)
	$(APKSIGNER) sign \
		--ks $(KEYSTORE) \
		--ks-pass pass:android \
		--ks-key-alias androiddebugkey \
		--key-pass pass:android \
		$(APK_SIGNED_PATH)
	$(APKSIGNER) verify --verbose --print-certs $(APK_SIGNED_PATH)

.PHONY: all
all: $(APK_SIGNED_PATH)

.PHONY: install
install: $(APK_SIGNED_PATH)
	$(ADB) install $(APK_SIGNED_PATH)

.PHONY: uninstall
uninstall:
	$(ADB) uninstall $(PACKAGE_NAME)

.PHONY: run
run:
	$(ADB) shell am start -n $(PACKAGE_NAME)/$(PACKAGE_NAME).Activity

# log file on remote device (relative to /data/data/package/)
LOGFILE = files/out.txt

.PHONY: log
log:
	$(ADB) shell run-as $(PACKAGE_NAME) cat $(LOGFILE)

# have to re-run this every time you run the app, because adb shell tail is deficient
.PHONY: logfollow
logfollow:
	$(ADB) shell run-as $(PACKAGE_NAME) tail -f $(LOGFILE)

.PHONY: clean
clean:
	-$(RM) -fr \
		$(COMPILED_RESOURCES) \
		$(CLASS_DIR) \
		$(CLASSES_DEX_DIR) \
		$(OBJ_DIR) \
		$(AAPT_GEN_DIR) \
		$(AAPT_GEN_TMP_DIR) \
		$(APK_DIR)
