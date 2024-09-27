#!/bin/bash
BINDINGS_DIR="./bindings/swift"
UNIFFI_BINDGEN_BIN="cargo +1.74.0 run --manifest-path bindings/uniffi-bindgen/Cargo.toml"

# Ensure correct toolchain is installed and set
rustup install 1.74.0
rustup component add rust-src --toolchain 1.74.0

# Install the necessary Rust target toolchains
rustup target add aarch64-apple-ios x86_64-apple-ios --toolchain 1.74.0
rustup target add aarch64-apple-ios-sim --toolchain 1.74.0
rustup target add aarch64-apple-darwin x86_64-apple-darwin --toolchain 1.74.0

# Build Rust libraries for each target
cargo +1.74.0 build --profile release-smaller --features uniffi || exit 1
cargo +1.74.0 build --profile release-smaller --features uniffi --target x86_64-apple-darwin || exit 1
cargo +1.74.0 build --profile release-smaller --features uniffi --target aarch64-apple-darwin || exit 1
cargo +1.74.0 build --profile release-smaller --features uniffi --target x86_64-apple-ios || exit 1
cargo +1.74.0 build --profile release-smaller --features uniffi --target aarch64-apple-ios || exit 1
cargo +1.74.0 build --release --features uniffi --target aarch64-apple-ios-sim || exit 1

# Combine iOS-sim and macOS libraries using lipo for multi-architecture support
mkdir -p target/lipo-ios-sim/release-smaller || exit 1
lipo target/aarch64-apple-ios-sim/release/libldk_node.a target/x86_64-apple-ios/release-smaller/libldk_node.a -create -output target/lipo-ios-sim/release-smaller/libldk_node.a || exit 1

mkdir -p target/lipo-macos/release-smaller || exit 1
lipo target/aarch64-apple-darwin/release-smaller/libldk_node.a target/x86_64-apple-darwin/release-smaller/libldk_node.a -create -output target/lipo-macos/release-smaller/libldk_node.a || exit 1

# Generate Swift bindings using Uniffi
$UNIFFI_BINDGEN_BIN generate bindings/ldk_node.udl --language swift -o "$BINDINGS_DIR" || exit 1

# Swift library creation
mkdir -p $BINDINGS_DIR

swiftc -module-name LDKNode -emit-library -o "$BINDINGS_DIR"/libldk_node.dylib -emit-module -emit-module-path "$BINDINGS_DIR" -parse-as-library -L ./target/release-smaller -lldk_node -Xcc -fmodule-map-file="$BINDINGS_DIR"/LDKNodeFFI.modulemap "$BINDINGS_DIR"/LDKNode.swift -v || exit 1

# Create xcframework from Swift file and libraries
mkdir -p "$BINDINGS_DIR"/Sources/LDKNode || exit 1

# Patch LDKNode.swift with `SystemConfiguration` import
sed -i '' '4s/^/import SystemConfiguration\n/' "$BINDINGS_DIR"/LDKNode.swift

mv "$BINDINGS_DIR"/LDKNode.swift "$BINDINGS_DIR"/Sources/LDKNode/LDKNode.swift || exit 1
cp "$BINDINGS_DIR"/LDKNodeFFI.h "$BINDINGS_DIR"/LDKNodeFFI.xcframework/ios-arm64/LDKNodeFFI.framework/Headers || exit 1
cp "$BINDINGS_DIR"/LDKNodeFFI.h "$BINDINGS_DIR"/LDKNodeFFI.xcframework/ios-arm64_x86_64-simulator/LDKNodeFFI.framework/Headers || exit 1
cp "$BINDINGS_DIR"/LDKNodeFFI.h "$BINDINGS_DIR"/LDKNodeFFI.xcframework/macos-arm64_x86_64/LDKNodeFFI.framework/Headers || exit 1
cp target/aarch64-apple-ios/release-smaller/libldk_node.a "$BINDINGS_DIR"/LDKNodeFFI.xcframework/ios-arm64/LDKNodeFFI.framework/LDKNodeFFI || exit 1
cp target/lipo-ios-sim/release-smaller/libldk_node.a "$BINDINGS_DIR"/LDKNodeFFI.xcframework/ios-arm64_x86_64-simulator/LDKNodeFFI.framework/LDKNodeFFI || exit 1
cp target/lipo-macos/release-smaller/libldk_node.a "$BINDINGS_DIR"/LDKNodeFFI.xcframework/macos-arm64_x86_64/LDKNodeFFI.framework/LDKNodeFFI || exit 1

# Clean up
rm "$BINDINGS_DIR"/LDKNodeFFI.h || exit 1
rm "$BINDINGS_DIR"/LDKNodeFFI.modulemap || exit 1

echo "Build finished successfully!"