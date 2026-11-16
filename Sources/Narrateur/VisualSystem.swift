import SwiftUI
import AppKit
import CoreText

enum Instrument {
    static let void = color(0x07080c), base = color(0x0c0d12), surface = color(0x11131a), raised = color(0x171a23)
    static let ghost = color(0xe7ebf2), muted = color(0x9aa2b5), dim = color(0x6a7285), cyan = color(0x7ad7ff), red = color(0xff3333)
    static let line = Color.white.opacity(0.08)
    static func color(_ hex: UInt32) -> Color { Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
    static func body(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        NSFont(name: "SpaceGrotesk-Regular", size: size) != nil ? .custom("SpaceGrotesk-Regular", size: size).weight(weight) : .system(size: size, weight: weight)
    }
    static func mono(_ size: CGFloat = 10) -> Font {
        NSFont(name: "JetBrainsMono-Regular", size: size) != nil ? .custom("JetBrainsMono-Regular", size: size) : .system(size: size, design: .monospaced)
    }
    static func registerFonts() {
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("Fonts"), let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension == "ttf" { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
    }
}
struct Eyebrow: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(Instrument.mono(9)).tracking(1.8).foregroundStyle(Instrument.muted) }
}
struct SteelPanel: ViewModifier {
    var accent = false
    func body(content: Content) -> some View {
        content.padding(16).background(Instrument.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(accent ? Instrument.cyan.opacity(0.35) : Instrument.line, lineWidth: 1))
            .overlay(alignment: .topLeading) {
                if accent { Rectangle().fill(Instrument.cyan).frame(width: 28, height: 1).padding(.leading, 16) }
            }
    }
}
struct InstrumentButton: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Instrument.body(13, weight: .semibold))
            .foregroundStyle(primary && enabled ? Instrument.void : Instrument.ghost)
            .padding(.horizontal, 14).frame(height: 36)
            .background(primary && enabled ? Instrument.cyan.opacity(configuration.isPressed ? 0.75 : 1) : Instrument.raised)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Instrument.line, lineWidth: 1))
            .opacity(enabled ? 1 : 0.4)
    }
}
