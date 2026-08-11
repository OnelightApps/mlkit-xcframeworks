#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ZIP_PATH="${1:-$ROOT_DIR/build/output/MLKitRuntime.xcframework.zip}"

FRAMEWORK_NAME="MLKitRuntime"
EXPECTED_INSTALL_NAME="@rpath/$FRAMEWORK_NAME.framework/$FRAMEWORK_NAME"
BUNDLES=("LatinOCRResources.bundle" "MLKitImageLabelingResources.bundle")
# xcodebuild -create-xcframework intentionally drops the compiler-private, binary
# .swiftmodule when a .swiftinterface is present (the interface is toolchain-portable,
# the binary module is not), so it must not be required in the packaged artifact.
SWIFT_EXTENSIONS=(swiftinterface private.swiftinterface swiftdoc swiftsourceinfo)

# Slices, expected arch, and expected Swift module triple, colon-joined.
SLICES=(
  "ios-arm64:arm64:arm64-apple-ios"
  "ios-x86_64-simulator:x86_64:x86_64-apple-ios-simulator"
)

# Anything a linked binary is allowed to depend on besides the framework itself.
# GoogleToolboxForMac is an intentionally external dylib (see README) — everything
# else must be a system framework/library so the artifact carries no stray deps.
ALLOWED_DYLIB_PATTERN='^(/usr/lib/|/System/Library/Frameworks/|@rpath/GoogleToolboxForMac\.framework/GoogleToolboxForMac$|@rpath/'"$FRAMEWORK_NAME"'\.framework/'"$FRAMEWORK_NAME"'$)'

PASS=0
FAIL=0

pass() { echo "  [OK] $*"; PASS=$((PASS + 1)); }
fail() { echo "  [FAIL] $*" >&2; FAIL=$((FAIL + 1)); }
section() { echo; echo "== $* =="; }

test -f "$ZIP_PATH" || { echo "error: zip not found at $ZIP_PATH" >&2; exit 1; }

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

section "Zip integrity"
if unzip -tq "$ZIP_PATH" >/dev/null; then
  pass "unzip -t reports no CRC/structural errors"
else
  fail "unzip -t reported a corrupt archive"
fi

ditto -x -k "$ZIP_PATH" "$WORK_DIR"
XCFRAMEWORK="$WORK_DIR/$FRAMEWORK_NAME.xcframework"
if [ -d "$XCFRAMEWORK" ]; then
  pass "archive extracts to $FRAMEWORK_NAME.xcframework"
else
  fail "extracted archive does not contain $FRAMEWORK_NAME.xcframework"
  echo
  echo "$FAIL check(s) failed, $PASS passed."
  exit 1
fi

section "Info.plist"
PLIST="$XCFRAMEWORK/Info.plist"
if [ -f "$PLIST" ]; then
  pass "Info.plist present"
  for slice in "${SLICES[@]}"; do
    slice_id="${slice%%:*}"
    if /usr/libexec/PlistBuddy -c "Print :AvailableLibraries" "$PLIST" 2>/dev/null | grep -q "$slice_id"; then
      pass "Info.plist lists library identifier $slice_id"
    else
      fail "Info.plist missing library identifier $slice_id"
    fi
  done
else
  fail "Info.plist missing at xcframework root"
fi

for slice in "${SLICES[@]}"; do
  slice_id="${slice%%:*}"
  expected_arch="$(echo "$slice" | cut -d: -f2)"
  triple="$(echo "$slice" | cut -d: -f3)"
  framework="$XCFRAMEWORK/$slice_id/$FRAMEWORK_NAME.framework"
  binary="$framework/$FRAMEWORK_NAME"

  section "Slice $slice_id"

  if [ -f "$binary" ]; then
    pass "binary present"
  else
    fail "binary missing at $binary"
    continue
  fi

  actual_arch="$(lipo -archs "$binary" 2>/dev/null || echo "")"
  if [ "$actual_arch" = "$expected_arch" ]; then
    pass "architecture is exactly '$expected_arch'"
  else
    fail "expected architecture '$expected_arch', got '$actual_arch'"
  fi

  install_name="$(otool -D "$binary" | tail -n +2)"
  if [ "$install_name" = "$EXPECTED_INSTALL_NAME" ]; then
    pass "install name is '$EXPECTED_INSTALL_NAME'"
  else
    fail "unexpected install name: '$install_name'"
  fi

  echo "  linked libraries:"
  bad_deps=0
  while IFS= read -r dep; do
    [ -z "$dep" ] && continue
    echo "    $dep"
    if [[ ! "$dep" =~ $ALLOWED_DYLIB_PATTERN ]]; then
      bad_deps=$((bad_deps + 1))
      fail "unexpected linked dependency: $dep"
    fi
  done < <(otool -L "$binary" | tail -n +2 | awk '{print $1}')
  [ "$bad_deps" -eq 0 ] && pass "no unexpected linked dependencies (only system libraries + GoogleToolboxForMac)"

  for bundle in "${BUNDLES[@]}"; do
    if [ -d "$framework/$bundle" ] && [ -f "$framework/$bundle/Info.plist" ]; then
      pass "$bundle present with Info.plist"
    else
      fail "$bundle missing or incomplete in $slice_id"
    fi
  done

  module_dir="$framework/Modules/$FRAMEWORK_NAME.swiftmodule"
  for ext in "${SWIFT_EXTENSIONS[@]}"; do
    if [ -f "$module_dir/$triple.$ext" ]; then
      pass "Swift module artifact $triple.$ext present"
    else
      fail "missing Swift module artifact: $module_dir/$triple.$ext"
    fi
  done

  # codesign exits non-zero for unsigned code, which would trip `pipefail` even
  # when the grep below matches — capture output first so its exit code can't leak.
  codesign_output="$(codesign -dv "$binary" 2>&1 || true)"
  if echo "$codesign_output" | grep -q "code object is not signed at all"; then
    pass "binary carries no code signature"
  else
    fail "binary unexpectedly carries a code signature (not portable/reproducible)"
  fi

  local_path_hits="$(strings "$binary" | grep -E "/Users/[A-Za-z0-9_.-]+" || true)"
  if [ -z "$local_path_hits" ]; then
    pass "no absolute local build-machine paths embedded in binary"
  else
    fail "binary embeds local paths:"
    echo "$local_path_hits" | sed 's/^/    /'
  fi
done

section "Info.plist absolute paths"
plist_path_hits=""
while IFS= read -r plist_file; do
  hits="$(grep -E "/Users/[A-Za-z0-9_.-]+" "$plist_file" || true)"
  [ -n "$hits" ] && plist_path_hits="$plist_path_hits$plist_file: $hits\n"
done < <(find "$XCFRAMEWORK" -name "Info.plist")
if [ -z "$plist_path_hits" ]; then
  pass "no absolute local paths in any Info.plist"
else
  fail "Info.plist(s) contain local paths:"
  echo -e "$plist_path_hits" | sed 's/^/    /'
fi

section "SwiftPM checksum"
CHECKSUM="$(swift package compute-checksum "$ZIP_PATH")"
ZIP_SIZE="$(stat -f%z "$ZIP_PATH")"
echo "  zip:      $ZIP_PATH"
echo "  size:     $ZIP_SIZE bytes"
echo "  checksum: $CHECKSUM"
pass "checksum computed"

echo
echo "$PASS check(s) passed, $FAIL check(s) failed."
[ "$FAIL" -eq 0 ]
