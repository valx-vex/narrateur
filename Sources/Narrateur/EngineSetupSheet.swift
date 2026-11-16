import SwiftUI
import AppKit
import NarrateurCore

/// Shown when book-audio cannot be found: the two commands to paste, what the first render downloads, and a way to look again.
/// Each button's name (its title, or its label) is what VoiceOver reads: SwiftUI puts it in AXAttributedDescription and
/// declares neither AXTitle nor AXDescription, so System Events sees no name. The identifiers are for a script.
struct EngineSetupSheet: View {
    let problem: String?
    let checkAgain: () -> Void
    let close: () -> Void
    @State private var copied: Int?
    /// The problem is shown only once the user has asked to look again.
    @State private var checked: Bool
    init(problem: String?, checked: Bool = false, checkAgain: @escaping () -> Void, close: @escaping () -> Void) {
        self.problem = problem; self.checkAgain = checkAgain; self.close = close
        _checked = State(initialValue: checked)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow(text: "VALX OS / NARRATEUR")
            Text(EngineSetup.title).font(Instrument.body(26, weight: .semibold))
            Text(EngineSetup.introduction).font(Instrument.body(12)).foregroundStyle(Instrument.muted).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(EngineSetup.commands.enumerated()), id: \.offset) { index, command in
                    HStack(spacing: 10) {
                        Text("\(index + 1)").font(Instrument.mono(10)).foregroundStyle(Instrument.dim)
                        Text(command).font(Instrument.mono(11)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button(copied == index ? "Copied" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                            copied = index
                        }.buttonStyle(.plain).font(Instrument.body(11, weight: .medium)).foregroundStyle(Instrument.cyan)
                            .accessibilityLabel("Copy command \(index + 1)").accessibilityIdentifier("engine-setup-copy-\(index + 1)")
                    }.padding(.horizontal, 12).padding(.vertical, 10).background(Instrument.void)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Instrument.line, lineWidth: 1))
                }
            }
            Text(EngineSetup.homebrewNote).font(Instrument.body(11)).foregroundStyle(Instrument.muted).fixedSize(horizontal: false, vertical: true)
            Text(EngineSetup.pathNote).font(Instrument.body(11)).foregroundStyle(Instrument.muted).fixedSize(horizontal: false, vertical: true)
            Text(EngineSetup.downloadNote).font(Instrument.body(11)).foregroundStyle(Instrument.muted).fixedSize(horizontal: false, vertical: true)
            if checked, let problem {
                Label(problem == EngineSetup.notFound ? EngineSetup.stillMissing : problem, systemImage: "exclamationmark.circle").font(Instrument.body(11)).foregroundStyle(Instrument.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Later", action: close).buttonStyle(InstrumentButton()).accessibilityIdentifier("engine-setup-later")
                Spacer()
                Button("Check again") { checked = true; checkAgain() }.buttonStyle(InstrumentButton(primary: true)).keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("engine-setup-check-again")
            }
        }.padding(28).frame(width: 660).background(Instrument.base).foregroundStyle(Instrument.ghost).font(Instrument.body())
            .preferredColorScheme(.dark).tint(Instrument.cyan)
    }
}
