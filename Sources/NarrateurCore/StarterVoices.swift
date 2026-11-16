import Foundation

/// Two voices written into an empty voices folder, so a first launch can read a book at once.
/// Neither needs an audio file: one is a preset speaker of the model, the other is designed from its description.
public enum StarterVoices {
    public static let presetID = "narrator-ryan"
    public static let designedID = "narrator-warm"
    public static let designedDescription = "A woman in her forties reading an audiobook: a warm, low, unhurried voice with clear diction and a smile in it. Calm and close to the listener, never theatrical."
    static let manifests: [(id: String, text: String)] = [
        (presetID, """
        # A starter voice written by Narrateur. Edit it, copy it, or delete this folder.
        # Other preset speakers: serena, vivian, uncle_fu, aiden, ono_anna, sohee, eric, dylan.
        name = "Ryan"
        owner = "Narrateur"
        language = "English"
        model = "customvoice"
        voice = "ryan"
        origin = "A preset speaker of the Qwen3-TTS CustomVoice model."

        """),
        (designedID, """
        # A starter voice written by Narrateur. Change the description to design another voice.
        name = "Warm narrator"
        owner = "Narrateur"
        language = "English"
        model = "voicedesign"
        description = \(BookTOML.quote(designedDescription))
        origin = "Designed from its description by the Qwen3-TTS VoiceDesign model."

        """)
    ]
    /// Writes the starter voices when `folder` is missing or holds no voice at all, and returns the ids written.
    /// Nothing that exists is ever replaced, so calling it again changes nothing.
    @discardableResult public static func installIfNeeded(in folder: URL) throws -> [String] {
        let files = FileManager.default
        guard VoiceLibrary.load(from: folder).isEmpty else { return [] }
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        var written: [String] = []
        for (id, text) in manifests {
            let home = folder.appendingPathComponent(id), manifest = home.appendingPathComponent("voice.toml")
            var isDirectory: ObjCBool = false
            if files.fileExists(atPath: home.path, isDirectory: &isDirectory) {
                guard isDirectory.boolValue, !files.fileExists(atPath: manifest.path) else { continue }
            } else {
                try files.createDirectory(at: home, withIntermediateDirectories: false)
            }
            try Data(text.utf8).write(to: manifest, options: .withoutOverwriting)
            written.append(id)
        }
        return written
    }
}
