// swift-tools-version: 5.9
import PackageDescription

private let releaseBase =
    "https://github.com/d-date/google-mlkit-swiftpm/releases/download/9.0.0-1"

let package = Package(
    name: "MLKitRuntime",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "MLKitRuntime", type: .dynamic, targets: ["MLKitRuntime"])
    ],
    targets: [
        .binaryTarget(
            name: "MLImage",
            url: "\(releaseBase)/MLImage.xcframework.zip",
            checksum: "ed3a23f4f5bf4c1f461337311a29dd12a3d01676dd49ea06b9b21cab223159f5"
        ),
        .binaryTarget(
            name: "MLKitCommon",
            url: "\(releaseBase)/MLKitCommon.xcframework.zip",
            checksum: "0c3523adc6248b5fd7e71c5af1c3e028a2ffcd20ca6add03283e20a09740f43f"
        ),
        .binaryTarget(
            name: "MLKitVision",
            url: "\(releaseBase)/MLKitVision.xcframework.zip",
            checksum: "b26f8c96d1e12515b990fca0b2237d60363d7bddc925d5ec61d7ee7d8b5e83c3"
        ),
        .binaryTarget(
            name: "GoogleToolboxForMac",
            url: "\(releaseBase)/GoogleToolboxForMac.xcframework.zip",
            checksum: "c095707fd64bad2f36cd9bcc86251de6aab7197d5b35112f3cdf40c6c94a6b4b"
        ),
        .binaryTarget(
            name: "MLKitTextRecognition",
            url: "\(releaseBase)/MLKitTextRecognition.xcframework.zip",
            checksum: "1f20493b54611a251cae278fd9f206c3009eee3de7091e5e4f1cb1a050526f72"
        ),
        .binaryTarget(
            name: "MLKitTextRecognitionCommon",
            url: "\(releaseBase)/MLKitTextRecognitionCommon.xcframework.zip",
            checksum: "9b6cbfd695e5458e5ccab905d2c6a641cd29fe60a6ec4fd8acb62ef9b8ac91e7"
        ),
        .binaryTarget(
            name: "MLKitImageLabeling",
            url: "\(releaseBase)/MLKitImageLabeling.xcframework.zip",
            checksum: "e3a35c622d10f15a5281d50365120e224df4c2e7432ba9421897adff653eb16e"
        ),
        .binaryTarget(
            name: "MLKitImageLabelingCustom",
            url: "\(releaseBase)/MLKitImageLabelingCustom.xcframework.zip",
            checksum: "fbfb8ae9ae9d1b37f4fce4be32f13758a4a5286890e25cdce5017c6460d9251b"
        ),
        .binaryTarget(
            name: "MLKitImageLabelingCommon",
            url: "\(releaseBase)/MLKitImageLabelingCommon.xcframework.zip",
            checksum: "03cd40ff3b2fe0e88b6c3bf9267f74b24bc650ea9b6eac35ea3dfecd27773520"
        ),
        .target(
            name: "MLKitRuntime",
            dependencies: [
                "MLImage",
                "MLKitCommon",
                "MLKitVision",
                "GoogleToolboxForMac",
                "MLKitTextRecognition",
                "MLKitTextRecognitionCommon",
                "MLKitImageLabeling",
                "MLKitImageLabelingCustom",
                "MLKitImageLabelingCommon"
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-ObjC",
                    "-Xlinker", "-undefined",
                    "-Xlinker", "dynamic_lookup"
                ])
            ]
        )
    ]
)
