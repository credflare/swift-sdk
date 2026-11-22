#if canImport(UIKit)
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AVFoundation
import ImageIO

private typealias Key = CredflareSpec.CopyKey

@MainActor
private final class VerificationModel: ObservableObject {
    struct Capture {
        let data: Data; let name: String; let source: CaptureSource; let key = UUID()
        var fileID: Int?
    }
    enum Screen: Equatable { case intro, documents, capture, questions, contact, liveness, location, receipt(hostSteps: Bool) }
    @Published var info: SessionInfo?
    @Published var document: DocumentRequirement?
    @Published var index = 0
    @Published var captures: [String: Capture] = [:]
    @Published var working = false
    @Published var error: String?
    @Published var pendingRefresh = false
    @Published var closed = false
    @Published var editing = false
    @Published var received: [String] = []
    @Published var liveness: LivenessModel?
    @Published var location: LocationModel?
    @Published var questions: QuestionsModel?
    @Published var contact: ContactCodeModel?
    fileprivate var client: VerificationSession?
    private var submissionKey = UUID()
    let makeFaceProvider: () -> FaceSignalProvider
    let makeLocationSource: () -> LocationSource
    var onLeave: () -> Void = {}

    init(makeFaceProvider: @escaping () -> FaceSignalProvider, makeLocationSource: @escaping () -> LocationSource) {
        self.makeFaceProvider = makeFaceProvider; self.makeLocationSource = makeLocationSource
    }

    var verifier: String { CredflareCopy.verifier(info?.requester?.name) }
    var dirty: Bool { !captures.isEmpty }
    var steps: [CaptureStep] { (try? document?.captureSteps()) ?? [] }
    var reviewing: Bool { document != nil && index == steps.count }
    var step: CaptureStep? { index < steps.count ? steps[index] : nil }
    var documents: [DocumentRequirement] { info?.profile?.documentRequirements ?? [] }
    var screen: Screen {
        guard let info, info.profile != nil else { return .intro }
        if document != nil { return .capture }
        if closed { return .receipt(hostSteps: false) }
        switch info.nextStep {
        case .documents: return .documents
        case .questions: return .questions
        case .check(let next): return next.facial != nil ? .liveness : next.location != nil ? .location : .contact
        case .receipt(let hostSteps): return .receipt(hostSteps: hostSteps)
        }
    }
    var complete: Bool { if case .receipt(false) = screen { return !pendingRefresh }; return false }

    func text(_ key: String, _ values: [String: String] = [:]) -> String { CredflareCopy.text(key, values.merging(["verifier": verifier]) { a, _ in a }) }

    func start(_ provider: @escaping () async throws -> SessionDescriptor) async {
        guard !working else { return }
        working = true; error = nil
        defer { working = false }
        do { client = VerificationSession(try await provider()); info = try await client!.get(); prepareStep() }
        catch { show(error, fallback: Key.errorsStartFailed) }
    }

    func show(_ cause: Error, fallback: String = Key.errorsGeneric) {
        if let error = cause as? CredflareError {
            switch error {
            case .api(401, _, _, _): self.error = text(Key.errorsSessionExpired)
            case .api(422, let message, _, _): self.error = message
            case .validation(let message): self.error = message
            case .network: self.error = text(Key.errorsNetwork)
            default: self.error = text(fallback)
            }
        } else { self.error = text(fallback) }
    }

    fileprivate func prepareStep() {
        guard document == nil, let client, let step = info?.nextStep else { clearSteps(); return }
        switch step {
        case .questions(let questionnaire):
            guard questions == nil else { return }
            clearSteps()
            questions = QuestionsModel(client: client, questionnaire: questionnaire, verifier: verifier) { [weak self] in
                Task { @MainActor in await self?.finished(receipt: Key.receiptAnswers) }
            }
        case .check(let next):
            if let facial = next.facial {
                guard liveness == nil else { return }
                clearSteps()
                liveness = LivenessModel(client: client, settings: facial, verifier: verifier, makeProvider: makeFaceProvider) { [weak self] in
                    Task { @MainActor in await self?.finished(receipt: Key.receiptSelfie) }
                }
            } else if let settings = next.location {
                guard location == nil else { return }
                clearSteps()
                location = LocationModel(client: client, settings: settings, verifier: verifier, makeSource: makeLocationSource) { [weak self] in
                    Task { @MainActor in await self?.finished(receipt: Key.receiptLocation) }
                }
            } else if let channel = next.contact {
                guard contact?.channel != channel else { return }
                clearSteps()
                contact = ContactCodeModel(client: client, channel: channel, verifier: verifier, onDone: { [weak self] in
                    Task { @MainActor in await self?.finished(receipt: channel == .email ? Key.receiptEmail : Key.receiptPhone) }
                }, onLeave: { [weak self] in self?.onLeave() })
            }
        case .documents, .receipt: clearSteps()
        }
        applyHelp()
    }

    private func applyHelp() {
        let help = info?.requester?.help ?? HelpContact()
        questions?.help = help; contact?.help = help; liveness?.help = help; location?.help = help
    }

    private func clearSteps() { liveness = nil; location = nil; questions = nil; contact = nil }

    private func finished(receipt: String) async {
        received.append(text(receipt))
        clearSteps()
        pendingRefresh = true
        await refresh()
    }

    func open(_ requirement: DocumentRequirement) {
        document = requirement; captures = [:]; index = 0; editing = false; submissionKey = UUID(); error = nil
    }
    func clearDocument() { document = nil; captures = [:]; index = 0; error = nil; prepareStep() }

    func select(data: Data, name: String, source: CaptureSource) throws {
        guard let info, step != nil, info.uploadLimits.maxFileSizeBytes > 0 else { throw CredflareError.validation(text(Key.errorsGeneric)) }
        let ext = (name as NSString).pathExtension.lowercased()
        let normalized = ext == "jpeg" ? "jpg" : ext
        guard info.uploadLimits.allowedFileTypes.contains(normalized) else { throw CredflareError.validation(text(Key.errorsFileType, ["types": fileTypes])) }
        guard !data.isEmpty else { throw CredflareError.validation(text(Key.errorsFileEmpty)) }
        guard data.count <= info.uploadLimits.maxFileSizeBytes else { throw CredflareError.validation(text(Key.errorsFileTooLarge, ["size": fileSize])) }
        captures[step!.id] = Capture(data: data, name: name, source: source); submissionKey = UUID(); error = nil
    }
    var fileTypes: String { (info?.uploadLimits.allowedFileTypes ?? []).map { $0.uppercased() }.joined(separator: ", ") }
    var fileSize: String { "\((info?.uploadLimits.maxFileSizeBytes ?? 0) / 1_048_576) MB" }

    func importFile(_ url: URL) async {
        guard !working else { return }; working = true; error = nil
        defer { working = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            guard let limit = info?.uploadLimits.maxFileSizeBytes, limit > 0 else { throw CredflareError.validation(text(Key.errorsAddFileFailed)) }
            let tooLarge = CredflareError.validation(text(Key.errorsFileTooLarge, ["size": fileSize]))
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > limit { throw tooLarge }
            let data = try await Task.detached {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                var data = Data()
                while let chunk = try handle.read(upToCount: 65536), !chunk.isEmpty {
                    guard chunk.count <= limit - data.count else { throw tooLarge }
                    data.append(chunk)
                }
                return data
            }.value
            try select(data: data, name: url.lastPathComponent, source: .upload)
        } catch { show(error, fallback: Key.errorsFileUnreadable) }
    }

    func photo(_ image: UIImage) {
        do {
            let png = !(info?.uploadLimits.allowedFileTypes.contains("jpg") ?? false)
            guard let data = png ? image.pngData() : image.jpegData(compressionQuality: 0.95) else { throw CredflareError.validation(text(Key.errorsCameraNoPhoto)) }
            try select(data: data, name: png ? "camera.png" : "camera.jpg", source: .camera)
        } catch { show(error, fallback: Key.errorsCameraNoPhoto) }
    }

    func next() { index = editing ? steps.count : index + 1; editing = false; error = nil }

    func refresh() async {
        guard !working, let client else { return }; working = true; error = nil
        defer { working = false }
        switch await client.refresh() {
        case .next(let next, _): info = next; pendingRefresh = false; prepareStep()
        case .closed: closed = true; pendingRefresh = false; clearSteps()
        case .failed(let message): error = message
        }
    }

    func send() async {
        guard !working, let client, let document, steps.allSatisfy({ captures[$0.id] != nil }) else { return }
        working = true; error = nil
        do {
            var evidence: [Evidence] = []
            for step in steps {
                var capture = captures[step.id]!
                if capture.fileID == nil {
                    capture.fileID = try await client.upload(capture.data, filename: capture.name, source: capture.source, side: step.side, documentTypeID: document.id, key: capture.key).id
                    captures[step.id] = capture
                }
                evidence.append(Evidence(fileID: capture.fileID!, source: capture.source, side: step.side))
            }
            _ = try await client.submit(documentTypeID: document.id, evidence: evidence, key: submissionKey)
            received.append(text(Key.receiptDocument, ["document": document.documentType.name]))
            self.document = nil; captures = [:]; index = 0; pendingRefresh = true
        } catch { show(error, fallback: Key.errorsSendDocumentFailed); working = false; return }
        working = false
        await refresh()
    }
}

@MainActor
public struct CredflareVerificationView: View {
    private let provider: () async throws -> SessionDescriptor
    private let autoStart: Bool
    private let onResult: (VerificationResult) -> Void
    @Environment(\.colorScheme) private var scheme
    @StateObject fileprivate var model: VerificationModel
    @State private var autoStarted = false
    @State private var importing = false
    @State private var camera = false
    @State private var confirmClose = false
    @State private var confirmDiscard = false

    public init(sessionProvider: @escaping () async throws -> SessionDescriptor, autoStart: Bool = false,
                faceSignalProvider: @escaping () -> FaceSignalProvider = { VisionFaceSignalProvider() },
                locationSource: @escaping () -> LocationSource = { DeviceLocationSource() },
                onResult: @escaping (VerificationResult) -> Void) {
        self.provider = sessionProvider; self.autoStart = autoStart; self.onResult = onResult
        _model = StateObject(wrappedValue: VerificationModel(makeFaceProvider: faceSignalProvider, makeLocationSource: locationSource))
    }

    private var theme: CredflareTheme { CredflareTheme(scheme) }
    private func t(_ key: String, _ values: [String: String] = [:]) -> String { model.text(key, values) }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: CredflareTheme.gap) {
                    content
                    if let error = model.error { ErrorBox(message: error) }
                    HStack(spacing: CGFloat(CredflareSpec.Tokens.spacingXs + 2)) {
                        BrandMark().frame(width: 18, height: 18).accessibilityHidden(true)
                        Text(t(Key.commonSecuredBy)).font(.system(size: CGFloat(CredflareSpec.Tokens.typeSmall.size))).foregroundStyle(theme.muted)
                    }.frame(maxWidth: .infinity).padding(.top, CGFloat(CredflareSpec.Tokens.spacingXl))
                }
                .padding(CredflareTheme.gutter)
                .frame(maxWidth: CGFloat(CredflareSpec.Tokens.sizeMaxContentWidth))
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(theme.ink)
        .tint(theme.primary)
        .background(theme.surface.ignoresSafeArea())
        .task {
            model.onLeave = { onResult(.cancelled) }
            if autoStart && !autoStarted { autoStarted = true; await model.start(provider) }
        }
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled()
        .confirmationDialog(t(Key.exitTitle), isPresented: $confirmClose, titleVisibility: .visible) {
            Button(t(Key.exitLeave), role: .destructive) { onResult(.cancelled) }
            Button(t(Key.exitStay), role: .cancel) {}
        } message: { Text(t(Key.exitBody)) }
        .confirmationDialog(t(Key.exitDiscardTitle), isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(t(Key.exitDiscardLeave), role: .destructive) { model.clearDocument() }
            Button(t(Key.exitDiscardStay), role: .cancel) {}
        } message: { Text(t(Key.exitDiscardBody)) }
        .fileImporter(isPresented: $importing, allowedContentTypes: allowedTypes) { result in
            switch result {
            case .success(let url): Task { await model.importFile(url) }
            case .failure(let error): if (error as? CocoaError)?.code != .userCancelled { model.show(error, fallback: Key.errorsFileUnreadable) }
            }
        }
        .sheet(isPresented: $camera) { CameraPicker { image in camera = false; if let image { model.photo(image) } }.ignoresSafeArea() }
    }

    private var header: some View {
        HStack(spacing: CGFloat(CredflareSpec.Tokens.spacingSm)) {
            if let name = model.info?.requester?.name { Text(name).specText(CredflareSpec.Tokens.typeLabel).lineLimit(1).fixedSize(horizontal: false, vertical: true) }
            if model.info?.environment == "sandbox" {
                Text(t(Key.commonTestMode)).specText(CredflareSpec.Tokens.typeChip).fixedSize()
                    .foregroundStyle(theme.warningInk).padding(.horizontal, 6).padding(.vertical, 3)
                    .background(theme.warningSoft).clipShape(RoundedRectangle(cornerRadius: CGFloat(CredflareSpec.Tokens.radiusSm)))
            }
            Spacer(minLength: 0)
            Button(t(Key.commonClose)) { if model.complete { onResult(.submitted) } else { confirmClose = true } }
                .font(.system(size: CGFloat(CredflareSpec.Tokens.typeButton.size), weight: .medium)).foregroundStyle(theme.primary).disabled(model.working)
        }
        .frame(minHeight: CGFloat(CredflareSpec.Tokens.sizeHeaderHeight))
        .padding(.horizontal, CredflareTheme.gutter)
    }

    @ViewBuilder private var content: some View {
        if model.working {
            LoadingBlock(label: t(model.info == nil ? Key.commonLoading : model.pendingRefresh ? Key.introChecking : Key.sendingSending))
        } else if model.pendingRefresh {
            SpecIconView(CredflareSpec.Icons.received, color: theme.success, size: CGFloat(CredflareSpec.Tokens.sizeIllustration))
            TitleText(t(Key.sendingSentTitle))
            ThemedText(t(Key.sendingSentBody), tone: \.muted)
            PrimaryButton(t(model.error == nil ? Key.sendingCheckAgain : Key.commonTryAgain)) { Task { await model.refresh() } }
        } else {
            switch model.screen {
            case .intro:
                SpecIconView(CredflareSpec.Icons.idCard, color: theme.primary, size: CGFloat(CredflareSpec.Tokens.sizeIllustration))
                TitleText(t(Key.introTitle))
                ThemedText(t(Key.introBody), tone: \.muted)
                PrimaryButton(t(model.error == nil ? Key.introStart : Key.commonTryAgain)) { Task { await model.start(provider) } }
            case .documents: documentsList
            case .capture: captureContent
            case .questions: if let questions = model.questions { QuestionsView(model: questions) }
            case .contact: if let contact = model.contact { ContactCodeView(model: contact) }
            case .liveness: if let liveness = model.liveness { LivenessView(model: liveness) }
            case .location: if let location = model.location { LocationView(model: location) }
            case .receipt(let hostSteps): receipt(hostSteps: hostSteps)
            }
        }
    }

    @ViewBuilder private var documentsList: some View {
        TitleText(t(Key.documentsTitle))
        ThemedText(t(Key.documentsRequestedBy), tone: \.muted)
        if let message = model.info?.customMessage, !message.isEmpty { ThemedText(message) }
        ForEach(model.documents) { requirement in
            VStack(spacing: CGFloat(CredflareSpec.Tokens.spacingSm)) {
                ThemedText(sectionLabel(requirement), style: CredflareSpec.Tokens.typeEyebrow, tone: \.muted)
                Button { model.open(requirement) } label: { documentCard(requirement) }
                    .buttonStyle(.plain).disabled(!requirement.isSupported)
            }
        }
        if let key = model.info?.profile?.nextStepsCopyKey { ThemedText(t(key), style: CredflareSpec.Tokens.typeSmall, tone: \.muted) }
    }

    private func sectionLabel(_ requirement: DocumentRequirement) -> String {
        guard requirement.rule == "any_of" else { return t(Key.documentsSectionRequired) }
        let count = requirement.remainingRequired ?? requirement.minRequired ?? 1
        return count == 1 ? t(Key.documentsSectionOneOf) : t(Key.documentsSectionCountOf, ["count": String(count)])
    }

    private func methodLabel(_ requirement: DocumentRequirement) -> String {
        switch requirement.policy {
        case "snapshot": return t(Key.documentsMethodCamera)
        case "upload": return t(Key.documentsMethodUpload)
        case "snapshot_or_upload": return t(Key.documentsMethodEither)
        case "snapshot_and_upload": return t(Key.documentsMethodBoth)
        default: return t(Key.documentsUnavailable)
        }
    }

    private func documentCard(_ requirement: DocumentRequirement) -> some View {
        VStack(spacing: CGFloat(CredflareSpec.Tokens.spacingXs)) {
            SpecIconView(requirement.documentType.twoSided ? CredflareSpec.Icons.idCard : CredflareSpec.Icons.document, color: theme.primary)
            Text(requirement.documentType.name).specText(CredflareSpec.Tokens.typeSubtitle).foregroundStyle(theme.ink)
            Text(methodLabel(requirement)).specText(CredflareSpec.Tokens.typeSmall).foregroundStyle(theme.muted)
        }
        .padding(CGFloat(CredflareSpec.Tokens.spacingLg))
        .frame(maxWidth: .infinity, minHeight: CGFloat(CredflareSpec.Tokens.sizeOptionHeight))
        .overlay(alignment: .trailing) { SpecIconView(CredflareSpec.Icons.chevronRight, color: theme.muted, size: 20).padding(.trailing, CGFloat(CredflareSpec.Tokens.spacingLg)) }
        .background(theme.soft)
        .clipShape(RoundedRectangle(cornerRadius: CGFloat(CredflareSpec.Tokens.radiusLg)))
        .overlay(RoundedRectangle(cornerRadius: CGFloat(CredflareSpec.Tokens.radiusLg)).stroke(theme.border))
        .contentShape(Rectangle())
    }

    private func sideLabel(_ side: DocumentSide) -> String { t(side == .front ? Key.captureSideFront : Key.captureSideBack) }

    @ViewBuilder private var captureContent: some View {
        Button { if model.dirty { confirmDiscard = true } else { model.clearDocument() } } label: {
            HStack(spacing: CGFloat(CredflareSpec.Tokens.spacingXs)) {
                SpecIconView(CredflareSpec.Icons.chevronLeft, color: theme.primary, size: 20)
                Text(t(Key.documentsBack)).font(.system(size: CGFloat(CredflareSpec.Tokens.typeButton.size), weight: .medium)).foregroundStyle(theme.primary)
            }.frame(minHeight: CGFloat(CredflareSpec.Tokens.sizeLinkHeight))
        }.buttonStyle(.plain).frame(maxWidth: .infinity)
        if let document = model.document { ThemedText(document.documentType.name, style: CredflareSpec.Tokens.typeEyebrow, tone: \.muted) }
        if model.reviewing {
            TitleText(t(Key.reviewTitle))
            ThemedText(t(Key.reviewBody), tone: \.muted)
            ForEach(model.steps) { step in
                if let capture = model.captures[step.id] {
                    VStack(spacing: CGFloat(CredflareSpec.Tokens.spacingSm)) {
                        ThemedText(t(Key.reviewItem, ["side": sideLabel(step.side), "source": t(capture.source == .camera ? Key.captureSourceCamera : Key.captureSourceUpload)]), style: CredflareSpec.Tokens.typeLabel)
                        preview(capture, side: step.side)
                        Button(t(Key.reviewChange)) { model.index = model.steps.firstIndex(where: { $0.id == step.id })!; model.editing = true }
                            .foregroundStyle(theme.primary)
                    }
                }
            }
            PrimaryButton(t(Key.reviewSend)) { Task { await model.send() } }
        } else if let step = model.step, let document = model.document {
            ThemedText(t(Key.commonStepProgress, ["current": String(model.index + 1), "total": String(model.steps.count + 1)]), style: CredflareSpec.Tokens.typeEyebrow, tone: \.muted)
            ProgressView(value: Double(model.index + 1), total: Double(model.steps.count + 1)).tint(theme.primary)
            TitleText(sideLabel(step.side))
            if let capture = model.captures[step.id] {
                preview(capture, side: step.side)
                if capture.source == .camera { ThemedText(t(Key.captureCheckPhoto), tone: \.muted) }
                ThemedText(capture.name, style: CredflareSpec.Tokens.typeSmall, tone: \.muted).lineLimit(2)
                SecondaryButton(t(capture.source == .camera ? Key.captureRetakePhoto : Key.captureChangeFile)) { model.captures.removeValue(forKey: step.id) }
                PrimaryButton(t(Key.commonContinue)) { model.next() }
            } else {
                ThemedText(instruction(step, document: document), tone: \.muted)
                SpecIconView(step.input == .upload ? CredflareSpec.Icons.upload : CredflareSpec.Icons.camera, color: theme.muted, size: CGFloat(CredflareSpec.Tokens.sizeIllustration))
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .background(theme.soft).clipShape(RoundedRectangle(cornerRadius: CGFloat(CredflareSpec.Tokens.radiusLg)))
                if step.input != .upload { PrimaryButton(t(Key.captureTakePhoto)) { openCamera() } }
                if step.input == .upload { PrimaryButton(t(Key.captureChooseFile)) { importing = true } }
                if step.input == .cameraOrUpload { SecondaryButton(t(Key.captureUseFileInstead)) { importing = true } }
                if step.input != .camera { ThemedText(t(Key.captureFileLimits, ["types": model.fileTypes, "size": model.fileSize]), style: CredflareSpec.Tokens.typeSmall, tone: \.muted) }
            }
        }
    }

    private func instruction(_ step: CaptureStep, document: DocumentRequirement) -> String {
        let side = sideLabel(step.side).lowercased()
        switch step.input {
        case .camera: return t(Key.captureInstructionCamera, ["document": document.documentType.name])
        case .cameraOrUpload: return t(Key.captureInstructionEither, ["side": side])
        case .upload:
            let pdf = model.info?.uploadLimits.allowedFileTypes.contains("pdf") ?? false
            return t(pdf ? Key.captureInstructionUploadPdf : Key.captureInstructionUpload, ["side": side])
        }
    }

    @ViewBuilder private func receipt(hostSteps: Bool) -> some View {
        SpecIconView(CredflareSpec.Icons.receivedIllustration, color: theme.success, size: CGFloat(CredflareSpec.Tokens.sizeIllustration))
        TitleText(t(Key.receiptTitle))
        ThemedText(t(Key.receiptBody), tone: \.muted)
        if !model.received.isEmpty {
            VStack(spacing: CGFloat(CredflareSpec.Tokens.spacingSm)) {
                ForEach(Array(model.received.enumerated()), id: \.offset) { _, line in
                    HStack(spacing: CGFloat(CredflareSpec.Tokens.spacingSm)) {
                        SpecIconView(CredflareSpec.Icons.received, color: theme.success, size: 20)
                        Text(line).font(.system(size: CGFloat(CredflareSpec.Tokens.typeBody.size))).foregroundStyle(theme.ink).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity)
                }
            }
            .padding(CGFloat(CredflareSpec.Tokens.spacingLg)).frame(maxWidth: .infinity)
            .background(theme.soft).clipShape(RoundedRectangle(cornerRadius: CGFloat(CredflareSpec.Tokens.radiusLg)))
        }
        if hostSteps {
            ThemedText(t(Key.receiptHostSteps), tone: \.muted)
            PrimaryButton(t(Key.commonReturnToApp)) { onResult(.hostActionRequired) }
        } else {
            PrimaryButton(t(Key.receiptDone)) { onResult(.submitted) }
        }
    }

    private func thumbnail(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1600, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    @ViewBuilder private func preview(_ capture: VerificationModel.Capture, side: DocumentSide) -> some View {
        if let image = thumbnail(capture.data) {
            Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: CGFloat(CredflareSpec.Tokens.radiusMd)))
                .accessibilityLabel(t(Key.capturePreviewLabel, ["side": sideLabel(side).lowercased()]))
        } else {
            VStack(spacing: CGFloat(CredflareSpec.Tokens.spacingXs)) {
                SpecIconView(CredflareSpec.Icons.document, color: theme.primary)
                Text(t(capture.name.lowercased().hasSuffix(".pdf") ? Key.capturePreviewPdf : Key.capturePreviewDocument)).specText(CredflareSpec.Tokens.typeLabel)
            }
            .frame(maxWidth: .infinity, minHeight: 100).background(theme.soft)
            .clipShape(RoundedRectangle(cornerRadius: CGFloat(CredflareSpec.Tokens.radiusLg)))
        }
    }

    private var allowedTypes: [UTType] { (model.info?.uploadLimits.allowedFileTypes ?? []).compactMap { UTType(filenameExtension: $0) } }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { model.error = t(Key.errorsCameraUnavailable); return }
        let permission = AVCaptureDevice.authorizationStatus(for: .video)
        guard permission != .denied && permission != .restricted else { model.error = t(Key.errorsCameraDenied); return }
        camera = true
    }
}

private struct BrandMark: UIViewRepresentable {
    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        if let path = Bundle.module.url(forResource: "credflare-mark", withExtension: "png")?.path, let image = UIImage(contentsOfFile: path) {
            view.image = UIGraphicsImageRenderer(size: CGSize(width: 18, height: 18)).image { _ in image.draw(in: CGRect(x: 2, y: 2, width: 14, height: 14)) }.withRenderingMode(.alwaysOriginal)
        }
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .white
        view.layer.cornerRadius = 3
        view.clipsToBounds = true
        return view
    }
    func updateUIView(_ view: UIImageView, context: Context) {}
}

private struct CameraPicker: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera; picker.mediaTypes = [UTType.image.identifier]; picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (UIImage?) -> Void
        init(_ completion: @escaping (UIImage?) -> Void) { self.completion = completion }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { completion(info[.originalImage] as? UIImage) }
    }
}
#endif

#if DEBUG && canImport(UIKit)
extension CredflareVerificationView {
    public static let previewScreens = [
        "intro", "documents", "capture", "capture_selected", "review",
        "liveness_intro", "liveness_starting", "liveness_positioning", "liveness_blink", "liveness_smile", "liveness_turn_left", "liveness_turn_right", "liveness_nod", "liveness_face_lost", "liveness_timeout", "liveness_sending",
        "location_consent", "location_waiting", "location_found", "location_error", "location_rejected",
        "questions", "questions_errors", "questions_rejected",
        "contact_email", "contact_phone", "contact_code", "contact_wait", "contact_invalid", "contact_leave",
        "refresh_failed", "receipt", "receipt_host_steps",
    ]

    public init(previewScreen: String) {
        self.init(sessionProvider: { throw CancellationError() }, faceSignalProvider: { VisionFaceSignalProvider() }, locationSource: { DeviceLocationSource() }, onResult: { _ in })
        _model = StateObject(wrappedValue: VerificationModel.preview(previewScreen))
    }
}

extension VerificationModel {
    static func previewSession(documents: Bool, requirements: [String], form: Bool, questions: Bool = false) -> SessionInfo {
        let document = #"{"document_type":{"id":1,"name":"Demo identity document","two_sided":true,"capture_method":"camera"},"capture_method":"snapshot_or_upload","group_key":null,"rule":"all_of","min_required":null,"remaining_required":1,"requested_sides":["front","back"]}"#
        let facial = #"{"verification_type":"facial_verification","settings":{"gestures":["blink","smile","turn_left","turn_right","nod"],"gesture_count":3,"record_video":true,"video_retention_days":30}}"#
        let location = #"{"verification_type":"location_verification","settings":{"max_accuracy_m":50,"max_age_s":60,"mock_location":"reject","ip_country":"flag","reference":{"rule":"within","places":[{"label":"Head office"}]}}}"#
        let contact = { (type: String) in #"{"verification_type":"\#(type)_verification","settings":null}"# }
        let verification = requirements.map { $0 == "facial" ? facial : $0 == "location" ? location : contact($0) }.joined(separator: ",")
        let schema = #"[{"key":"country","label":"Country of residence","type":"country","required":true},{"key":"employment","label":"Employment","type":"single_select","required":true,"options":["Employed","Self employed","Student","Retired"]},{"key":"employer","label":"Employer name","type":"text","required":true,"show_if":{"match":"all","conditions":[{"path":"form.employment","op":"equals","value":"Employed"}]}},{"key":"income","label":"Yearly income","type":"number","required":false,"min":0,"max":10000000,"show_if":{"match":"any","conditions":[{"path":"form.employment","op":"in","value":["Employed","Self employed"]}]}},{"key":"birth_date","label":"Date of birth","type":"date","required":true},{"key":"contact_email","label":"Email address","type":"email","required":false},{"key":"sources","label":"Sources of funds","type":"multi_select","required":false,"options":["Salary","Savings","Investments","Other"]},{"key":"sources_other","label":"Other source of funds","type":"text","required":true,"show_if":{"conditions":[{"path":"form.sources","op":"contains","value":"Other"}]}},{"key":"terms","label":"I agree to share these details for this verification","type":"consent","required":true}]"#
        let json = #"{"session_id":"01a1fb33-a1d0-7081-aa9e-7ce29c2a41d8","environment":"sandbox","custom_message":null,"requester":{"name":"SDK's Workspace","logo_url":null},"upload_limits":{"max_file_size_bytes":10485760,"allowed_file_types":["jpg","png","webp","pdf"]},"profile":{"form_schema":"# + (questions ? schema : form ? #"[{"key":"founders","label":"Founders","type":"founders","required":true}]"# : "null") + #","verification_requirements":["# + verification + #"],"document_requirements":["# + (documents ? document : "") + "]}}"
        return try! JSONDecoder().decode(SessionInfo.self, from: Data(json.utf8))
    }

    static func previewPhoto() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 860, height: 540)).image { context in
            UIColor(white: 0.85, alpha: 1).setFill(); context.fill(CGRect(x: 0, y: 0, width: 860, height: 540))
            UIColor(white: 0.6, alpha: 1).setFill(); context.fill(CGRect(x: 60, y: 120, width: 220, height: 280))
            UIColor(white: 0.7, alpha: 1).setFill()
            for row in 0..<5 { context.fill(CGRect(x: 330, y: 140 + row * 52, width: 460 - row * 40, height: 22)) }
        }.jpegData(compressionQuality: 0.8)!
    }

    static func preview(_ screen: String) -> VerificationModel {
        let model = VerificationModel(makeFaceProvider: { VisionFaceSignalProvider() }, makeLocationSource: { DeviceLocationSource() })
        let descriptor = try! SessionDescriptor(sessionID: UUID(uuidString: "01a1fb33-a1d0-7081-aa9e-7ce29c2a41d8")!, token: "preview", apiBaseURL: URL(string: "http://127.0.0.1:9/api/v1")!, expiresAt: "2026-11-20T23:33:47.000000Z")
        model.client = VerificationSession(descriptor)
        let part = screen.split(separator: "_").first.map(String.init) ?? screen
        switch part {
        case "intro": return model
        case "documents", "capture", "review":
            model.info = previewSession(documents: true, requirements: ["facial", "location"], form: true)
            if part == "documents" { return model }
            model.open(model.documents[0])
            if screen == "capture" { return model }
            let photo = previewPhoto()
            model.captures[model.steps[0].id] = Capture(data: photo, name: "camera.jpg", source: .camera)
            if screen == "capture_selected" { return model }
            for step in model.steps { model.captures[step.id] = Capture(data: photo, name: "camera.jpg", source: .camera) }
            model.index = model.steps.count
        case "liveness":
            model.info = previewSession(documents: false, requirements: ["facial", "location"], form: false)
            model.prepareStep()
            guard let liveness = model.liveness else { return model }
            let hint: (String) -> String = { CredflareCopy.text($0) }
            switch screen {
            case "liveness_starting": liveness.stage = .preparing
            case "liveness_positioning": liveness.stage = .running; liveness.recording = true; liveness.current = 1; liveness.hint = hint(PositionStatus.tooSmall.copyKey)
            case "liveness_blink", "liveness_smile", "liveness_turn_left", "liveness_turn_right", "liveness_nod":
                let gesture = String(screen.dropFirst("liveness_".count))
                liveness.stage = .running; liveness.recording = true
                liveness.current = ["blink": 1, "smile": 2, "turn_left": 3, "turn_right": 3, "nod": 3][gesture]!
                liveness.hint = hint(LivenessSequence.promptKey(for: gesture))
            case "liveness_face_lost": liveness.stage = .running; liveness.recording = true; liveness.current = 2; liveness.hint = hint(CredflareSpec.CopyKey.livenessFaceLost)
            case "liveness_timeout": liveness.stage = .failed(hint(CredflareSpec.CopyKey.livenessTimeout))
            case "liveness_sending": liveness.stage = .sending
            default: break
            }
        case "location":
            model.info = previewSession(documents: false, requirements: ["location"], form: false)
            model.prepareStep()
            guard let location = model.location else { return model }
            let fix = LocationFix(latitude: 4.05112, longitude: 9.76791, accuracy: 12, altitude: nil, timestamp: Date(timeIntervalSince1970: 1_795_000_000), isMock: nil)
            switch screen {
            case "location_waiting": location.stage = .waiting(improving: true)
            case "location_found": location.stage = .found(fix)
            case "location_error": location.stage = .failed(CredflareCopy.text(CredflareSpec.CopyKey.locationLowAccuracy), retry: true)
            case "location_rejected": location.stage = .rejected(Rejection(.api(422, "", code: .locationReferenceNotMatched), requester: model.verifier, reference: location.settings.reference))
            default: break
            }
        case "questions":
            model.info = previewSession(documents: false, requirements: [], form: false, questions: true)
            model.prepareStep()
            guard let questions = model.questions else { return model }
            if screen == "questions_errors" {
                questions.answers = ["employment": .string("Employed"), "income": .string("-5"), "sources": .array([.string("Other")])]
                questions.errors = questions.questionnaire.errors(questions.answers)
            }
            if screen == "questions_rejected" { questions.stage = .rejected(Rejection(.api(422, "This question is not shown for the answers given.", code: nil), requester: model.verifier)) }
        case "contact":
            let phone = screen != "contact_email"
            model.info = previewSession(documents: false, requirements: [phone ? "phone" : "email"], form: false)
            model.prepareStep()
            guard let contact = model.contact else { return model }
            let resend = ISO8601.format(Date().addingTimeInterval(45)), expires = ISO8601.format(Date().addingTimeInterval(600))
            let sent = try! JSONDecoder().decode(ContactCodeSent.self, from: Data(#"{"channel":"phone","destination":"+237*******01","expires_at":"\#(expires)","resend_available_at":"\#(resend)","sends_remaining":4}"#.utf8))
            switch screen {
            case "contact_phone": contact.destination = "+237 650 000 001"
            case "contact_code": contact.sent = sent; contact.code = "1234"; contact.stage = .code
            case "contact_wait": contact.sent = sent; contact.stage = .rejected(Rejection(.api(422, "", code: .phoneResendTooSoon), requester: model.verifier))
            case "contact_invalid": contact.sent = sent; contact.stage = .rejected(Rejection(.api(422, "", code: .phoneCodeInvalid), requester: model.verifier))
            case "contact_leave": contact.stage = .rejected(Rejection(.api(422, "", code: .phoneNotConfigured), requester: model.verifier, contact: HelpContact(email: "help@northwind.example")))
            default: break
            }
        case "refresh":
            model.info = previewSession(documents: false, requirements: [], form: false, questions: true)
            model.received = [CredflareCopy.text(CredflareSpec.CopyKey.receiptAnswers)]
            model.pendingRefresh = true
            model.error = CredflareCopy.text(CredflareSpec.CopyKey.errorsRefreshFailed)
        case "receipt":
            let host = screen == "receipt_host_steps"
            model.info = previewSession(documents: false, requirements: [], form: host)
            model.received = [CredflareCopy.text(CredflareSpec.CopyKey.receiptDocument, ["document": "Demo identity document"]), CredflareCopy.text(CredflareSpec.CopyKey.receiptAnswers), CredflareCopy.text(CredflareSpec.CopyKey.receiptPhone), CredflareCopy.text(CredflareSpec.CopyKey.receiptSelfie), CredflareCopy.text(CredflareSpec.CopyKey.receiptLocation)]
        default: break
        }
        return model
    }
}
#endif
