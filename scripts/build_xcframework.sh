#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_DIR="$BUILD_DIR/archives"
OUTPUT_DIR="$BUILD_DIR/output"
RESOURCES_DIR="$ROOT_DIR/Resources"

FRAMEWORK_NAME="MLKitRuntime"
BUNDLES=("LatinOCRResources.bundle" "MLKitImageLabelingResources.bundle")

log() { echo "==> $*"; }
fail() { echo "error: $*" >&2; exit 1; }

check_arch() {
  local binary="$1"
  local expected="$2"
  local actual
  actual="$(lipo -archs "$binary")"
  [ "$actual" = "$expected" ] || fail "$binary: expected arch '$expected', got '$actual'"
}

# Preflight: fail fast if required inputs are missing, before touching build state.
test -f "$ROOT_DIR/Package.swift" || fail "Package.swift not found at $ROOT_DIR"
for bundle in "${BUNDLES[@]}"; do
  test -d "$RESOURCES_DIR/$bundle" || fail "missing resource bundle: $RESOURCES_DIR/$bundle"
  test -f "$RESOURCES_DIR/$bundle/Info.plist" || fail "resource bundle missing Info.plist: $bundle"
done

log "Cleaning build directory (no reuse of prior DerivedData)"
rm -rf "$BUILD_DIR"
mkdir -p "$ARCHIVE_DIR" "$OUTPUT_DIR"

archive() {
  local destination="$1"
  local archive_path="$2"
  local derived_data_path="$3"
  shift 3

  xcodebuild archive \
    -scheme "$FRAMEWORK_NAME" \
    -destination "$destination" \
    -archivePath "$archive_path" \
    -derivedDataPath "$derived_data_path" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    CODE_SIGNING_ALLOWED=NO \
    "$@"
}

log "Archiving for iOS device (arm64)"
archive "generic/platform=iOS" "$ARCHIVE_DIR/ios" "$BUILD_DIR/derived/ios"

log "Archiving for iOS Simulator (x86_64 — upstream ML Kit 9.0.0-1 ships no arm64 simulator slice)"
archive "generic/platform=iOS Simulator" "$ARCHIVE_DIR/simulator" "$BUILD_DIR/derived/simulator" \
  ARCHS=x86_64 \
  ONLY_ACTIVE_ARCH=NO

for slice in "ios:arm64" "simulator:x86_64"; do
  archive_name="${slice%%:*}"
  expected_arch="${slice##*:}"
  archive_path="$ARCHIVE_DIR/$archive_name.xcarchive"
  framework="$archive_path/Products/usr/local/lib/$FRAMEWORK_NAME.framework"

  test -d "$framework" || fail "archive did not produce framework: $framework"
  binary="$framework/$FRAMEWORK_NAME"
  test -f "$binary" || fail "archived framework missing binary: $binary"
  check_arch "$binary" "$expected_arch"
  log "Verified $archive_name binary architecture: $expected_arch"

  log "Embedding resource bundles into $archive_name slice"
  for bundle in "${BUNDLES[@]}"; do
    rm -rf "$framework/$bundle"
    cp -R "$RESOURCES_DIR/$bundle" "$framework/$bundle"
    test -d "$framework/$bundle" || fail "failed to copy $bundle into $archive_name slice"
  done
done

install_swift_module() {
  local framework="$1"
  local derived_data_path="$2"
  local architecture="$3"
  local triple="$4"
  local objects_dir

  objects_dir="$(find "$derived_data_path/Build/Intermediates.noindex/ArchiveIntermediates" \
    -type d -path "*/$FRAMEWORK_NAME.build/Objects-normal/$architecture" -print -quit)"
  test -n "$objects_dir" || fail "could not locate Swift build objects for $architecture under $derived_data_path"

  local module_dir="$framework/Modules/$FRAMEWORK_NAME.swiftmodule"
  mkdir -p "$module_dir"

  local ext
  for ext in swiftinterface private.swiftinterface swiftdoc swiftmodule swiftsourceinfo; do
    local source="$objects_dir/$FRAMEWORK_NAME.$ext"
    test -f "$source" || fail "missing Swift module artifact for $triple: $source"
    cp "$source" "$module_dir/$triple.$ext"
  done
}

log "Installing Swift module interfaces"
install_swift_module \
  "$ARCHIVE_DIR/ios.xcarchive/Products/usr/local/lib/$FRAMEWORK_NAME.framework" \
  "$BUILD_DIR/derived/ios" \
  arm64 \
  arm64-apple-ios
install_swift_module \
  "$ARCHIVE_DIR/simulator.xcarchive/Products/usr/local/lib/$FRAMEWORK_NAME.framework" \
  "$BUILD_DIR/derived/simulator" \
  x86_64 \
  x86_64-apple-ios-simulator

log "Creating XCFramework"
XCFRAMEWORK="$OUTPUT_DIR/$FRAMEWORK_NAME.xcframework"
xcodebuild -create-xcframework \
  -framework "$ARCHIVE_DIR/ios.xcarchive/Products/usr/local/lib/$FRAMEWORK_NAME.framework" \
  -framework "$ARCHIVE_DIR/simulator.xcarchive/Products/usr/local/lib/$FRAMEWORK_NAME.framework" \
  -output "$XCFRAMEWORK"

log "Verifying assembled XCFramework before packaging"
test -f "$XCFRAMEWORK/Info.plist" || fail "xcframework missing Info.plist"

for slice in "ios-arm64:arm64" "ios-x86_64-simulator:x86_64"; do
  slice_id="${slice%%:*}"
  expected_arch="${slice##*:}"
  slice_framework="$XCFRAMEWORK/$slice_id/$FRAMEWORK_NAME.framework"
  binary="$slice_framework/$FRAMEWORK_NAME"

  test -f "$binary" || fail "xcframework missing binary for slice $slice_id"
  check_arch "$binary" "$expected_arch"

  for bundle in "${BUNDLES[@]}"; do
    test -d "$slice_framework/$bundle" || fail "xcframework slice $slice_id missing bundle $bundle"
  done

  test -d "$slice_framework/Modules/$FRAMEWORK_NAME.swiftmodule" || \
    fail "xcframework slice $slice_id missing Swift module directory"
done

log "All slices verified: correct architecture, both resource bundles, Swift module present"

ZIP_PATH="$OUTPUT_DIR/$FRAMEWORK_NAME.xcframework.zip"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$XCFRAMEWORK" "$ZIP_PATH"

ZIP_SIZE=$(stat -f%z "$ZIP_PATH")
CHECKSUM=$(swift package compute-checksum "$ZIP_PATH")

log "Build complete"
echo "zip:      $ZIP_PATH"
echo "size:     $ZIP_SIZE bytes"
echo "checksum: $CHECKSUM"
