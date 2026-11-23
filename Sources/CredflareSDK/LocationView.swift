#if canImport(UIKit)
import SwiftUI

@MainActor
final class LocationModel: ObservableObject {
    enum Stage: Equatable { case consent, waiting(improving: Bool), found(LocationFix), sending, failed(String, retry: Bool), rejected(Rejection) }
    @Published var stage: Stage = .consent
    let settings: LocationSettings
    let verifier: String
    var help = HelpContact()
    private let client: VerificationSession
    private let makeSource: () -> LocationSource
    private let onDone: () -> Void
    private var failures = 0
    private var submitKey = UUID()

    init(client: VerificationSession, settings: LocationSettings, verifier: String, makeSource: @escaping () -> LocationSource, onDone: @escaping () -> Void) {
        self.client = client; self.settings = settings; self.verifier = verifier; self.makeSource = makeSource; self.onDone = onDone
    }

    func locate() async {
        stage = .waiting(improving: false)
        let outcome = await LocationCollector.collect(from: makeSource(), settings: settings) { _ in
            Task { @MainActor [weak self] in if case .waiting = self?.stage { self?.stage = .waiting(improving: true) } }
        }
        switch outcome {
        case .fix(let fix): submitKey = UUID(); stage = .found(fix)
        case .denied: stage = .failed(text(CredflareSpec.CopyKey.locationPermissionDenied), retry: true)
        case .unavailable: stage = .failed(text(CredflareSpec.CopyKey.locationUnavailable), retry: true)
        case .mock: failed(CredflareSpec.CopyKey.locationMockDetected)
        case .lowAccuracy: failed(settings.reference == nil ? CredflareSpec.CopyKey.locationLowAccuracy : CredflareSpec.CopyKey.locationPlaceNotPrecise)
        case .timeout: failed(CredflareSpec.CopyKey.locationTimeout)
        }
    }

    private func failed(_ key: String) {
        failures += 1
        if failures >= CredflareSpec.Location.retryAttempts { stage = .failed(text(CredflareSpec.CopyKey.locationRetriesExhausted), retry: false) }
        else { stage = .failed(text(key), retry: true) }
    }

    func send(_ fix: LocationFix) async {
        stage = .sending
        do {
            _ = try await client.submitLocation(fix.submission(), key: submitKey)
            onDone()
        } catch let error as CredflareError {
            if case .api(422, _, _) = error { stage = .rejected(Rejection(error, requester: verifier, contact: help, reference: settings.reference)) }
            else { stage = .failed(text(CredflareSpec.CopyKey.errorsSendLocationFailed), retry: true) }
        } catch {
            stage = .failed(text(CredflareSpec.CopyKey.errorsSendLocationFailed), retry: true)
        }
    }

    private func text(_ key: String) -> String { CredflareCopy.text(key, ["verifier": verifier]) }
}

struct LocationView: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var model: LocationModel
    var body: some View {
        let theme = CredflareTheme(scheme)
        VStack(spacing: CredflareTheme.gap) {
            SpecIconView(CredflareSpec.Icons.location, color: theme.primary, size: CGFloat(CredflareSpec.Tokens.sizeIllustration))
            switch model.stage {
            case .consent:
                TitleText(LocationCopy.title(model.settings.reference))
                if let requirement = LocationCopy.requirement(model.settings.reference) { ThemedText(requirement) }
                ThemedText(CredflareCopy.text(CredflareSpec.CopyKey.locationWhy, ["verifier": model.verifier]), tone: \.muted)
                ThemedText(CredflareCopy.text(CredflareSpec.CopyKey.locationWhatShared), tone: \.muted)
                ThemedText(CredflareCopy.text(CredflareSpec.CopyKey.locationPermissionPrompt), style: CredflareSpec.Tokens.typeSmall, tone: \.muted)
                PrimaryButton(CredflareCopy.text(CredflareSpec.CopyKey.locationShare)) { Task { await model.locate() } }
            case .waiting(let improving):
                TitleText(LocationCopy.title(model.settings.reference))
                LoadingBlock(label: CredflareCopy.text(improving ? CredflareSpec.CopyKey.locationWaitingAccuracy : CredflareSpec.CopyKey.locationWaiting))
            case .found(let fix):
                TitleText(CredflareCopy.text(CredflareSpec.CopyKey.locationFoundTitle))
                ThemedText(CredflareCopy.text(CredflareSpec.CopyKey.locationFoundBody), tone: \.muted)
                VStack(spacing: CGFloat(CredflareSpec.Tokens.spacingMd)) {
                    detail(CredflareSpec.CopyKey.locationAccuracyLabel, CredflareCopy.text(CredflareSpec.CopyKey.locationAccuracyValue, ["meters": String(Int(fix.accuracy.rounded()))]))
                    detail(CredflareSpec.CopyKey.locationCoordinatesLabel, String(format: "%.5f, %.5f", fix.latitude, fix.longitude))
                    detail(CredflareSpec.CopyKey.locationTimeLabel, fix.timestamp.formatted(date: .omitted, time: .standard))
                }
                .padding(CGFloat(CredflareSpec.Tokens.spacingLg))
                .frame(maxWidth: .infinity)
                .background(theme.soft)
                .clipShape(RoundedRectangle(cornerRadius: CGFloat(CredflareSpec.Tokens.radiusLg)))
                PrimaryButton(CredflareCopy.text(CredflareSpec.CopyKey.locationSend)) { Task { await model.send(fix) } }
                SecondaryButton(CredflareCopy.text(CredflareSpec.CopyKey.locationRetry)) { Task { await model.locate() } }
            case .sending:
                LoadingBlock(label: CredflareCopy.text(CredflareSpec.CopyKey.sendingSending))
            case .rejected(let rejection):
                RejectionPanel(rejection: rejection, fallbackTitle: LocationCopy.title(model.settings.reference)) { Task { await model.locate() } }
            case .failed(let message, let retry):
                TitleText(LocationCopy.title(model.settings.reference))
                ErrorBox(message: message)
                if retry { PrimaryButton(CredflareCopy.text(CredflareSpec.CopyKey.locationRetry)) { Task { await model.locate() } } }
            }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(spacing: CGFloat(CredflareSpec.Tokens.spacingXxs)) {
            ThemedText(CredflareCopy.text(label), style: CredflareSpec.Tokens.typeLabel, tone: \.muted)
            ThemedText(value)
        }
    }
}
#endif
