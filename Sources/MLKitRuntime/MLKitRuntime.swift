import Foundation
@_implementationOnly import MLKitCommon
@_implementationOnly import MLKitImageLabeling
@_implementationOnly import MLKitImageLabelingCustom
@_implementationOnly import MLKitTextRecognition
@_implementationOnly import MLKitVision
@_implementationOnly import UIKit

public struct MLKitRuntimeLabel: Sendable {
    public let confidence: Double
    public let text: String
    public let index: Int

    public init(confidence: Double, text: String, index: Int) {
        self.confidence = confidence
        self.text = text
        self.index = index
    }
}

public struct MLKitRuntimeRect: Sendable {
    public let left: Double
    public let top: Double
    public let right: Double
    public let bottom: Double

    public init(left: Double, top: Double, right: Double, bottom: Double) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }
}

public struct MLKitRuntimeTextBlock: Sendable {
    public let text: String
    public let boundingBox: MLKitRuntimeRect

    public init(text: String, boundingBox: MLKitRuntimeRect) {
        self.text = text
        self.boundingBox = boundingBox
    }
}

public struct MLKitRuntimeRecognizedText: Sendable {
    public let fullText: String
    public let blocks: [MLKitRuntimeTextBlock]

    public init(fullText: String, blocks: [MLKitRuntimeTextBlock]) {
        self.fullText = fullText
        self.blocks = blocks
    }
}

public enum MLKitRuntimeError: LocalizedError {
    case imageNotFound(String)

    public var errorDescription: String? {
        switch self {
        case let .imageNotFound(path):
            return "Image not found at path: \(path)"
        }
    }
}

public final class MLKitRuntimeClient: @unchecked Sendable {
    public static let shared = MLKitRuntimeClient()

    private var defaultLabeler: ImageLabeler?
    private var customLabelers: [String: ImageLabeler] = [:]
    private var textRecognizer: TextRecognizer?

    private init() {}

    public func labelImage(
        at imagePath: String,
        modelPath: String?,
        confidenceThreshold: Float,
        maxResultCount: Int,
        completion: @escaping (Result<[MLKitRuntimeLabel], Error>) -> Void
    ) {
        guard let image = UIImage(contentsOfFile: imagePath) else {
            completion(.failure(MLKitRuntimeError.imageNotFound(imagePath)))
            return
        }

        let visionImage = VisionImage(image: image)
        visionImage.orientation = image.imageOrientation

        let labeler: ImageLabeler
        if let modelPath {
            let resolvedPath = Self.resolvedModelPath(modelPath)
            if let cached = customLabelers[resolvedPath] {
                labeler = cached
            } else {
                let options = CustomImageLabelerOptions(
                    localModel: LocalModel(path: resolvedPath)
                )
                options.confidenceThreshold = NSNumber(value: confidenceThreshold)
                options.maxResultCount = maxResultCount
                labeler = ImageLabeler.imageLabeler(options: options)
                customLabelers[resolvedPath] = labeler
            }
        } else if let defaultLabeler {
            labeler = defaultLabeler
        } else {
            let options = ImageLabelerOptions()
            options.confidenceThreshold = NSNumber(value: confidenceThreshold)
            let newLabeler = ImageLabeler.imageLabeler(options: options)
            defaultLabeler = newLabeler
            labeler = newLabeler
        }

        labeler.process(visionImage) { labels, error in
            if let error {
                completion(.failure(error))
                return
            }
            completion(.success((labels ?? []).map {
                MLKitRuntimeLabel(
                    confidence: Double($0.confidence),
                    text: $0.text,
                    index: $0.index
                )
            }))
        }
    }

    public func recognizeText(
        at imagePath: String,
        completion: @escaping (Result<MLKitRuntimeRecognizedText?, Error>) -> Void
    ) {
        guard let image = UIImage(contentsOfFile: imagePath) else {
            completion(.failure(MLKitRuntimeError.imageNotFound(imagePath)))
            return
        }

        let visionImage = VisionImage(image: image)
        visionImage.orientation = image.imageOrientation
        let recognizer = textRecognizer ?? TextRecognizer.textRecognizer()
        textRecognizer = recognizer

        recognizer.process(visionImage) { text, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let text else {
                completion(.success(nil))
                return
            }
            completion(.success(MLKitRuntimeRecognizedText(
                fullText: text.text,
                blocks: text.blocks.map {
                    let frame = $0.frame
                    return MLKitRuntimeTextBlock(
                        text: $0.text,
                        boundingBox: MLKitRuntimeRect(
                            left: frame.minX,
                            top: frame.minY,
                            right: frame.maxX,
                            bottom: frame.maxY
                        )
                    )
                }
            )))
        }
    }

    private static func resolvedModelPath(_ modelPath: String) -> String {
        let url = URL(fileURLWithPath: modelPath)
        guard url.pathExtension.lowercased() != "tflite" else {
            return modelPath
        }

        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(url.lastPathComponent)
            .appendingPathExtension("tflite")
            .path
        if !FileManager.default.fileExists(atPath: destination) {
            try? FileManager.default.copyItem(atPath: modelPath, toPath: destination)
        }
        return FileManager.default.fileExists(atPath: destination) ? destination : modelPath
    }
}
