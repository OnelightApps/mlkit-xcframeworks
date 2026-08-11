# MLKitRuntime XCFramework

Dynamic XCFramework wrapper around the ML Kit 9.0.0-1 modules used by
OneLightApps Flutter applications: on-device image labeling (default +
custom/NSFW models) and Latin text recognition (OCR). Model resources are
embedded inside the framework so host applications need no separate
resource-copy build phase.

## Build

```bash
./scripts/build_xcframework.sh
```

Every run wipes `build/` first, archives fresh for device and simulator (no
reuse of prior `DerivedData`), and fails fast if an input framework, a
resource bundle, an architecture, or a Swift module artifact is missing or
wrong. It prints the final zip path, exact size, and SwiftPM checksum.

Output: `build/output/MLKitRuntime.xcframework.zip`.

**On reproducibility:** the process is deterministic — same pinned inputs,
same clean-room build with no leftover state — but the resulting Mach-O
binaries and zip are not byte-for-byte identical across runs (compiler-embedded
UUIDs and filesystem timestamps vary). Always compute the checksum from the
exact zip you intend to publish; never reuse a checksum from a previous build.

## Verify

```bash
./scripts/verify_xcframework.sh [path-to-zip]
```

Defaults to `build/output/MLKitRuntime.xcframework.zip`. Independently audits
the packaged artifact: zip integrity, `Info.plist` slice declarations, exact
per-slice architecture, framework install name, linked libraries (fails if
anything beyond system libraries and the intentionally-external
`GoogleToolboxForMac` shows up), presence of both resource bundles in both
slices, Swift interface/module files, absence of any code signature, absence
of absolute local build-machine paths, and the SwiftPM checksum.

## Embedded resources

Baked into `MLKitRuntime.framework` for both slices — no host-side copy step:

- `LatinOCRResources.bundle` — Latin OCR recognizer + language-ID models
- `MLKitImageLabelingResources.bundle` — default on-device image-labeling model

## Architectures

- iOS device: `arm64`
- iOS Simulator: `x86_64`

The upstream ML Kit 9.0.0-1 binaries ship no `arm64` simulator slice, so the
simulator archive is forced to `x86_64` (`ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO`).
On Apple Silicon Macs this means the simulator slice runs under Rosetta
translation — there is no native Apple Silicon simulator slice available
upstream to build against.

## Runtime dependency contract

`MLKitRuntime.xcframework` never embeds a copy of Google's shared Objective-C
runtime classes. Verified by symbol audit (`nm`) across every bundled ML Kit
binary target: none of them *define* these classes, they only reference them
as undefined symbols, resolved at runtime either via an explicit `@rpath`
load command (`GoogleToolboxForMac`) or deferred entirely to dyld's flat
namespace (`-Xlinker -undefined -Xlinker dynamic_lookup`, for the rest). This
is why the host application must link matching versions itself, exactly once,
for the app to resolve at launch instead of crashing with
`symbol not found in flat namespace`:

- `GTMSessionFetcherCore` 3.5.0
- `GoogleUtilities` 8.1.0 (`GULLogger`, `GULUserDefaults`)
- `GoogleDataTransport` 10.1.0
- `GoogleToolboxForMac` from the matching ML Kit 9.0.0-1 binaries
  (`https://github.com/d-date/google-mlkit-swiftpm`, release `9.0.0-1`) —
  this one is linked as an explicit `@rpath/GoogleToolboxForMac.framework`
  dependency, not flat-namespace lookup, so the host must embed an actual
  `GoogleToolboxForMac.framework` at runtime, not merely have its symbols
  available some other way.

`GoogleDataTransport` in particular has no dedicated binary in this package;
today it is only guaranteed if the host app also depends on `firebase-ios-sdk`
(which pins compatible versions transitively). A host without Firebase must
add it directly, exact-pinned to `10.1.0`, or `GDTCORTransport` will be
unresolved at launch.

Keeping these four out of `MLKitRuntime` means an app that already uses
Firebase (as OneLightApps apps do) does not get a second embedded copy of the
same Objective-C classes — which would otherwise crash at launch with a
"class implemented in both ... and ..." duplicate-class abort.

## Reference build (9.0.0-1.0.2)

Figures from a from-scratch build on this toolchain (Xcode 26.5); recompute
before every release per the reproducibility note above:

| Artifact | Value |
|---|---|
| `MLKitRuntime.xcframework.zip` size | 63,488,585 bytes |
| SwiftPM checksum | `ca2cd4f95cd05a20e29300252e46d94e6ad493dc4f5610e2b7475dfae9991a43` |
| Device (`arm64`) binary size | 87,155,928 bytes |
| Simulator (`x86_64`) binary size | 93,865,544 bytes |
