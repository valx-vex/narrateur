import Foundation

/// Where the project lives. Each address is written once, here.
public enum ProjectInfo {
    public static let repository = "https://github.com/valx-vex/narrateur"
    public static let engineRepository = "https://github.com/valx-vex/book-audio"
    public static let license = "MIT License"
    /// The version is written once, in the bundle's Info.plist (`assets/Narrateur-Info.plist`).
    public static func version(_ info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        (info?["CFBundleShortVersionString"] as? String) ?? "development build"
    }
}
/// What the About panel says under the app's name.
public enum AboutInfo {
    public static let name = "VALX OS Narrateur"
    public static let dedication = "Finished with love for Patricia and Ocean."
    public static let creditLines = [
        "A voice for the books of the table.",
        "Built by HAL and Fable with Valentin · VALX OS",
        "Space Grotesk & JetBrains Mono · SIL OFL",
        "",
        "\(ProjectInfo.license) · free and open source",
        ProjectInfo.repository,
        "",
        dedication
    ]
}
/// What the app shows when it cannot find book-audio.
public enum EngineSetup {
    public static let title = "Engine setup"
    public static let introduction = "Narrateur reads your book with book-audio, a free engine that runs on your Mac. Install it once: open Terminal and paste these two commands, one after the other."
    /// The same two lines as the engine's own README.
    public static let commands = ["brew install ffmpeg uv", "uv tool install --python 3.12 git+\(ProjectInfo.engineRepository)"]
    public static let homebrewNote = "The first command needs Homebrew (brew.sh). If Terminal answers “command not found: brew”, install Homebrew first, then come back."
    public static let notFound = "book-audio was not found. Open \(title) to install it, or set its executable in Settings."
    /// The same failure, under the field of the Settings window where the executable is set.
    public static let notFoundInSettings = "book-audio was not found. Open \(title) to install it, or set its executable above."
    /// A problem with the engine as the Settings window says it: there, the reader is already in Settings.
    public static func inSettings(_ problem: String) -> String { problem == notFound ? notFoundInSettings : problem }
    public static let stillMissing = "Still not found. Narrateur looks for book-audio in your PATH and in ~/.local/bin. Let both commands finish in Terminal, then check again."
    /// On a new Mac, `uv tool install` ends with a warning about ~/.local/bin. The app does not need what it asks.
    public static let pathNote = "At the end of the second command, uv may warn that ~/.local/bin is not on your PATH and suggest “uv tool update-shell”. You can ignore that warning: Narrateur finds book-audio there by itself. uv tool update-shell is only needed to type book-audio in Terminal."
    public static let downloadNote = "The first render downloads the voice model from Hugging Face, about 4.5 GB (a designed voice needs two, about 9 GB). Your book is read on your Mac: its text is never sent anywhere."
}
