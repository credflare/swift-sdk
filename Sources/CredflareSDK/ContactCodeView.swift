#if canImport(UIKit)
import SwiftUI

struct ContactCodeView: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var model: ContactCodeModel
    @FocusState private var focused: Bool

    var body: some View {
        let theme = CredflareTheme(scheme)
        let email = model.channel == .email
        VStack(spacing: CredflareTheme.gap) {
            switch model.stage {
            case .destination:
                SpecIconView(CredflareSpec.Icons.received, color: theme.primary, size: CGFloat(CredflareSpec.Tokens.sizeIllustration))
                TitleText(model.text(model.titleKey))
                ThemedText(model.text(email ? CredflareSpec.CopyKey.emailBody : CredflareSpec.CopyKey.phoneBody), tone: \.muted)
                VStack(spacing: CGFloat(CredflareSpec.Tokens.spacingXs)) {
                    ThemedText(model.text(email ? CredflareSpec.CopyKey.emailLabel : CredflareSpec.CopyKey.phoneLabel), style: CredflareSpec.Tokens.typeLabel)
                    InputField(placeholder: email ? model.text(CredflareSpec.CopyKey.emailPlaceholder) : "", text: $model.destination, keyboard: email ? .emailAddress : .phonePad, content: email ? .emailAddress : .telephoneNumber, invalid: model.problem != nil)
                    if !email { ThemedText(model.text(CredflareSpec.CopyKey.phoneHint), style: CredflareSpec.Tokens.typeSmall, tone: \.muted) }
                }
                if let problem = model.problem { ErrorBox(message: problem) }
                PrimaryButton(model.text(email ? CredflareSpec.CopyKey.emailSend : CredflareSpec.CopyKey.phoneSend)) { Task { await model.send() } }
                    .disabled(model.destination.trimmingCharacters(in: .whitespaces).isEmpty)
                if model.sent != nil {
                    Button(model.text(CredflareSpec.CopyKey.contactCodeTitle)) { model.returnToCode() }
                        .font(.system(size: CGFloat(CredflareSpec.Tokens.typeButton.size), weight: .medium)).foregroundStyle(theme.primary)
                        .frame(minHeight: CGFloat(CredflareSpec.Tokens.sizeLinkHeight))
                }
            case .sending:
                LoadingBlock(label: model.text(CredflareSpec.CopyKey.contactCodeSending))
            case .code:
                SpecIconView(CredflareSpec.Icons.received, color: theme.primary, size: CGFloat(CredflareSpec.Tokens.sizeIllustration))
                TitleText(model.text(CredflareSpec.CopyKey.contactCodeTitle))
                ThemedText(model.text(CredflareSpec.CopyKey.contactCodeBody, ["destination": model.sent?.destination ?? model.destination, "minutes": String(CredflareSpec.Requirements.contactCodesTtlMinutes)]), tone: \.muted)
                VStack(spacing: CGFloat(CredflareSpec.Tokens.spacingXs)) {
                    ThemedText(model.text(CredflareSpec.CopyKey.contactCodeLabel), style: CredflareSpec.Tokens.typeLabel)
                    InputField(placeholder: "", text: Binding(get: { model.code }, set: { model.setCode($0) }), keyboard: .numberPad, content: .oneTimeCode, invalid: model.problem != nil, monospaced: true)
                        .focused($focused)
                }
                if let problem = model.problem { ErrorBox(message: problem) }
                PrimaryButton(model.text(CredflareSpec.CopyKey.contactCodeConfirm)) { Task { await model.confirm() } }
                    .disabled(!ContactChannel.isCode(model.code))
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let wait = model.secondsUntilResend(now: context.date)
                    VStack(spacing: CGFloat(CredflareSpec.Tokens.spacingXs)) {
                        if model.canResend && wait > 0 {
                            ThemedText(model.text(CredflareSpec.CopyKey.contactCodeResendIn, ["seconds": String(wait)]), style: CredflareSpec.Tokens.typeSmall, tone: \.muted)
                        } else if model.canResend {
                            SecondaryButton(model.text(CredflareSpec.CopyKey.contactCodeResend)) { Task { await model.resend() } }
                        }
                        if model.changeAfter && wait > 0 {
                            ThemedText(model.text(email ? CredflareSpec.CopyKey.emailChangeAfter : CredflareSpec.CopyKey.phoneChangeAfter), style: CredflareSpec.Tokens.typeSmall, tone: \.muted)
                        }
                        if let remaining = model.sent?.sendsRemaining {
                            ThemedText(model.text(CredflareSpec.CopyKey.contactCodeSendsRemaining, ["count": String(remaining)]), style: CredflareSpec.Tokens.typeSmall, tone: \.muted)
                        }
                    }
                }
                Button(model.text(email ? CredflareSpec.CopyKey.emailChange : CredflareSpec.CopyKey.phoneChange)) { model.changeDestination() }
                    .font(.system(size: CGFloat(CredflareSpec.Tokens.typeButton.size), weight: .medium)).foregroundStyle(theme.primary)
                    .frame(minHeight: CGFloat(CredflareSpec.Tokens.sizeLinkHeight))
            case .confirming:
                LoadingBlock(label: model.text(CredflareSpec.CopyKey.contactCodeConfirming))
            case .rejected(let rejection):
                RejectionPanel(rejection: rejection, fallbackTitle: model.text(model.titleKey)) { Task { await model.perform(rejection) } }
            }
        }
        .onChange(of: model.stage) { stage in focused = stage == .code }
    }
}

struct InputField: View {
    @Environment(\.colorScheme) private var scheme
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var content: UITextContentType? = nil
    var invalid = false
    var monospaced = false
    var multiline = false

    var body: some View {
        let theme = CredflareTheme(scheme)
        Group {
            if multiline { TextField(placeholder, text: $text, axis: .vertical).lineLimit(3...8) }
            else { TextField(placeholder, text: $text) }
        }
        .keyboardType(keyboard)
        .textContentType(content)
        .textInputAutocapitalization(keyboard == .default ? .sentences : .never)
        .autocorrectionDisabled(keyboard != .default)
        .font(monospaced ? .system(size: CGFloat(CredflareSpec.Tokens.typeTitle.size), weight: .semibold, design: .monospaced) : .system(size: CGFloat(CredflareSpec.Tokens.typeBody.size)))
        .multilineTextAlignment(monospaced ? .center : .leading)
        .foregroundStyle(theme.ink)
        .padding(.horizontal, CGFloat(CredflareSpec.Tokens.spacingMd))
        .frame(minHeight: CGFloat(CredflareSpec.Tokens.sizeButtonHeight))
        .padding(.vertical, multiline ? CGFloat(CredflareSpec.Tokens.spacingSm) : 0)
        .background(theme.soft)
        .clipShape(RoundedRectangle(cornerRadius: CGFloat(CredflareSpec.Tokens.radiusMd)))
        .overlay(RoundedRectangle(cornerRadius: CGFloat(CredflareSpec.Tokens.radiusMd)).stroke(invalid ? theme.error : theme.border))
    }
}
#endif
