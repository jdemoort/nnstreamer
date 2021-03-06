#!/usr/bin/env bash

##
## SPDX-License-Identifier: LGPL-2.1-only
##
# @file  build-android-lib.sh
# @brief A script to build NNStreamer API library for Android
#
# Before running this script, below variables must be set.
# - ANDROID_HOME: Android SDK
# - GSTREAMER_ROOT_ANDROID: GStreamer prebuilt libraries for Android
# - NNSTREAMER_ROOT: NNStreamer root directory
#
# To include sub-plugin for SNAP, you also should define the variable 'SNAP_DIRECTORY'.
# - SNAP_DIRECTORY: Absolute path for SNAP, tensor-filter sub-plugin and prebuilt library.
#
# Build options
# --build_type (default 'all', 'lite' to build with GStreamer core plugins)
# --target_abi (default 'arm64-v8a', 'armeabi-v7a' available)
# --run_test (default 'no', 'yes' to run the instrumentation test)
# --enable_snap (default 'yes' to build with sub-plugin for SNAP)
# --enable_tflite (default 'yes' to build with sub-plugin for tensorflow-lite)
#
# For example, to build library with core plugins for arm64-v8a
# ./build-android-lib.sh --api_option=lite --target_abi=arm64-v8a
#

# API build option
# 'all' : default
# 'lite' : with GStreamer core plugins
# 'single' : no plugins, single-shot only
# 'internal' : no plugins, single-shot only, disable SNAP and tf-lite
build_type='all'

nnstreamer_api_option='all'
include_assets='no'

# Set target ABI ('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64')
target_abi='arm64-v8a'

# Run instrumentation test after build procedure is done
run_test='no'

# Variables to release library (GROUP:ARTIFACT:VERSION)
release_bintray='no'

# Enable SNAP
enable_snap='yes'

# Enable tensorflow-lite
enable_tflite='yes'

# Set tensorflow-lite version (available: 1.9 and 1.13)
nnstreamer_tf_lite_ver='1.13'

# Parse args
for arg in "$@"; do
    case $arg in
        --build_type=*)
            build_type=${arg#*=}
            ;;
        --target_abi=*)
            target_abi=${arg#*=}
            if [ $target_abi != 'armeabi-v7a' ] && [ $target_abi != 'arm64-v8a' ]; then
                echo "Unknown target ABI." && exit 1
            fi
            ;;
        --release=*)
            release_bintray=${arg#*=}
            ;;
        --release_version=*)
            release_version=${arg#*=}
            ;;
        --bintray_user_name=*)
            bintray_user_name=${arg#*=}
            ;;
        --bintray_user_key=*)
            bintray_user_key=${arg#*=}
            ;;
        --run_test=*)
            run_test=${arg#*=}
            ;;
        --nnstreamer_dir=*)
            nnstreamer_dir=${arg#*=}
            ;;
        --result_dir=*)
            result_dir=${arg#*=}
            ;;
        --enable_snap=*)
            enable_snap=${arg#*=}
            ;;
        --enable_tflite=*)
            enable_tflite=${arg#*=}
            ;;
    esac
done

# Check build type
if [[ $build_type == 'single' ]]; then
    nnstreamer_api_option='single'
elif [[ $build_type == 'lite' ]]; then
    nnstreamer_api_option='lite'
elif [[ $build_type == 'internal' ]]; then
    nnstreamer_api_option='single'

    enable_snap='no'
    enable_tflite='no'

    target_abi='arm64-v8a'
elif [[ $build_type != 'all' ]]; then
    echo "Failed, unknown build type $build_type." && exit 1
fi

if [[ $enable_snap == 'yes' ]]; then
    [ -z "$SNAP_DIRECTORY" ] && echo "Need to set SNAP_DIRECTORY, to build sub-plugin for SNAP." && exit 1
    [ $target_abi != 'arm64-v8a' ] && echo "Set target ABI arm64-v8a to build sub-plugin for SNAP." && exit 1

    echo "Build with SNAP: $SNAP_DIRECTORY"
fi

if [[ $release_bintray == 'yes' ]]; then
    [ -z "$release_version" ] && echo "Set release version." && exit 1
    [ -z "$bintray_user_name" ] || [ -z "$bintray_user_key" ] && echo "Set user info to release." && exit 1

    echo "Release version: $release_version user: $bintray_user_name"
fi

# Set library name
nnstreamer_lib_name="nnstreamer"

if [[ $build_type != 'all' ]]; then
    nnstreamer_lib_name="$nnstreamer_lib_name-$build_type"
fi

echo "NNStreamer library name: $nnstreamer_lib_name"

# Function to check if a package is installed
function check_package() {
    which "$1" 2>/dev/null || {
        echo "Need to install $1."
        exit 1
    }
}

# Check required packages
check_package svn
check_package sed
check_package zip

# Android SDK (Set your own path)
[ -z "$ANDROID_HOME" ] && echo "Need to set ANDROID_HOME." && exit 1

echo "Android SDK: $ANDROID_HOME"

# GStreamer prebuilt libraries for Android
# Download from https://gstreamer.freedesktop.org/data/pkg/android/
[ -z "$GSTREAMER_ROOT_ANDROID" ] && echo "Need to set GSTREAMER_ROOT_ANDROID." && exit 1

echo "GStreamer binaries: $GSTREAMER_ROOT_ANDROID"

# NNStreamer root directory
if [[ -z $nnstreamer_dir ]]; then
    [ -z "$NNSTREAMER_ROOT" ] && echo "Need to set NNSTREAMER_ROOT." && exit 1
    nnstreamer_dir=$NNSTREAMER_ROOT
fi

echo "NNStreamer root directory: $nnstreamer_dir"

echo "Start to build NNStreamer library for Android."
pushd $nnstreamer_dir

# Make directory to build NNStreamer library
mkdir -p build_android_lib

# Copy the files (native and java to build Android library) to build directory
cp -r ./api/android/* ./build_android_lib

# Get the prebuilt libraries and build-script
svn --force export https://github.com/nnsuite/nnstreamer-android-resource/trunk/android_api ./build_android_lib

pushd ./build_android_lib

# Update target ABI
sed -i "s|abiFilters 'armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64'|abiFilters '$target_abi'|" api/build.gradle

# Update API build option
sed -i "s|NNSTREAMER_API_OPTION := all|NNSTREAMER_API_OPTION := $nnstreamer_api_option|" api/src/main/jni/Android.mk

if [[ $include_assets == 'yes' ]]; then
    sed -i "s|GSTREAMER_INCLUDE_FONTS := no|GSTREAMER_INCLUDE_FONTS := yes|" api/src/main/jni/Android.mk
    sed -i "s|GSTREAMER_INCLUDE_CA_CERTIFICATES := no|GSTREAMER_INCLUDE_CA_CERTIFICATES := yes|" api/src/main/jni/Android.mk
fi

# Update SNAP option
if [[ $enable_snap == 'yes' ]]; then
    sed -i "s|ENABLE_SNAP := false|ENABLE_SNAP := true|" ext-files/jni/Android-nnstreamer-prebuilt.mk
    sed -i "s|ENABLE_SNAP := false|ENABLE_SNAP := true|" api/src/main/jni/Android.mk
    cp -r $SNAP_DIRECTORY/* api/src/main/jni
fi

# Update tf-lite option
if [[ $enable_tflite == 'yes' ]]; then
    sed -i "s|ENABLE_TF_LITE := false|ENABLE_TF_LITE := true|" api/src/main/jni/Android.mk
    tar xJf ./ext-files/tensorflow-lite-$nnstreamer_tf_lite_ver.tar.xz -C ./api/src/main/jni
fi

# Add dependency for release
if [[ $release_bintray == 'yes' ]]; then
    sed -i "s|// add dependency (bintray)|classpath 'com.novoda:bintray-release:0.9.1'|" build.gradle

    sed -i "s|// add plugin (bintray)|apply plugin: 'com.novoda.bintray-release'\n\
\n\
publish {\n\
    userOrg = 'nnsuite'\n\
    repoName = 'nnstreamer'\n\
    groupId = 'org.nnsuite'\n\
    artifactId = '$nnstreamer_lib_name'\n\
    publishVersion = '$release_version'\n\
    desc = 'NNStreamer API for Android'\n\
    website = 'https://github.com/nnsuite/nnstreamer'\n\
    issueTracker = 'https://github.com/nnsuite/nnstreamer/issues'\n\
    repository = 'https://github.com/nnsuite/nnstreamer.git'\n\
}|" api/build.gradle
fi

# If build option is single-shot only, remove unnecessary files.
if [[ $nnstreamer_api_option == 'single' ]]; then
    rm ./api/src/main/java/org/nnsuite/nnstreamer/CustomFilter.java
    rm ./api/src/main/java/org/nnsuite/nnstreamer/Pipeline.java
    rm ./api/src/androidTest/java/org/nnsuite/nnstreamer/APITestCustomFilter.java
    rm ./api/src/androidTest/java/org/nnsuite/nnstreamer/APITestPipeline.java
fi

echo "Starting gradle build for Android library."

# Build Android library.
chmod +x gradlew
./gradlew api:build

# Check if build procedure is done.
nnstreamer_android_api_lib=./api/build/outputs/aar/api-release.aar

result=1
if [[ -e $nnstreamer_android_api_lib ]]; then
    if [[ -z $result_dir ]]; then
        result_dir=../android_lib
    fi
    today=$(date '+%Y-%m-%d')
    result=0

    echo "Build procedure is done, copy NNStreamer library to $result_dir directory."
    mkdir -p $result_dir
    cp $nnstreamer_android_api_lib $result_dir/$nnstreamer_lib_name-$today.aar

    # Prepare native libraries and header files for C-API
    unzip $nnstreamer_android_api_lib -d aar_extracted

    mkdir -p main/java/org/freedesktop
    mkdir -p main/jni/nnstreamer/lib
    mkdir -p main/jni/nnstreamer/include

    # assets
    if [[ $include_assets == 'yes' ]]; then
        mkdir -p main/assets
        cp -r aar_extracted/assets/* main/assets
    fi

    cp -r api/src/main/java/org/freedesktop/* main/java/org/freedesktop
    cp -r aar_extracted/jni/* main/jni/nnstreamer/lib
    cp ext-files/jni/Android-nnstreamer-prebuilt.mk main/jni
    # header for C-API
    cp $nnstreamer_dir/api/capi/include/nnstreamer.h main/jni/nnstreamer/include
    cp $nnstreamer_dir/api/capi/include/nnstreamer-single.h main/jni/nnstreamer/include
    cp $nnstreamer_dir/api/capi/include/platform/tizen_error.h main/jni/nnstreamer/include

    # header for plugin
    if [[ $nnstreamer_api_option != 'single' ]]; then
        cp $nnstreamer_dir/gst/nnstreamer/nnstreamer_plugin_api.h main/jni/nnstreamer/include
        cp $nnstreamer_dir/gst/nnstreamer/nnstreamer_plugin_api_converter.h main/jni/nnstreamer/include
        cp $nnstreamer_dir/gst/nnstreamer/nnstreamer_plugin_api_decoder.h main/jni/nnstreamer/include
        cp $nnstreamer_dir/gst/nnstreamer/nnstreamer_plugin_api_filter.h main/jni/nnstreamer/include
        cp $nnstreamer_dir/gst/nnstreamer/tensor_filter_custom.h main/jni/nnstreamer/include
        cp $nnstreamer_dir/gst/nnstreamer/tensor_filter_custom_easy.h main/jni/nnstreamer/include
        cp $nnstreamer_dir/gst/nnstreamer/tensor_typedef.h main/jni/nnstreamer/include
        cp $nnstreamer_dir/ext/nnstreamer/tensor_filter/tensor_filter_cpp.hh main/jni/nnstreamer/include
    fi

    nnstreamer_native_files="$nnstreamer_lib_name-native-$today.zip"
    zip -r $nnstreamer_native_files main
    cp $nnstreamer_native_files $result_dir

    rm -rf aar_extracted main

    # Upload to jcenter
    if [[ $release_bintray == 'yes' ]]; then
        echo "Upload NNStreamer library to Bintray."
        ./gradlew api:bintrayUpload -PbintrayUser=$bintray_user_name -PbintrayKey=$bintray_user_key -PdryRun=false
    fi

    # Run instrumentation test
    if [[ $run_test == 'yes' ]]; then
        echo "Run instrumentation test."
        ./gradlew api:connectedCheck

        test_result="$nnstreamer_lib_name-test-$today.zip"
        zip -r $test_result api/build/reports
        cp $test_result $result_dir
    fi
else
    echo "Failed to build NNStreamer library."
fi

popd

# Remove build directory
rm -rf build_android_lib

popd

# exit with success/failure status
exit $result
