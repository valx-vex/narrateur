import SwiftUI
import AppKit
import NarrateurCore

struct SettingsView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Eyebrow(text: "VALX OS / NARRATEUR")
            Text("Settings").font(Instrument.body(26, weight: .semibold))
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "ENGINE")
                TextField("Automatic — executable path override", text: $model.preferences.engineOverride).textFieldStyle(.roundedBorder)
                    .onSubmit { model.savePreferences() }
                Text(model.engine?.display ?? model.engineProblem.map(EngineSetup.inSettings) ?? "Not found").font(Instrument.mono(10)).foregroundStyle(model.engine == nil ? Instrument.red : Instrument.muted).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Text("Leave empty to find book-audio automatically.").font(Instrument.body(11)).foregroundStyle(Instrument.muted)
            }
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "VOICES FOLDER")
                HStack {
                    TextField("Voices folder", text: $model.preferences.voicesFolder).textFieldStyle(.roundedBorder).onSubmit { model.savePreferences() }
                    Button("Choose…") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
                        panel.canCreateDirectories = true   // Narrateur never creates a folder from what is typed in the field
                        panel.directoryURL = model.voicesFolderURL   // the folder whose voices are counted below, not the last one shown
                        if panel.runModal() == .OK, let url = panel.url { model.preferences.voicesFolder = url.path; model.savePreferences() }
                    }
                }
                Text("\(model.voices.filter { $0.unavailableReason == nil }.count) available voices").font(Instrument.mono(10)).foregroundStyle(Instrument.muted)
                if let note = model.voicesFolderNote { Text(note).font(Instrument.body(11)).foregroundStyle(Instrument.muted).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "DEFAULT AUTHOR")
                TextField("Author", text: $model.preferences.author).textFieldStyle(.roundedBorder).onSubmit { model.savePreferences() }
            }
            HStack { Spacer(); Button("Apply", action: model.savePreferences).buttonStyle(InstrumentButton(primary: true)) }
            if model.active { Text("Settings are locked while a job is running.").font(Instrument.body(11)).foregroundStyle(Instrument.muted) }
        }.padding(28).frame(width: 480).background(Instrument.base).foregroundStyle(Instrument.ghost).font(Instrument.body())
            .preferredColorScheme(.dark).tint(Instrument.cyan).disabled(model.active)
            .onDisappear { if !model.active { model.savePreferences() } }
    }
}
