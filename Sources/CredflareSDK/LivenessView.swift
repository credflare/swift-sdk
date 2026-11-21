#if canImport(UIKit)
import SwiftUI
import AVFoundation

@MainActor
final class LivenessModel: ObservableObject {
    enum Stage: Equatable { case intro, preparing, running, sending, failed(String) }
    @Published var stage: Stage = .intro
    @Published var hint = CredflareCopy.text(CredflareSpec.CopyKey.livenessPositionNoFace)
    @Published var current = 0
    @Published var total: Int
    @Published var recording = false
    let settings: FacialSettings
    let verifier: String
    private let client: VerificationSession
    private let makeProvider: () -> FaceSignalProvider
    private let onDone: () -> Void
    private var camera: CameraController?
    private var capture: LivenessCapture?
    private var pending: LivenessEvidence?
    private var keys: [String: UUID] = [:]
    private var finishing = false

    init(client: VerificationSession, settings: FacialSettings, verifier: String, makeProvider: @escaping () -> FaceSignalProvider, onDone: @escaping () -> Void) {
        self.client = client; self.settings = settings; self.verifier = verifier; self.makeProvider = makeProvider; self.onDone = onDone
        total = settings.gestureCount
    }

    var session: AVCaptureSession? { camera?.session }

    func start() async {
        if let pending { await submit(pending); return }
        stage = .preparing
        do { try await CameraController.authorize() } catch { return fail(CredflareSpec.CopyKey.errorsCameraDenied) }
        let camera = self.camera ?? CameraController()
        do { try camera.configure() } catch CameraError.frontRequired { return fail(CredflareSpec.CopyKey.errorsFrontCameraRequired) } catch { return fail(CredflareSpec.CopyKey.errorsCameraUnavailable) }
        self.camera = camera
        let challenge: LivenessChallenge
        do { challenge = try await client.createLivenessChallenge() } catch { return fail(CredflareSpec.CopyKey.errorsChallengeFailed) }
        let capture: LivenessCapture
        do { capture = try LivenessCapture(challenge: challenge, provider: makeProvider()) } catch { return fail(CredflareSpec.CopyKey.errorsChallengeFailed) }
        self.capture = capture; keys = [:]; finishing = false
        total = challenge.gestures.count; current = 0
        hint = CredflareCopy.text(CredflareSpec.CopyKey.livenessPositionNoFace)
        camera.onFrame = { [weak self] buffer, seconds in
            let update = capture.process(buffer, seconds: seconds)
            let expired = capture.isExpired
            Task { @MainActor in self?.apply(update, expired: expired, capture: capture) }
        }
        camera.start()
        if challenge.recordVideo { camera.startRecording(maxSeconds: min(challenge.maxVideoSeconds, CredflareSpec.Liveness.videoMaxSeconds)); recording = true }
        stage = .running
    }

    private func apply(_ update: LivenessUpdate, expired: Bool, capture: LivenessCapture) {
        guard capture === self.capture, stage == .running, !finishing else { return }
        if expired { return stop(failing: CredflareSpec.CopyKey.livenessExpired) }
        switch update.phase {
        case .positioning(let status): hint = CredflareCopy.text(status.copyKey)
        case .gesture(let index, let name, let tracked):
            current = index + 1
            hint = CredflareCopy.text(tracked ? LivenessSequence.promptKey(for: name) : CredflareSpec.CopyKey.livenessFaceLost)
        case .completed: current = total; hint = CredflareCopy.text(CredflareSpec.CopyKey.livenessSuccess)
        case .timedOut: return stop(failing: CredflareSpec.CopyKey.livenessTimeout)
        }
        if update.selfieCaptured { Task { await finish(capture) } }
    }

    private func stop(failing key: String) {
        camera?.onFrame = nil
        camera?.stop()
        recording = false
        capture = nil
        fail(key)
    }

    private func finish(_ capture: LivenessCapture) async {
        finishing = true
        camera?.onFrame = nil
        if let photo = await camera?.capturePhoto() { capture.replaceSelfie(photo) }
        let video = capture.challenge.recordVideo ? await camera?.finishRecording() : nil
        recording = false
        camera?.stop()
        guard let evidence = capture.evidence(video: video), !capture.challenge.recordVideo || video != nil else { return fail(CredflareSpec.CopyKey.errorsSelfieFailed) }
        await submit(evidence)
    }

    private func submit(_ evidence: LivenessEvidence) async {
        stage = .sending
        do {
            var keys = self.keys
            defer { self.keys = keys }
            _ = try await LivenessSubmitter.submit(evidence, client: client, keys: &keys)
            pending = nil
            if let video = evidence.video { try? FileManager.default.removeItem(at: video) }
            onDone()
        } catch let error as CredflareError {
            if LivenessRejection.needsNewChallenge(error) {
                pending = nil
                if let video = evidence.video { try? FileManager.default.removeItem(at: video) }
                stage = .failed(LivenessRejection.message(for: error))
            }
            else { pending = evidence; stage = .failed(CredflareCopy.text(CredflareSpec.CopyKey.errorsSendSelfieFailed)) }
        } catch {
            pending = evidence; stage = .failed(CredflareCopy.text(CredflareSpec.CopyKey.errorsSendSelfieFailed))
        }
    }

    private func fail(_ key: String) { stage = .failed(CredflareCopy.text(key, ["verifier": verifier])) }

    func tearDown() { camera?.onFrame = nil; camera?.stop() }
}

struct LivenessView: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var model: LivenessModel
    var body: some View {
        let theme = CredflareTheme(scheme)
        VStack(spacing: CredflareTheme.gap) {
            switch model.stage {
            case .intro:
                SpecIconView(CredflareSpec.Icons.selfie, color: theme.primary, size: CGFloat(CredflareSpec.Tokens.sizeIllustration))
                TitleText(CredflareCopy.text(CredflareSpec.CopyKey.livenessTitle))
                ThemedText(CredflareCopy.text(CredflareSpec.CopyKey.livenessBody, ["total": String(model.total)]), tone: \.muted)
                ThemedText(CredflareCopy.text(CredflareSpec.CopyKey.selfieGuidance), tone: \.muted)
                if model.settings.recordVideo {
                    HStack(spacing: CGFloat(CredflareSpec.Tokens.spacingSm)) {
                        SpecIconView(CredflareSpec.Icons.video, color: theme.warningInk, size: 20)
                        Text(CredflareCopy.text(CredflareSpec.CopyKey.videoConsent, ["verifier": model.verifier])).specText(CredflareSpec.Tokens.typeSmall).foregroundStyle(theme.warningInk)
                    }
                    .padding(CGFloat(CredflareSpec.Tokens.spacingMd))
                    .background(theme.warningSoft)
                    .clipShape(RoundedRectangle(cornerRadius: CGFloat(CredflareSpec.Tokens.radiusMd)))
                }
                PrimaryButton(CredflareCopy.text(CredflareSpec.CopyKey.livenessStart)) { Task { await model.start() } }
                ThemedText(CredflareCopy.text(CredflareSpec.CopyKey.selfiePrivacy, ["verifier": model.verifier]), style: CredflareSpec.Tokens.typeSmall, tone: \.muted)
            case .preparing:
                LoadingBlock(label: CredflareCopy.text(CredflareSpec.CopyKey.selfieStartingCamera))
            case .running:
                ThemedText(CredflareCopy.text(CredflareSpec.CopyKey.livenessProgress, ["current": String(max(model.current, 1)), "total": String(model.total)]), style: CredflareSpec.Tokens.typeEyebrow, tone: \.muted)
                ZStack(alignment: .top) {
                    Group {
                        if let session = model.session {
                            CameraPreview(session: session)
                        } else {
                            theme.soft.overlay(SpecIconView(CredflareSpec.Icons.camera, color: theme.muted, size: CGFloat(CredflareSpec.Tokens.sizeIllustration)))
                        }
                    }
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: CGFloat(CredflareSpec.Tokens.radiusXl)))
                    .overlay(Ellipse().stroke(Color(argb: CredflareSpec.Tokens.light.surface).opacity(0.9), lineWidth: 3).padding(.horizontal, 48).padding(.vertical, 40))
                    .accessibilityLabel(CredflareCopy.text(CredflareSpec.CopyKey.selfiePreviewLabel))
                    if model.recording {
                        HStack(spacing: CGFloat(CredflareSpec.Tokens.spacingXs)) {
                            Circle().fill(theme.error).frame(width: 8, height: 8)
                            Text(CredflareCopy.text(CredflareSpec.CopyKey.videoRecording)).specText(CredflareSpec.Tokens.typeChip).fixedSize()
                        }
                        .foregroundStyle(theme.ink)
                        .padding(.horizontal, CGFloat(CredflareSpec.Tokens.spacingSm)).padding(.vertical, CGFloat(CredflareSpec.Tokens.spacingXs))
                        .background(theme.surface.opacity(0.85)).clipShape(Capsule()).padding(CGFloat(CredflareSpec.Tokens.spacingSm))
                    }
                }
                Text(model.hint).specText(CredflareSpec.Tokens.typeSubtitle).foregroundStyle(theme.ink).accessibilityAddTraits(.updatesFrequently)
            case .sending:
                LoadingBlock(label: CredflareCopy.text(CredflareSpec.CopyKey.livenessSending))
            case .failed(let message):
                SpecIconView(CredflareSpec.Icons.selfie, color: theme.primary, size: CGFloat(CredflareSpec.Tokens.sizeIllustration))
                TitleText(CredflareCopy.text(CredflareSpec.CopyKey.livenessTitle))
                ErrorBox(message: message)
                PrimaryButton(CredflareCopy.text(CredflareSpec.CopyKey.livenessRetry)) { Task { await model.start() } }
            }
        }
        .onDisappear { model.tearDown() }
    }
}
#endif
