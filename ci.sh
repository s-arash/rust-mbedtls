#!/bin/bash
set -ex
cd "$(dirname "$0")"

repo_root=$(readlink -f $(dirname "${BASH_SOURCE[0]}"))

if [ -z $TRAVIS_RUST_VERSION ]; then
    echo "Expected TRAVIS_RUST_VERSION to be set in env"
    exit 1
fi

# Test logic start from here
export CFLAGS_x86_64_fortanix_unknown_sgx="-isystem/usr/include/x86_64-linux-gnu -mlvi-hardening -mllvm -x86-experimental-lvi-inline-asm-hardening"
export CC_x86_64_fortanix_unknown_sgx=clang-11
export CC_aarch64_unknown_linux_musl=/tmp/aarch64-linux-musl-cross/bin/aarch64-linux-musl-gcc
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER=/tmp/aarch64-linux-musl-cross/bin/aarch64-linux-musl-gcc
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_RUNNER=qemu-aarch64

cd "${repo_root}/mbedtls"
case "$TRAVIS_RUST_VERSION" in
    stable|beta|nightly)
        # Install the rust toolchain
        rustup default $TRAVIS_RUST_VERSION
        rustup target add --toolchain $TRAVIS_RUST_VERSION $TARGET
        printenv

        # The SGX target cannot be run under test like a ELF binary
        if [ "$TARGET" != "x86_64-fortanix-unknown-sgx" ]; then
            # make sure that explicitly providing the default target works
            cargo nextest run --target $TARGET --release
            cargo nextest run --features pkcs12 --target $TARGET
            cargo nextest run --features pkcs12_rc2 --target $TARGET
            cargo nextest run --features dsa --target $TARGET
            cargo nextest run --test async_session --features=async-rt --target $TARGET
            cargo nextest run --test async_session --features=async-rt,legacy_protocols --target $TARGET

            # If zlib is installed, test the zlib feature
            if [ -n "$ZLIB_INSTALLED" ]; then
                cargo nextest run --features zlib --target $TARGET
                cargo nextest run --test async_session --features=async-rt,zlib --target $TARGET
                cargo nextest run --test async_session --features=async-rt,zlib,legacy_protocols --target $TARGET
            fi

            # If AES-NI is supported, test the feature
            if [ -n "$AES_NI_SUPPORT" ]; then
                cargo nextest run --features force_aesni_support --target $TARGET
            fi

            # no_std tests only are able to run on x86 platform
            if [ "$TARGET" == "x86_64-unknown-linux-gnu" ] || [[ "$TARGET" =~ ^x86_64-pc-windows- ]]; then
                cargo nextest run --no-default-features --features no_std_deps,rdrand,time --target $TARGET
                cargo nextest run --no-default-features --features no_std_deps --target $TARGET
            fi

        else
            cargo +$TRAVIS_RUST_VERSION test --no-run --target=$TARGET
        fi
        ;;
    *)
        # Default case: If TRAVIS_RUST_VERSION does not match any of the above
        echo "Unknown version $TRAVIS_RUST_VERSION"
        exit 1
        ;;
esac
