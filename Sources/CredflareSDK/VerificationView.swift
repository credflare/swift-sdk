#if canImport(UIKit)
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AVFoundation
import ImageIO

@MainActor
private final class VerificationModel: ObservableObject {
    struct Capture {
        let data: Data; let name: String; let source: CaptureSource; let key = UUID()
        var fileID: Int?
    }
    @Published var info: SessionInfo?
    @Published var document: DocumentRequirement?
    @Published var index = 0
    @Published var captures: [String: Capture] = [:]
    @Published var working = false
    @Published var error: String?
    @Published var pendingReceipt = false
    @Published var received = false
    @Published var editing = false
    private var client: VerificationSession?
    private var submissionKey = UUID()
    var dirty: Bool { !captures.isEmpty }
    var steps: [CaptureStep] { (try? document?.captureSteps()) ?? [] }
    var reviewing: Bool { document != nil && index == steps.count }
    var step: CaptureStep? { index < steps.count ? steps[index] : nil }
    var complete: Bool { info?.profile != nil && !pendingReceipt && (info?.profile?.documentRequirements.isEmpty ?? true) && !(info?.profile?.needsHostSteps ?? false) }
    func start(_ provider: @escaping () async throws -> SessionDescriptor) async {
        guard !working else { return }
        working = true; error = nil
        defer { working = false }
        do { client = VerificationSession(try await provider()); info = try await client!.get() }
        catch { show(error) }
    }
    func show(_ cause: Error) {
        if let error = cause as? CredflareError, error.type == "session_unavailable" { self.error = "Your session has expired. Close this screen and start again." }
        else if cause is CancellationError { self.error = "The request was cancelled. Try again with the same evidence." }
        else { self.error = (cause as? CredflareError)?.localizedDescription ?? "We could not complete that step. Please try again." }
    }
    func open(_ requirement: DocumentRequirement) {
        document = requirement; captures = [:]; index = 0; editing = false; submissionKey = UUID(); error = nil
    }
    func clearDocument() { document = nil; captures = [:]; index = 0; error = nil }
    func select(data: Data, name: String, source: CaptureSource) throws {
        guard let info, let step, info.uploadLimits.maxFileSizeBytes > 0 else { throw CredflareError.validation("File limits are unavailable. Restart the flow.") }
        let ext = (name as NSString).pathExtension.lowercased()
        let normalized = ext == "jpeg" ? "jpg" : ext
        guard info.uploadLimits.allowedFileTypes.contains(normalized) else { throw CredflareError.validation("This file type is not allowed by your verifier.") }
        guard !data.isEmpty, data.count <= info.uploadLimits.maxFileSizeBytes else { throw CredflareError.validation("This file is empty or too large. Choose another file.") }
        captures[step.id] = Capture(data: data, name: name, source: source); submissionKey = UUID(); error = nil
    }
    func importFile(_ url: URL) async {
        guard !working else { return }; working = true; error = nil
        defer { working = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            if let size, size > (info?.uploadLimits.maxFileSizeBytes ?? 0) { throw CredflareError.validation("This file is too large.") }
            guard let limit = info?.uploadLimits.maxFileSizeBytes, limit > 0 else { throw CredflareError.validation("File limits are unavailable.") }
            let data = try await Task.detached {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                var data = Data()
                while let chunk = try handle.read(upToCount: 65536), !chunk.isEmpty {
                    guard chunk.count <= limit - data.count else { throw CredflareError.validation("This file is too large.") }
                    data.append(chunk)
                }
                return data
            }.value
            try select(data: data, name: url.lastPathComponent, source: .upload)
        } catch { show(error) }
    }
    func photo(_ image: UIImage) {
        do {
            let png = !(info?.uploadLimits.allowedFileTypes.contains("jpg") ?? false)
            guard let data = png ? image.pngData() : image.jpegData(compressionQuality: 0.95) else { throw CredflareError.validation("The camera did not return a readable photo.") }
            try select(data: data, name: png ? "camera.png" : "camera.jpg", source: .camera)
        } catch { show(error) }
    }
    func next() { index = editing ? steps.count : index + 1; editing = false; error = nil }
    func refresh() async {
        guard !working else { return }; working = true; error = nil
        defer { working = false }
        do { info = try await client!.get(); pendingReceipt = false }
        catch { show(error) }
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
            clearDocument(); pendingReceipt = true; received = true
        } catch { show(error); working = false; return }
        working = false
        await refresh()
    }
}

@MainActor
public struct CredflareVerificationView: View {
    private let provider: () async throws -> SessionDescriptor
    private let autoStart: Bool
    private let onResult: (VerificationResult) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model = VerificationModel()
    @State private var autoStarted = false
    @State private var importing = false
    @State private var camera = false
    @State private var confirmClose = false
    @State private var confirmDiscard = false
    public init(sessionProvider: @escaping () async throws -> SessionDescriptor, autoStart: Bool = false, onResult: @escaping (VerificationResult) -> Void) {
        self.provider = sessionProvider; self.autoStart = autoStart; self.onResult = onResult
    }
    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let name = model.info?.requester?.name { Text(name).font(.subheadline.weight(.medium)).lineLimit(1) }
                if model.info?.environment == "sandbox" { Text("Test mode").font(.caption2).padding(5).background(.orange.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 5)) }
                Spacer()
                Button("Close") { if model.complete { onResult(.submitted) } else { confirmClose = true } }.disabled(model.working)
            }.padding(.horizontal, 24).padding(.vertical, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content
                    if let error = model.error { Text(error).foregroundStyle(.red).padding().overlay(RoundedRectangle(cornerRadius: 12).stroke(.red)).accessibilityAddTraits(.updatesFrequently) }
                    HStack { Spacer(); Text("Secured by Credflare").font(.caption).foregroundStyle(.secondary); Spacer() }.padding(.top, 24)
                }.padding(24).frame(maxWidth: 600)
            }
        }
        .tint(colorScheme == .dark ? Color(red: 185/255, green: 205/255, blue: 1) : Color(red: 32/255, green: 49/255, blue: 95/255))
        .background(colorScheme == .dark ? Color(red: 17/255, green: 28/255, blue: 49/255) : Color.white)
        .task { if autoStart && !autoStarted { autoStarted = true; await model.start(provider) } }
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled()
        .confirmationDialog("Leave verification?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Leave for now", role: .destructive) { onResult(.cancelled) }
            Button("Continue verification", role: .cancel) {}
        } message: { Text(model.dirty ? "Your unsent photos and files will be discarded. Documents you already sent are kept." : "Documents you already sent are kept. You can return through the app that requested them.") }
        .confirmationDialog("Discard unsent evidence?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard and return", role: .destructive) { model.clearDocument() }
            Button("Keep editing", role: .cancel) {}
        } message: { Text("The photos and files you have not sent will be discarded.") }
        .fileImporter(isPresented: $importing, allowedContentTypes: allowedTypes) { result in
            switch result {
            case .success(let url): Task { await model.importFile(url) }
            case .failure(let error): if (error as? CocoaError)?.code != .userCancelled { model.show(error) }
            }
        }
        .sheet(isPresented: $camera) { CameraPicker { image in camera = false; if let image { model.photo(image) } }.ignoresSafeArea() }
    }
    @ViewBuilder private var content: some View {
        if model.working {
            ProgressView(model.info == nil ? "Getting ready…" : "Sending or checking your document…").frame(maxWidth: .infinity).padding(.vertical, 64)
        } else if model.info == nil {
            title("Share your documents")
            Text("Choose a document, add each requested side, then review before sending.").foregroundStyle(.secondary)
            action(model.error == nil ? "Start" : "Try again") { Task { await model.start(provider) } }
        } else if model.pendingReceipt {
            title("Your document was sent")
            Text("Check your progress to see whether anything else is needed.")
            action("Check progress") { Task { await model.refresh() } }
        } else if model.complete {
            title("Documents received")
            Text("Your verifier will review what you sent.").foregroundStyle(.secondary)
            action("Done") { onResult(.submitted) }
        } else if let document = model.document {
            Button("‹ Documents") { if model.dirty { confirmDiscard = true } else { model.clearDocument() } }
            Text(document.documentType.name).font(.subheadline).foregroundStyle(.secondary)
            captureContent
        } else {
            title("Documents requested")
            if let message = model.info?.customMessage, !message.isEmpty { Text(message).foregroundStyle(.secondary) }
            ForEach(model.info?.profile?.documentRequirements ?? []) { requirement in
                VStack(alignment: .leading, spacing: 8) {
                    if requirement.rule == "any_of" { Text("Choose \(requirement.remainingRequired ?? requirement.minRequired ?? 1) from this group").font(.caption).foregroundStyle(.secondary) }
                    Button { model.open(requirement) } label: {
                        HStack { VStack(alignment: .leading, spacing: 6) { Text(requirement.documentType.name).font(.headline); Text(requirement.methodSummary).font(.subheadline).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right") }
                            .padding(18).frame(maxWidth: .infinity, alignment: .leading).overlay(RoundedRectangle(cornerRadius: 14).stroke(.secondary.opacity(0.5)))
                    }.buttonStyle(.plain).disabled(!requirement.isSupported)
                }
            }
            if model.info?.profile?.documentRequirements.isEmpty ?? true {
                Text("Your documents are received. Return to the requesting app for its remaining checks.")
                action("Return to app") { onResult(.hostActionRequired) }
            }
        }
    }
    @ViewBuilder private var captureContent: some View {
        if model.reviewing {
            title("Review before sending")
            Text("Check every photo and file before sharing.").foregroundStyle(.secondary)
            ForEach(model.steps) { step in
                if let capture = model.captures[step.id] {
                    HStack { Text("\(step.side.label): \(capture.source == .camera ? "Camera photo" : "Saved file")"); Spacer(); Button("Change") { model.index = model.steps.firstIndex(where: { $0.id == step.id })!; model.editing = true } }
                    preview(capture)
                }
            }
            action("Send document") { Task { await model.send() } }
        } else if let step = model.step {
            title(step.side.label)
            Text(step.input == .camera ? "Camera photo" : step.input == .upload ? "Saved file" : "Photo or file").foregroundStyle(.secondary)
            ProgressView(value: Double(model.index + 1), total: Double(model.steps.count + 1))
            Text("Step \(model.index + 1) of \(model.steps.count + 1)").font(.caption).foregroundStyle(.secondary)
            if let capture = model.captures[step.id] {
                preview(capture)
                Text(capture.name).font(.caption).lineLimit(2)
                Button("Choose again") { model.captures.removeValue(forKey: step.id) }
                action(model.editing ? "Return to review" : model.index == model.steps.count - 1 ? "Review document" : "Continue") { model.next() }
            } else {
                Text(step.input == .camera ? "Keep all four corners visible and avoid reflections." : "Add a clear photo, scan or PDF of this side.")
                Image(systemName: "doc.text.viewfinder").font(.system(size: 64)).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 160)
                if step.input != .upload { action("Take photo") { openCamera() } }
                if step.input != .camera { action("Choose a file") { importing = true } }
                if let info = model.info { Text("\(info.uploadLimits.allowedFileTypes.joined(separator: ", ").uppercased()), up to \(info.uploadLimits.maxFileSizeBytes / 1048576) MB").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
    private func title(_ value: String) -> some View { Text(value).font(.title2.weight(.bold)).accessibilityAddTraits(.isHeader) }
    private func action(_ label: String, _ work: @escaping () -> Void) -> some View { Button(action: work) { Text(label).font(.headline).foregroundStyle(colorScheme == .dark ? Color(red: 22/255, green: 41/255, blue: 78/255) : Color.white).frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(.borderedProminent).controlSize(.large) }
    private func thumbnail(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1600, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
    @ViewBuilder private func preview(_ capture: VerificationModel.Capture) -> some View {
        if let image = thumbnail(capture.data) { Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 200).accessibilityLabel("Selected document") }
        else { Label(capture.name, systemImage: "doc.fill").frame(maxWidth: .infinity, minHeight: 100).background(.secondary.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 14)) }
    }
    private var allowedTypes: [UTType] {
        (model.info?.uploadLimits.allowedFileTypes ?? []).compactMap { UTType(filenameExtension: $0) }
    }
    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { model.error = "The camera is unavailable. Use a physical device for camera testing."; return }
        let permission = AVCaptureDevice.authorizationStatus(for: .video)
        guard permission != .denied && permission != .restricted else { model.error = "Camera access is off. Enable it in Settings, then try again."; return }
        camera = true
    }
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
