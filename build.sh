#!/bin/bash
set -o nounset
set -o errexit
set -o pipefail

src_dir="$1"
install_dir="$2"
# todo: more configure options

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
    local config_args=(
        --prefix="$install_dir"
        --disable-openssl-compatible-defaults
        --disable-opensslextra
        --disable-oldnames
        --enable-alpn
        --enable-session-ticket
        --enable-aesni
        --enable-shared
        --enable-static
        # --enable-singlethreaded
    )
    ./configure "${config_args[@]}"
    make
    make install
}

# install_deps
build
