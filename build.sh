#!/usr/bin/env bash
# type './build.sh'       for release build
# type './build.sh debug' for debug build
# if the LLVM_DIR variable is not set, LLVM will be downloaded.
#
# Dependencies include: build-essential libncurses5 libncurses-dev cmake zlib1g-dev
set -e # exit on first error

jobs=4

#########
# VARs and Links
########
SVFHOME=$(pwd)
sysOS=$(uname -s)
arch=$(uname -m)

LLVM_VERSION="15.0.0"
Z3_VERSION="4.9.1"

SourceLLVM="https://github.com/llvm/llvm-project/archive/refs/tags/llvmorg-$LLVM_VERSION.zip"
SourceZ3="https://github.com/Z3Prover/z3/archive/refs/tags/z3-$Z3_VERSION.zip"
BuildLLVMFromSource=false
BuildZ3FromSource=false

if [[ $1 == 'debug' ]]; then
    BuildType="Debug"
else
    BuildType="Release"
fi

if [[ "$sysOS" == "Linux" ]]; then
    if [[ "$arch" == "aarch64" ]]; then
        LLVM="https://github.com/llvm/llvm-project/releases/download/llvmorg-$LLVM_VERSION/clang+llvm-$LLVM_VERSION-aarch64-linux-gnu.tar.xz"
        BuildZ3FromSource=true
    else
        # assume x86
        echo "Currently, there is no LLVM 15.0.0 prebuilt binaries for x86 Ubuntu/Linux. See https://discourse.llvm.org/t/llvm-15-0-0-release/65099"
        BuildLLVMFromSource=true
        Z3="https://github.com/Z3Prover/z3/releases/download/z3-$Z3_VERSION/z3-$Z3_VERSION-x64-ubuntu-16.04.zip"
    fi
elif [[ "$sysOS" == "Darwin" ]]; then
    if [[ "$arch" == "arm64" ]]; then
        LLVM="https://github.com/llvm/llvm-project/releases/download/llvmorg-$LLVM_VERSION/clang+llvm-$LLVM_VERSION-arm64-apple-darwin21.0.tar.xz"
        Z3="https://github.com/Z3Prover/z3/releases/download/z3-$Z3_VERSION/z3-$Z3_VERSION-arm64-osx-11.0.zip"
    else 
        # assume x86
        LLVM="https://github.com/llvm/llvm-project/releases/download/llvmorg-$LLVM_VERSION/clang+llvm-$LLVM_VERSION-x86_64-apple-darwin.tar.xz"
        Z3="https://github.com/Z3Prover/z3/releases/download/z3-$Z3_VERSION/z3-$Z3_VERSION-x64-osx-10.16.zip"
    fi
else
    echo "Unsupported Platform: $sysOS. Exiting."
    exit 1
fi

# Keep LLVM version suffix for version checking and better debugging
# keep the version consistent with LLVM_DIR in setup.sh and llvm_version in Dockerfile
LLVMHome="llvm-$LLVM_VERSION.obj"
Z3Home="z3.obj"

# Downloads $1 (URL) to $2 (target destination) using wget or curl
# E.g. generic_download_file www.url.com/my.zip loc/my.zip
function generic_download_file {
    if [ $# -ne 2 ]
    then
        echo "$0: bad args to generic_download_file!"
        exit 1
    fi

    if [ -f "$2" ]; then
        echo "File $2 exists, skip download..."
        return
    fi

    local download_failed=false
    if type curl &> /dev/null; then
        if ! curl -L "$1" -o "$2"; then
            download_failed=true
        fi
    elif type wget &> /dev/null; then
        if ! wget -c "$1" -O "$2"; then
            download_failed=true
        fi
    else
        echo "Cannot find download tool. Please install curl or wget."
        exit 1
    fi

    if $download_failed; then
        echo "Failed to download $1"
        rm -f "$2"
        exit 1
    fi
}

# check if unzip is missing (Z3)
function check_unzip {
    if ! type unzip &> /dev/null; then
        echo "Cannot find unzip. Please install unzip."
        exit 1
    fi
}

# check if xz is missing (LLVM)
function check_xz {
    if ! type xz &> /dev/null; then
        echo "Cannot find xz. Please install xz-utils."
        exit 1
    fi
}

function build_z3_from_source {
    mkdir "$Z3Home"
    echo "Downloading Z3 source..."
    generic_download_file "$SourceZ3" z3.zip
    check_unzip
    echo "Unzipping Z3 source..."
    mkdir z3-source
    unzip z3.zip -d z3-source

    echo "Building Z3..."
    mkdir z3-build
    cd z3-build
    # /* is a dirty hack to get z3-version...
    cmake -DCMAKE_INSTALL_PREFIX="$SVFHOME/$Z3Home" -DZ3_BUILD_LIBZ3_SHARED=false -DCMAKE_BUILD_TYPE="$BuildType" ../z3-source/*
    make -j${jobs}
    make install

    cd ..
    rm -r z3-source z3-build z3.zip
}

function build_llvm_from_source {
    mkdir "$LLVMHome"
    echo "Downloading LLVM source..."
    generic_download_file "$SourceLLVM" llvm.zip
    check_unzip
    echo "Unzipping LLVM source..."
    mkdir llvm-source
    unzip llvm.zip -d llvm-source

    echo "Building LLVM..."
    mkdir llvm-build
    cd llvm-build
    # /*/ is a dirty hack to get llvm-project-llvmorg-version...
    cmake -DCMAKE_INSTALL_PREFIX="$SVFHOME/$LLVMHome" -DCMAKE_BUILD_TYPE="$BuildType" ../llvm-source/*/llvm
    make -j${jobs}
    make install

    cd ..
    rm -r llvm-source llvm-build llvm.zip
}

########
# Download LLVM if need be.
#######
if [ ! -d "$LLVM_DIR" ]
then
    if [ ! -d "$LLVMHome" ]
    then
        if [ $BuildLLVMFromSource = true ]
        then
            build_llvm_from_source
        else
            echo "Downloading LLVM binary for $sysOS"
            generic_download_file "$LLVM" llvm.tar.xz
            check_xz
            echo "Unzipping llvm package..."
            mkdir -p "./$LLVMHome" && tar -xf llvm.tar.xz -C "./$LLVMHome" --strip-components 1 --no-same-owner
            rm llvm.tar.xz
        fi
    fi

    export LLVM_DIR="$SVFHOME/$LLVMHome"
fi

########
# Download Z3 if need be.
#######
if [ ! -d "$Z3_DIR" ]
then
    if [ ! -d "$Z3Home" ]
    then
        if [ $BuildZ3FromSource = true ]
        then
            build_z3_from_source
        else
            echo "Downloading Z3 binary for $sysOS"
            generic_download_file "$Z3" z3.zip
            check_unzip
            echo "Unzipping z3 package..."
            unzip -q "z3.zip" && mv ./z3-* ./$Z3Home
            rm z3.zip
        fi
    fi

    export Z3_DIR="$SVFHOME/$Z3Home"
fi

export PATH=$LLVM_DIR/bin:$PATH
echo "LLVM_DIR=$LLVM_DIR"
echo "Z3_DIR=$Z3_DIR"

########
# Build SVF
########
rm -rf ./"$BuildType-build"
mkdir ./"$BuildType-build"
cd ./"$BuildType-build"

cmake -DCMAKE_BUILD_TYPE="$BuildType" ../
make -j ${jobs}

########
# Set up environment variables of SVF
########
cd ../
if [[ "$BuildType" == "Debug" ]]
then
  . ./setup.sh debug
else
  . ./setup.sh
fi

#########
# Optionally, you can also specify a CXX_COMPILER and your $LLVM_HOME for your build
# cmake -DCMAKE_CXX_COMPILER=$LLVM_DIR/bin/clang++ -DLLVM_DIR=$LLVM_DIR
#########
