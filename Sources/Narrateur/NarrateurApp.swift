import SwiftUI
import AppKit
import NarrateurCore

@main struct NarrateurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel
    init() {
        Instrument.registerFonts()
        _model = State(initialValue: AppModel())
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }
    var body: some Scene {
        Window("Narrateur", id: "main") {
            MainWindow(model: model)
                .onAppear { delegate.model = model; NSApplication.shared.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 560, height: 640)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Narrateur") { AboutPanel.show() }
            }
            CommandGroup(replacing: .newItem) {
                Button("Choose a book…", action: model.chooseBook).keyboardShortcut("o").disabled(model.active)
            }
        }
        Settings { SettingsView(model: model) }
    }
}
@MainActor enum AboutPanel {
    /// The standard panel: name, version from the bundle, then the credits with the repository as a link.
    static func show() {
        let style = NSMutableParagraphStyle()
        style.alignment = .center; style.lineSpacing = 2
        let credits = NSMutableAttributedString(string: AboutInfo.creditLines.joined(separator: "\n"), attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
        let address = (credits.string as NSString).range(of: ProjectInfo.repository)
        if address.location != NSNotFound, let url = URL(string: ProjectInfo.repository) { credits.addAttribute(.link, value: url, range: address) }
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.applicationName: AboutInfo.name, .applicationVersion: ProjectInfo.version(), .credits: credits])
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { model?.runner.shutdown() }
    /// Back from the Finder, where a voice may have been added: the narrator menu shows the folder as it is now.
    func applicationDidBecomeActive(_ notification: Notification) { model?.refreshVoices() }
    func application(_ application: NSApplication, open urls: [URL]) { if let url = urls.first { model?.openBook(url) } }
}
struct WindowBridge: NSViewRepresentable {
    let model: AppModel
    func makeNSView(context: Context) -> BridgeView { let view = BridgeView(); view.model = model; return view }
    func updateNSView(_ view: BridgeView, context: Context) { view.model = model; view.configure() }
    @MainActor final class BridgeView: NSView {
        weak var model: AppModel?
        private var configured = false
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
        func configure() {
            guard let window else { return }
            if !configured {
                configured = true
                window.title = "Narrateur"
                window.backgroundColor = NSColor(red: 12/255, green: 13/255, blue: 18/255, alpha: 1)
                window.setFrameAutosaveName("Narrateur.main")
            }
            if let directory = model?.smokeDirectory {
                window.center()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak window] in
                    guard let window else { return }
                    try? String(window.windowNumber).write(to: directory.appendingPathComponent("window-id.txt"), atomically: true, encoding: .utf8)
                    let names = ["SpaceGrotesk-Regular", "JetBrainsMono-Regular"].map { "\($0): \(NSFont(name: $0, size: 12) != nil)" }.joined(separator: "\n")
                    try? names.write(to: directory.appendingPathComponent("fonts.txt"), atomically: true, encoding: .utf8)
                }
            }
        }
    }
}
