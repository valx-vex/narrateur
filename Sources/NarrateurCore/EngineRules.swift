import Foundation

/// What the engine (book-audio) refuses in a voice before it downloads or loads a model. The app checks the same,
/// so that a voice the engine would refuse is shown as unavailable, with the engine's reason next to it.
public enum EngineRules {
    /// The models the engine uses when a voice names none of its own.
    public static let defaultModelIDs: [VoiceModel: String] = [
        .customvoice: "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16",
        .voicedesign: "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16",
        .base: "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16",
    ]
    /// The preset voices of the default CustomVoice model.
    public static let presetSpeakers = ["serena", "vivian", "uncle_fu", "ryan", "aiden", "ono_anna", "sohee", "eric", "dylan"]
    /// The languages the default models read.
    public static let languages = ["Chinese", "English", "French", "German", "Italian", "Japanese", "Korean", "Portuguese", "Russian", "Spanish"]
}

extension EngineRules {
    /// The model the engine loads for this voice: its own `model_id`, or the default one for its kind.
    static func modelID(_ settings: VoiceSettings) -> String {
        let own = settings.modelID ?? ""
        return own.isEmpty ? defaultModelIDs[settings.model]! : own
    }
    /// Why the engine refuses this voice, in its words; nil when it does not.
    /// A model of your own has voices the engine does not know: only the default CustomVoice model's names are checked.
    public static func voiceProblem(_ settings: VoiceSettings) -> String? {
        guard let voice = settings.voice else { return nil }
        if settings.model != .customvoice {
            return "'voice' names a preset voice and only goes with model 'customvoice'; with model \(quoted(settings.model.rawValue)), remove the 'voice' line"
        }
        if modelID(settings) == defaultModelIDs[.customvoice], !presetSpeakers.contains(voice.lowercased()) {
            return "unknown preset speaker \(quoted(voice)); supported: \(presetSpeakers.sorted().joined(separator: ", "))"
        }
        return nil
    }
    /// Why the engine refuses this language for a book read with this voice, in its words; nil when it does not.
    /// The language is checked when one of the models that read the book is a default one. A described voice is
    /// then read by the default Base model, whoever invented it.
    public static func languageProblem(_ language: String, for settings: VoiceSettings) -> String? {
        var readers = [modelID(settings)]
        if settings.model == .voicedesign { readers.append(defaultModelIDs[.base]!) }
        guard readers.contains(where: { Set(defaultModelIDs.values).contains($0) }) else { return nil }
        let lowered = language.lowercased()
        if lowered == "auto" || languages.contains(where: { $0.lowercased() == lowered }) { return nil }
        return "unknown language \(quoted(language)); the speech model reads \(languages.dropLast().joined(separator: ", ")) and \(languages.last!) (or \"auto\" to let it guess)"
    }
    /// Why the engine would refuse the recording of a cloned voice when it reads book.toml, in a reader's words: the
    /// recording by its file name, then where it is (the engine says "ref_audio", its key in book.toml, which a reader
    /// of voice.toml never wrote); nil when the engine would not refuse it there. The engine then asks ffprobe whether
    /// the file is a sound that lasts. The app does not judge that: the system's own reader opens fewer formats than
    /// ffprobe (a WebM recording, for one) and would turn away a voice the engine reads. The engine says it in one
    /// line, before anything is downloaded.
    public static func recordingProblem(_ recording: URL) -> String? {
        let path = recording.path, name = recording.lastPathComponent
        var info = stat()
        guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return "The recording \(name) was not found: \(path)" }
        let handle = open(path, O_RDONLY)
        guard handle >= 0 else { return "The recording \(name) cannot be read (\(String(cString: strerror(errno)))): \(path)" }
        defer { close(handle) }
        var first: UInt8 = 0
        let count = read(handle, &first, 1)
        if count < 0 { return "The recording \(name) cannot be read (\(String(cString: strerror(errno)))): \(path)" }
        return count == 0 ? "The recording \(name) is empty: \(path)" : nil
    }
    /// A text as the engine shows it in a message (Python's repr): in single quotes, or in double quotes when it
    /// holds a single quote and no double quote.
    static func quoted(_ text: String) -> String {
        let mark = text.contains("'") && !text.contains("\"") ? "\"" : "'"
        var shown = ""
        for character in text {
            switch character {
            case "\\": shown += "\\\\"
            case "\n": shown += "\\n"
            case "\r": shown += "\\r"
            case "\t": shown += "\\t"
            case Character(mark): shown += "\\" + mark
            default: shown.append(character)
            }
        }
        return mark + shown + mark
    }
}
