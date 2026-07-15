#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_DIR="$BUILD_DIR/archives"
OUTPUT_DIR="$BUILD_DIR/output"
RESOURCES_DIR="$ROOT_DIR/Resources"

rm -rf "$BUILD_DIR"
mkdir -p "$ARCHIVE_DIR" "$OUTPUT_DIR"

archive() {
  local destination="$1"
  local archive_path="$2"
  local derived_data_path="$3"
  shift 3

  xcodebuild archive \
    -scheme MLKitRuntime \
    -destination "$destination" \
    -archivePath "$archive_path" \
    -derivedDataPath "$derived_data_path" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    CODE_SIGNING_ALLOWED=NO \
    "$@"
}

archive "generic/platform=iOS" "$ARCHIVE_DIR/ios" "$BUILD_DIR/derived/ios"
archive "generic/platform=iOS Simulator" "$ARCHIVE_DIR/simulator" "$BUILD_DIR/derived/simulator" \
  ARCHS=x86_64 \
  ONLY_ACTIVE_ARCH=NO

for archive_path in "$ARCHIVE_DIR/ios.xcarchive" "$ARCHIVE_DIR/simulator.xcarchive"; do
  framework="$archive_path/Products/usr/local/lib/MLKitRuntime.framework"
  test -d "$framework"
  cp -R "$RESOURCES_DIR/LatinOCRResources.bundle" "$framework/LatinOCRResources.bundle"
  cp -R "$RESOURCES_DIR/MLKitImageLabelingResources.bundle" "$framework/MLKitImageLabelingResources.bundle"
done

install_swift_module() {
  local framework="$1"
  local derived_data_path="$2"
  local architecture="$3"
  local triple="$4"
  local objects_dir

  objects_dir="$(find "$derived_data_path/Build/Intermediates.noindex/ArchiveIntermediates" \
    -type d -path "*/MLKitRuntime.build/Objects-normal/$architecture" -print -quit)"
  test -n "$objects_dir"

  module_dir="$framework/Modules/MLKitRuntime.swiftmodule"
  mkdir -p "$module_dir"
  cp "$objects_dir/MLKitRuntime.swiftinterface" "$module_dir/$triple.swiftinterface"
  cp "$objects_dir/MLKitRuntime.private.swiftinterface" "$module_dir/$triple.private.swiftinterface"
  cp "$objects_dir/MLKitRuntime.swiftdoc" "$module_dir/$triple.swiftdoc"
  cp "$objects_dir/MLKitRuntime.swiftmodule" "$module_dir/$triple.swiftmodule"
  cp "$objects_dir/MLKitRuntime.swiftsourceinfo" "$module_dir/$triple.swiftsourceinfo"
}

install_swift_module \
  "$ARCHIVE_DIR/ios.xcarchive/Products/usr/local/lib/MLKitRuntime.framework" \
  "$BUILD_DIR/derived/ios" \
  arm64 \
  arm64-apple-ios
install_swift_module \
  "$ARCHIVE_DIR/simulator.xcarchive/Products/usr/local/lib/MLKitRuntime.framework" \
  "$BUILD_DIR/derived/simulator" \
  x86_64 \
  x86_64-apple-ios-simulator

xcodebuild -create-xcframework \
  -framework "$ARCHIVE_DIR/ios.xcarchive/Products/usr/local/lib/MLKitRuntime.framework" \
  -framework "$ARCHIVE_DIR/simulator.xcarchive/Products/usr/local/lib/MLKitRuntime.framework" \
  -output "$OUTPUT_DIR/MLKitRuntime.xcframework"

ditto -c -k --sequesterRsrc --keepParent \
  "$OUTPUT_DIR/MLKitRuntime.xcframework" \
  "$OUTPUT_DIR/MLKitRuntime.xcframework.zip"

swift package compute-checksum "$OUTPUT_DIR/MLKitRuntime.xcframework.zip"
