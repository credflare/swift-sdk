import SwiftUI

struct ThemedText: View {
    @Environment(\.colorScheme) private var scheme
    let value: String
    let style: SpecTextStyle
    let tone: KeyPath<CredflareTheme, Color>
    init(_ value: String, style: SpecTextStyle = CredflareSpec.Tokens.typeBody, tone: KeyPath<CredflareTheme, Color> = \.ink) { self.value = value; self.style = style; self.tone = tone }
    var body: some View { Text(value).specText(style).foregroundStyle(CredflareTheme(scheme)[keyPath: tone]) }
}

struct TitleText: View {
    let value: String
    init(_ value: String) { self.value = value }
    var body: some View { ThemedText(value, style: CredflareSpec.Tokens.typeTitle).accessibilityAddTraits(.isHeader) }
}

struct PrimaryButton: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    let label: String
    let action: () -> Void
    init(_ label: String, action: @escaping () -> Void) { self.label = label; self.action = action }
    var body: some View {
        let theme = CredflareTheme(scheme)
        Button(action: action) {
            Text(label).specText(CredflareSpec.Tokens.typeButton)
                .foregroundStyle(theme.onPrimary)
                .frame(maxWidth: .infinity, minHeight: CGFloat(CredflareSpec.Tokens.sizeButtonHeight))
                .background(theme.primary.opacity(enabled ? 1 : 0.5))
                .clipShape(RoundedRectangle(cornerRadius: CGFloat(CredflareSpec.Tokens.radiusLg)))
        }.buttonStyle(.plain)
    }
}

struct SecondaryButton: View {
    @Environment(\.colorScheme) private var scheme
    let label: String
    let action: () -> Void
    init(_ label: String, action: @escaping () -> Void) { self.label = label; self.action = action }
    var body: some View {
        let theme = CredflareTheme(scheme)
        Button(action: action) {
            Text(label).specText(CredflareSpec.Tokens.typeButton).foregroundStyle(theme.primary)
                .frame(maxWidth: .infinity, minHeight: CGFloat(CredflareSpec.Tokens.sizeLinkHeight))
                .overlay(RoundedRectangle(cornerRadius: CGFloat(CredflareSpec.Tokens.radiusLg)).stroke(theme.border))
        }.buttonStyle(.plain)
    }
}

struct ErrorBox: View {
    @Environment(\.colorScheme) private var scheme
    let message: String
    var body: some View {
        let theme = CredflareTheme(scheme)
        VStack(spacing: CGFloat(CredflareSpec.Tokens.spacingSm)) {
            SpecIconView(CredflareSpec.Icons.error, color: theme.error)
            Text(message).specText(CredflareSpec.Tokens.typeBody).foregroundStyle(theme.error)
        }
        .padding(CGFloat(CredflareSpec.Tokens.spacingLg))
        .frame(maxWidth: .infinity)
        .overlay(RoundedRectangle(cornerRadius: CGFloat(CredflareSpec.Tokens.radiusMd)).stroke(theme.error))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

struct LoadingBlock: View {
    @Environment(\.colorScheme) private var scheme
    let label: String
    var body: some View {
        VStack(spacing: CGFloat(CredflareSpec.Tokens.spacingMd)) {
            ProgressView().tint(CredflareTheme(scheme).primary)
            ThemedText(label, tone: \.muted)
        }.frame(maxWidth: .infinity).padding(.vertical, 64)
    }
}
