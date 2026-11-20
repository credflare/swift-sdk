#if canImport(UIKit)
import AVFoundation
import UIKit
import SwiftUI

enum CameraError: Error { case denied, unavailable, frontRequired }

final class CameraController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let cameraQueue = DispatchQueue(label: "net.credflare.sdk.camera")
    private let analysisQueue = DispatchQueue(label: "net.credflare.sdk.analysis")
    private var analysing = false
    private let analysisLock = NSLock()
    private var lastAnalysed: Double = -1
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var recordingURL: URL?
    private var recordingStart: Double?
    private var recordingLimit: Double = 0
    private var recording = false
    private var configured = false
    var analysisInterval = Double(CredflareSpec.Liveness.sampleIntervalMs) / 1000
    var onFrame: ((CVPixelBuffer, Double) -> Void)?

    static func authorize() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return
        case .notDetermined: if await AVCaptureDevice.requestAccess(for: .video) { return }; throw CameraError.denied
        default: throw CameraError.denied
        }
    }

    func configure() throws {
        guard !configured else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw AVCaptureDevice.default(for: .video) == nil ? CameraError.unavailable : CameraError.frontRequired
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.unavailable }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: cameraQueue)
        guard session.canAddOutput(output) else { throw CameraError.unavailable }
        session.addOutput(output)
        if let connection = output.connection(with: .video) {
            if #available(iOS 17.0, *) {
                if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            } else if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
        configured = true
    }

    func start() { cameraQueue.async { [session] in if !session.isRunning { session.startRunning() } } }

    func stop() {
        cameraQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            self.writer?.cancelWriting(); self.writer = nil; self.writerInput = nil; self.recording = false
        }
    }

    func startRecording(maxSeconds: Int) {
        cameraQueue.async { [weak self] in
            guard let self else { return }
            self.writer?.cancelWriting(); self.writer = nil; self.writerInput = nil
            self.recordingURL = FileManager.default.temporaryDirectory.appendingPathComponent("credflare-\(UUID().uuidString).mp4")
            self.recordingLimit = Double(maxSeconds) - 0.1
            self.recordingStart = nil
            self.recording = true
        }
    }

    func finishRecording() async -> URL? {
        await withCheckedContinuation { continuation in
            cameraQueue.async { [weak self] in
                guard let self, let writer = self.writer, writer.status == .writing else { continuation.resume(returning: nil); return }
                self.recording = false
                self.writerInput?.markAsFinished()
                let url = self.recordingURL
                writer.finishWriting { continuation.resume(returning: writer.status == .completed ? url : nil) }
                self.writer = nil; self.writerInput = nil
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let seconds = CMTimeGetSeconds(time)
        if recording { append(sampleBuffer, buffer: buffer, time: time, seconds: seconds) }
        guard seconds - lastAnalysed >= analysisInterval * 0.95 else { return }
        analysisLock.lock()
        let busy = analysing
        if !busy { analysing = true }
        analysisLock.unlock()
        guard !busy else { return }
        lastAnalysed = seconds
        analysisQueue.async { [weak self] in
            guard let self else { return }
            self.onFrame?(buffer, seconds)
            self.analysisLock.lock(); self.analysing = false; self.analysisLock.unlock()
        }
    }

    private func append(_ sampleBuffer: CMSampleBuffer, buffer: CVPixelBuffer, time: CMTime, seconds: Double) {
        if writer == nil, let url = recordingURL {
            guard let next = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { recording = false; return }
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: CVPixelBufferGetWidth(buffer),
                AVVideoHeightKey: CVPixelBufferGetHeight(buffer),
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_000_000],
            ])
            input.expectsMediaDataInRealTime = true
            guard next.canAdd(input) else { recording = false; return }
            next.add(input)
            guard next.startWriting() else { recording = false; return }
            next.startSession(atSourceTime: time)
            writer = next; writerInput = input; recordingStart = seconds
        }
        guard let input = writerInput, let start = recordingStart else { return }
        if seconds - start >= recordingLimit { recording = false; return }
        if input.isReadyForMoreMediaData { input.append(sampleBuffer) }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ view: PreviewView, context: Context) {}
}
#endif
