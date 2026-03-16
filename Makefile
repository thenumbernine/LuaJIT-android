# because Gradle sucks so much ,I'm tired of slow builds, tired of 5mb source projects exploding to 1gb of cache files, tired of cache sync mismatches and mysterious runtime link fails
# going off this script, but converting to GNU Make: https://github.com/WanghongLin/miscellaneous/blob/master/tools/build-apk-manually.sh


ANDROID_STUDIO_ROOT = $(HOME)/android-studio

ANDROID_SDK_ROOT = $(HOME)/Android/Sdk
PLATFORM = $(shell ls $(ANDROID_SDK_ROOT)/platforms | sort -nr | tail -1)
BUILD_TOOLS_VERSION = $(shell ls $(ANDROID_SDK_ROOT)/build-tools | sort -n |tail -1)

BUILD_TOOLS_DIR = $(ANDROID_SDK_ROOT)/build-tools/$(BUILD_TOOLS_VERSION)

ANDROID_JAR = $(ANDROID_SDK_ROOT)/platforms/$(PLATFORM)/android.jar

JAVA_FLAGS = -classpath $(ANDROID_JAR)
JAVA_FLAGS += -Xlint:deprecation

D8_FLAGS = --classpath $(ANDROID_JAR)

# debug:
JAVA_FLAGS += -g



# what do I even need this stupid style bullshit for?


AAPT2 = $(BUILD_TOOLS_DIR)/aapt2

# Use aapt2 to compile resources into compiled_resources.zip 
# This produces a bunch of files $(dir)_$(file).xml.flat based on res/$(dir)/$(file).xml ... smfh what a stupid build process
# NOTICE `aapt2 compile` works on a normie AndroidManifest.xml while `aapt2 link` does not
#RESOURCE_DIR = app/src/main/res
RESOURCE_DIR = nogradle/res
COMPILED_RESOURCES = compiled_resources/
$(COMPILED_RESOURCES):
	mkdir -p $(COMPILED_RESOURCES)
	$(AAPT2) compile \
		--dir $(RESOURCE_DIR) \
		-o $(COMPILED_RESOURCES)

# merge manifests
# nah it's too stupid.  can't find dependencies, docs don't help, Google AI doesn't help ...
#ANDROID_MANIFEST = app/src/main/AndroidManifest.xml
#MergedAndroidManifest.xml: $(ANDROID_MANIFEST)
#	java \
#		-cp $(ANDROID_STUDIO_ROOT)/plugins/android/lib/manifest-merger.jar \
#		com.android.manifmerger.ManifestMerger2 \
#		--main $(ANDROID_MANIFEST) \
#		--out MergedAndroidManifest.xml
# --libs comes next but I have no libs, so this is a worthless step, except that passing a merged-manifold itno gradle gets warnings, and passing an unmerged manifold into aapt2 gets errors, so overall Google is retarded.
# so I'll just hack it myself, bypass their slow and retarded tool
ANDROID_MANIFEST = nogradle/AndroidManifest.xml

# use aapt2 again to make base.apk
# this errors that the manifest is missing package, because it's not a merged-manifest
# this populates _gen/ with io/github/thenumbernine/LuaJIT/ Manifest.java and R.java 
AAPT_GEN_DIR = _gen
ASSETS_DIR = app/src/main/assets
APK_OF_RESOURCES = base.apk
$(APK_OF_RESOURCES): $(ANDROID_MANIFEST) $(COMPILED_RESOURCES) $(shell find $(ASSETS_DIR) -type f)
	mkdir -p $(AAPT_GEN_DIR)
	$(AAPT2) link \
		-o $(APK_OF_RESOURCES) \
		-A $(ASSETS_DIR) \
		-I $(ANDROID_JAR) \
		--manifest $(ANDROID_MANIFEST) \
		--java $(AAPT_GEN_DIR) \
		$(COMPILED_RESOURCES)/*.flat

# now we should compile the java files, now, with R.java 

JAVA_SRC_DIR = app/src/main/java
# JAVA_SRC_FILES is relative to JAVA_SRC_DIR 
JAVA_SRC_FILES = io/github/thenumbernine/LuaJIT/Activity.java

CLASS_DIR = ./_class
# JAVA_CLASS_FILES is relative to project
# dependencies should be all .class files, but that list isn't made until after javac is run, so I'll just go with the files i know it makes
JAVA_CLASS_FILES = $(patsubst %.java, $(CLASS_DIR)/%.class, $(JAVA_SRC_FILES))

$(CLASS_DIR)/io/github/thenumbernine/LuaJIT/Activity.class: $(JAVA_SRC_DIR)/io/github/thenumbernine/LuaJIT/Activity.java  $(AAPT_GEN_DIR)/io/github/thenumbernine/LuaJIT/R.java
	mkdir -p $(CLASS_DIR)
	$(ANDROID_STUDIO_ROOT)/jbr/bin/javac \
		$(JAVA_FLAGS) \
		-d $(CLASS_DIR) \
		$(JAVA_SRC_DIR)/io/github/thenumbernine/LuaJIT/Activity.java \
		$(AAPT_GEN_DIR)/io/github/thenumbernine/LuaJIT/R.java

# compile .class to classes.dex

CLASSES_DEX_DIR = _dex
CLASSES_DEX = $(CLASSES_DEX_DIR)/classes.dex
$(CLASSES_DEX): $(JAVA_CLASS_FILES)
	mkdir -p $(CLASSES_DEX_DIR)
	$(BUILD_TOOLS_DIR)/d8 \
		$(CLASS_DIR)/io/github/thenumbernine/LuaJIT/*.class \
		$(D8_FLAGS) \
		--output $(CLASSES_DEX_DIR)

# now add the dex to the apk

LIB_DIR = lib/
APK_UNALIGNED_PATH = base-unaligned.apk
$(APK_UNALIGNED_PATH): $(APK_OF_RESOURCES) $(CLASSES_DEX)
	cp $(APK_OF_RESOURCES) $(APK_UNALIGNED_PATH)
	zip -j $(APK_UNALIGNED_PATH) $(CLASSES_DEX)
	zip -r -0 -u $(APK_UNALIGNED_PATH) $(LIB_DIR)

# use zipalign to align the unsigned apk
APK_ALIGNED_PATH = base-aligned.apk
$(APK_ALIGNED_PATH): $(APK_UNALIGNED_PATH)
	-rm $(APK_ALIGNED_PATH)
	$(BUILD_TOOLS_DIR)/zipalign -v -p 4 $(APK_UNALIGNED_PATH) $(APK_ALIGNED_PATH)

APK_SIGNED_PATH = base-signed.apk
KEYSTORE = $(HOME)/.android/debug.keystore
$(APK_SIGNED_PATH): $(APK_ALIGNED_PATH)
	cp $(APK_ALIGNED_PATH) $(APK_SIGNED_PATH)
	$(BUILD_TOOLS_DIR)/apksigner sign \
		--ks $(KEYSTORE) \
		--ks-pass pass:android \
		--ks-key-alias androiddebugkey \
		--key-pass pass:android \
		$(APK_SIGNED_PATH)
	$(BUILD_TOOLS_DIR)/apksigner verify --verbose --print-certs $(APK_SIGNED_PATH)

.PHONY: all
all: $(APK_SIGNED_PATH)

.PHONY: install
install: $(APK_SIGNED_PATH)
	adb install $(APK_SIGNED_PATH)

.PHONY: log
log:
	adb shell run-as io.github.thenumbernine.LuaJIT cat files/out.txt

.PHONY: clean
clean:
	-rm -fr \
		$(COMPILED_RESOURCES) \
		$(CLASS_DIR) \
		$(CLASSES_DEX_DIR) \
		$(AAPT_GEN_DIR) \
		$(APK_OF_RESOURCES) \
		$(APK_UNALIGNED_PATH) \
		$(APK_ALIGNED_PATH) \
		$(APK_SIGNED_PATH) \
		$(APK_SIGNED_PATH).idsig
