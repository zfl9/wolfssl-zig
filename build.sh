#!/bin/bash
set -o nounset
set -o errexit
set -o pipefail

source "$1" # conf.sh
src_dir="$2"
install_dir="$3"
# zig_exe="$3"
# zig_target="$4"
# zig_mcpu="$5"
# lto_mode="$6"
# single_threaded="$7"
# todo: more configure options

# convert to absolute path
mkdir -p "$install_dir"
install_dir="$(cd "$install_dir" && pwd)"

# enter the source directory
cd "$src_dir"

install_deps() {
    if command -v apt &>/dev/null; then
        sudo apt install -y --no-upgrade make autoconf automake libtool
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm --needed make autoconf automake libtool
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y make autoconf automake libtool
    elif command -v yum &>/dev/null; then
        sudo yum install -y make autoconf automake libtool
    else
        echo "please ensure the dependencies are installed:"
        echo ">>> make autoconf automake libtool"
    fi
}

build() {
    ./autogen.sh

    local lto_flag=""
    if [ "$lto_mode" = "full" -o "$lto_mode" = "thin" ]; then
        lto_flag="-flto=$lto_mode"
    fi

    # TODO: -ffunction-sections -fdata-sections -Wl,--gc-sections

    # configure options
    local config_args=(
        CC="$zig_exe cc -target $zig_target -mcpu=$zig_mcpu -O3 -Xclang -O3 $lto_flag"
        CXX="$zig_exe c++ -target $zig_target -mcpu=$zig_mcpu -O3 -Xclang -O3 $lto_flag"
        AR="$zig_exe ar"
        RANLIB="$zig_exe ranlib"
        --host="$zig_target"
        --prefix="$install_dir"
        --enable-static
        --disable-shared
        --disable-openssl-compatible-defaults
        --disable-opensslextra
        --disable-oldnames
        --enable-alpn
        --enable-session-ticket
        --enable-aesni
    )
    if ((single_threaded)); then
        config_args+=("--enable-singlethreaded")
    fi

    ./configure "${config_args[@]}"
    make
    make install
}

# TODO: clean up the build directory before running the script

# install_deps
build
