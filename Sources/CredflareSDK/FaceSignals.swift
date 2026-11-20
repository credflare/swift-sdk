import Foundation
import CoreGraphics
import CoreVideo
import ImageIO
import Vision

public protocol FaceSignalProvider: AnyObject {
    var name: String { get }
    func reset()
    func sample(from pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, t: Int) -> FaceSample
}

public struct VisionSignalNormalizer: Sendable {
    public static let fallbackEyeRatio = 0.27
    public static let fallbackMouthRatio = 0.95
    public static let baselineFrames = 8
    public static let closedEyeFraction = 0.35
    public static let fullSmileWidening = 0.18

    private var eyeRatios: [Double] = []
    private var mouthRatios: [Double] = []
    public init() {}

    public var eyeBaseline: Double { Self.median(eyeRatios) ?? Self.fallbackEyeRatio }
    public var mouthBaseline: Double { Self.median(mouthRatios) ?? Self.fallbackMouthRatio }

    public mutating func eyeOpen(ratio: Double) -> Double {
        if eyeRatios.count < Self.baselineFrames { eyeRatios.append(ratio) }
        let relative = ratio / eyeBaseline
        return Self.clamp((relative - Self.closedEyeFraction) / (1 - Self.closedEyeFraction))
    }

    public mutating func smile(ratio: Double) -> Double {
        if mouthRatios.count < Self.baselineFrames { mouthRatios.append(ratio) }
        return Self.clamp((ratio / mouthBaseline - 1) / Self.fullSmileWidening)
    }

    public static func eyeAspectRatio(_ points: [CGPoint]) -> Double? {
        guard points.count >= 4, let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(), let minY = points.map(\.y).min(), let maxY = points.map(\.y).max(), maxX > minX else { return nil }
        return Double((maxY - minY) / (maxX - minX))
    }

    public static func mouthWidthRatio(lips: [CGPoint], leftPupil: CGPoint, rightPupil: CGPoint) -> Double? {
        guard let minX = lips.map(\.x).min(), let maxX = lips.map(\.x).max() else { return nil }
        let pupils = hypot(leftPupil.x - rightPupil.x, leftPupil.y - rightPupil.y)
        guard pupils > 0 else { return nil }
        return Double((maxX - minX) / pupils)
    }

    public static func contractYaw(visionRadians: Double) -> Double { visionRadians * 180 / .pi }
    public static func contractPitch(visionRadians: Double) -> Double { -visionRadians * 180 / .pi }
    public static func contractBox(_ rect: CGRect) -> FaceBox {
        FaceBox(x: Double(rect.minX), y: Double(1 - rect.maxY), w: Double(rect.width), h: Double(rect.height))
    }

    static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
    static func median(_ values: [Double]) -> Double? {
        guard values.count >= baselineFrames else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}

public final class VisionFaceSignalProvider: FaceSignalProvider {
    public let name = "vision"
    private var normalizer = VisionSignalNormalizer()
    private let lock = NSLock()
    public init() {}

    public func reset() { lock.lock(); normalizer = VisionSignalNormalizer(); lock.unlock() }

    public func sample(from pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, t: Int) -> FaceSample {
        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        let rotated = [.left, .right, .leftMirrored, .rightMirrored].contains(orientation)
        return sample(handler: VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:]), imageSize: rotated ? CGSize(width: size.height, height: size.width) : size, t: t)
    }

    public func sample(from image: CGImage, t: Int) -> FaceSample {
        sample(handler: VNImageRequestHandler(cgImage: image, options: [:]), imageSize: CGSize(width: image.width, height: image.height), t: t)
    }

    private func sample(handler: VNImageRequestHandler, imageSize: CGSize, t: Int) -> FaceSample {
        let rectangles = VNDetectFaceRectanglesRequest()
        rectangles.revision = VNDetectFaceRectanglesRequestRevision3
        do { try handler.perform([rectangles]) } catch { return FaceSample(t: t, faces: 0) }
        let faces = rectangles.results ?? []
        guard faces.count == 1, let face = faces.first else { return FaceSample(t: t, faces: faces.count) }
        let landmarks = VNDetectFaceLandmarksRequest()
        landmarks.revision = VNDetectFaceLandmarksRequestRevision3
        landmarks.inputFaceObservations = [face]
        try? handler.perform([landmarks])
        let marks = landmarks.results?.first?.landmarks
        var sample = FaceSample(t: t, faces: 1, box: VisionSignalNormalizer.contractBox(face.boundingBox))
        sample.yaw = face.yaw.map { VisionSignalNormalizer.contractYaw(visionRadians: $0.doubleValue) }
        sample.pitch = face.pitch.map { VisionSignalNormalizer.contractPitch(visionRadians: $0.doubleValue) }
        lock.lock(); defer { lock.unlock() }
        if let left = marks?.leftEye?.pointsInImage(imageSize: imageSize), let right = marks?.rightEye?.pointsInImage(imageSize: imageSize),
           let a = VisionSignalNormalizer.eyeAspectRatio(left), let b = VisionSignalNormalizer.eyeAspectRatio(right) {
            sample.eyeOpen = normalizer.eyeOpen(ratio: (a + b) / 2)
        }
        if let lips = marks?.outerLips?.pointsInImage(imageSize: imageSize), let lp = marks?.leftPupil?.pointsInImage(imageSize: imageSize).first,
           let rp = marks?.rightPupil?.pointsInImage(imageSize: imageSize).first,
           let ratio = VisionSignalNormalizer.mouthWidthRatio(lips: lips, leftPupil: lp, rightPupil: rp) {
            sample.smile = normalizer.smile(ratio: ratio)
        }
        return sample
    }
}
