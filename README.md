# MLKitRuntime XCFramework

Reproducible dynamic XCFramework wrapper around the ML Kit modules used by
OneLightApps Flutter applications. OCR and image-labeling models are embedded
inside their owning framework so host applications need no resource-copy build
phases.

## Build

```bash
./scripts/build_xcframework.sh
```

Output: `build/output/MLKitRuntime.xcframework.zip`.

## Runtime dependencies

The host Swift package must link these products once:

- `GTMSessionFetcherCore` 3.5.0
- `GULLogger` and `GULUserDefaults` 8.1.0
- `GoogleDataTransport` 10.1.0
- `GoogleToolboxForMac` from the matching ML Kit 9.0.0-1 binaries

These stay outside `MLKitRuntime` so applications that already use Firebase do
not receive a second embedded copy of the shared Google Objective-C classes.

## Architectures

- iOS device: arm64
- iOS Simulator: x86_64

The upstream ML Kit 9.0.0-1 binaries do not contain an arm64 simulator slice.
