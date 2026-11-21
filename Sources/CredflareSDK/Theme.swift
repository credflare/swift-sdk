import Foundation
import SwiftUI

public enum CredflareCopy {
    public static func text(_ key: String, _ values: [String: String] = [:]) -> String {
        var value = CredflareSpec.Copy.en[key] ?? key
        for (name, replacement) in values { value = value.replacingOccurrences(of: "{\(name)}", with: replacement) }
        return value
    }
    public static func verifier(_ name: String?) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? text(CredflareSpec.CopyKey.commonVerifierFallback) : trimmed
    }
}

extension Color {
    init(argb: UInt32) {
        self.init(.sRGB, red: Double((argb >> 16) & 0xFF) / 255, green: Double((argb >> 8) & 0xFF) / 255, blue: Double(argb & 0xFF) / 255, opacity: Double((argb >> 24) & 0xFF) / 255)
    }
}

struct CredflareTheme {
    let palette: SpecPalette
    init(_ scheme: ColorScheme) { palette = scheme == .dark ? CredflareSpec.Tokens.dark : CredflareSpec.Tokens.light }
    var primary: Color { Color(argb: palette.primary) }
    var onPrimary: Color { Color(argb: palette.onPrimary) }
    var surface: Color { Color(argb: palette.surface) }
    var ink: Color { Color(argb: palette.ink) }
    var muted: Color { Color(argb: palette.muted) }
    var soft: Color { Color(argb: palette.soft) }
    var border: Color { Color(argb: palette.border) }
    var accent: Color { Color(argb: palette.accent) }
    var success: Color { Color(argb: palette.success) }
    var error: Color { Color(argb: palette.error) }
    var warningSoft: Color { Color(argb: palette.warningSoft) }
    var warningInk: Color { Color(argb: palette.warningInk) }

    static func space(_ value: Int) -> CGFloat { CGFloat(value) }
    static let gutter = CGFloat(CredflareSpec.Tokens.spacingGutter)
    static let gap = CGFloat(CredflareSpec.Tokens.spacingGap)
}

extension Font.Weight {
    init(spec weight: Int) {
        switch weight {
        case ..<450: self = .regular
        case ..<600: self = .medium
        default: self = .bold
        }
    }
}

extension View {
    func specText(_ style: SpecTextStyle) -> some View {
        font(.system(size: CGFloat(style.size), weight: Font.Weight(spec: style.weight)))
            .lineSpacing(max(0, CGFloat(style.lineHeight - style.size * 1.2)))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

enum SpecPathCommand: Equatable {
    case move(CGPoint), line(CGPoint), curve(CGPoint, CGPoint, CGPoint), close
}

enum SpecPathParser {
    static func parse(_ d: String) -> [SpecPathCommand] {
        var tokens: [String] = []
        var current = ""
        for character in d {
            if "MLCZ".contains(character) {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(character))
            } else if character == " " || character == "," {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else if character == "-" && !current.isEmpty && !current.hasSuffix("e") {
                tokens.append(current); current = "-"
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        var commands: [SpecPathCommand] = []
        var index = 0
        var command = ""
        func number() -> CGFloat? {
            guard index < tokens.count, let value = Double(tokens[index]) else { return nil }
            index += 1
            return CGFloat(value)
        }
        func point() -> CGPoint? { guard let x = number(), let y = number() else { return nil }; return CGPoint(x: x, y: y) }
        while index < tokens.count {
            if "MLCZ".contains(tokens[index]) { command = tokens[index]; index += 1 }
            switch command {
            case "M": guard let p = point() else { return commands }; commands.append(.move(p)); command = "L"
            case "L": guard let p = point() else { return commands }; commands.append(.line(p))
            case "C": guard let a = point(), let b = point(), let c = point() else { return commands }; commands.append(.curve(a, b, c))
            case "Z": commands.append(.close); command = ""
            default: return commands
            }
        }
        return commands
    }
}

struct SpecPathShape: Shape {
    let commands: [SpecPathCommand]
    let viewBox: CGFloat
    init(_ d: String, viewBox: Double) { commands = SpecPathParser.parse(d); self.viewBox = CGFloat(viewBox) }
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / viewBox
        let origin = CGPoint(x: rect.midX - viewBox * scale / 2, y: rect.midY - viewBox * scale / 2)
        func map(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale) }
        var path = Path()
        for command in commands {
            switch command {
            case .move(let p): path.move(to: map(p))
            case .line(let p): path.addLine(to: map(p))
            case .curve(let a, let b, let c): path.addCurve(to: map(c), control1: map(a), control2: map(b))
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}

public struct SpecIconView: View {
    let icon: SpecIcon
    let color: Color
    let size: CGFloat
    public init(_ icon: SpecIcon, color: Color, size: CGFloat = CGFloat(CredflareSpec.Tokens.sizeIcon)) { self.icon = icon; self.color = color; self.size = size }
    public var body: some View {
        let scale = size / CGFloat(icon.viewBox)
        ZStack {
            ForEach(Array(icon.paths.enumerated()), id: \.offset) { _, path in
                let shape = SpecPathShape(path.d, viewBox: icon.viewBox)
                if path.fill { shape.fill(color.opacity(path.fillOpacity)) }
                if path.stroke { shape.stroke(color.opacity(path.strokeOpacity), style: StrokeStyle(lineWidth: CGFloat(path.strokeWidth) * scale, lineCap: .round, lineJoin: .round)) }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
