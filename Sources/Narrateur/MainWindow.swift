import SwiftUI
import AppKit
import NarrateurCore

struct MainWindow: View {
    @Bindable var model: AppModel
    @State private var targeted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            bookCard
            voiceCard
            chapters
            actions
        }
        .padding(24)
        .frame(minWidth: 500, idealWidth: 560, minHeight: 600, idealHeight: 640)
        .background(Instrument.base)
        .foregroundStyle(Instrument.ghost)
        .font(Instrument.body())
        .preferredColorScheme(.dark)
        .tint(Instrument.cyan)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(targeted ? Instrument.cyan : .clear, lineWidth: 2).padding(4))
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, !model.active else { return false }
            model.openBook(url); return true
        } isTargeted: { targeted = $0 }
        .background(WindowBridge(model: model))
        .onChange(of: model.runner.state) { _, _ in model.jobChanged() }
        .sheet(isPresented: $model.showEngineSetup) {
            EngineSetupSheet(problem: model.engineProblem, checkAgain: model.recheckEngine) { model.showEngineSetup = false }
        }
        .task { model.bootstrap() }
    }
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Circle().fill(Instrument.cyan).frame(width: 5, height: 5)
                    Eyebrow(text: "VALX OS / AUDIO")
                }
                Text("Narrateur").font(Instrument.body(34, weight: .semibold)).tracking(-1)
                Text("Your words. A voice. Time to listen.").foregroundStyle(Instrument.muted).font(Instrument.body(12))
            }
            Spacer()
            Image(systemName: "waveform").font(.system(size: 28, weight: .ultraLight)).foregroundStyle(Instrument.cyan)
                .frame(width: 52, height: 52).background(Instrument.surface)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Instrument.line))
                .accessibilityHidden(true)
        }
    }
    private var bookCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Eyebrow(text: "01 / THE BOOK")
                Spacer()
                if model.book != nil {
                    Button("Change…", action: model.chooseBook).buttonStyle(.plain).foregroundStyle(Instrument.cyan).font(Instrument.body(11)).disabled(model.active)
                }
            }
            if let book = model.book {
                HStack(alignment: .top, spacing: 14) {
                    cover(book)
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Book title", text: $model.title).font(Instrument.body(18, weight: .medium)).textFieldStyle(.plain)
                            .accessibilityLabel("Book title").onSubmit { model.saveMetadata() }
                        TextField("Author", text: $model.author).font(Instrument.body(11)).foregroundStyle(Instrument.muted).textFieldStyle(.plain)
                            .accessibilityLabel("Author").onSubmit { model.saveMetadata() }
                        Text(book.sourceURL.lastPathComponent).font(Instrument.mono(9)).foregroundStyle(Instrument.dim).lineLimit(1).truncationMode(.middle).help(book.sourceURL.path)
                    }.disabled(model.active || model.isPreview)
                }
            } else {
                HStack(spacing: 16) {
                    Image(systemName: "book.closed").font(.system(size: 28, weight: .light)).foregroundStyle(Instrument.cyan).frame(width: 44)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("A book waiting to be heard.").font(Instrument.body(16, weight: .medium))
                        Text("Drop a Markdown file here, or choose one.").foregroundStyle(Instrument.muted).font(Instrument.body(11))
                    }
                    Spacer(minLength: 0)
                }.padding(.vertical, 4)
                Button(action: model.chooseBook) { Label("Choose a book", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(InstrumentButton())
            }
        }.modifier(SteelPanel(accent: model.book == nil || targeted))
    }
    @ViewBuilder private func cover(_ book: BookDocument) -> some View {
        if let url = book.coverURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFill().frame(width: 48, height: 65).clipped().clipShape(RoundedRectangle(cornerRadius: 2))
        } else {
            Image(systemName: "book.closed").font(.system(size: 23, weight: .ultraLight)).foregroundStyle(Instrument.cyan)
                .frame(width: 48, height: 65).background(Instrument.raised).overlay(Rectangle().stroke(Instrument.line))
        }
    }
    private var voiceCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.circle").font(.system(size: 25, weight: .light)).foregroundStyle(Instrument.cyan)
            VStack(alignment: .leading, spacing: 5) {
                Eyebrow(text: "02 / THE NARRATOR")
                Text(model.voiceName).font(Instrument.body(14, weight: .medium)).lineLimit(1)
                Text(model.voiceDetail).font(Instrument.body(10)).foregroundStyle(Instrument.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            Menu {
                if model.voices.isEmpty { Text("No voices found — open Settings") }
                ForEach(model.voices) { voice in
                    Button {
                        model.selectVoice(voice)
                    } label: {
                        Text(voice.name + " · " + voice.owner + (voice.unavailableReason.map { " — " + $0 } ?? ""))
                    }.disabled(voice.unavailableReason != nil)
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Change").font(Instrument.body(11, weight: .medium))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
                }.foregroundStyle(Instrument.cyan)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(model.active || model.isPreview)
        }.modifier(SteelPanel())
    }
    private var chapters: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(text: "03 / CHAPTERS")
                Spacer()
                Text(model.book == nil ? "—" : "\(model.progress.completedCount) / \(model.book!.chapters.count)")
                    .font(Instrument.mono(10)).foregroundStyle(Instrument.cyan)
            }
            if model.progress.items.isEmpty {
                VStack(spacing: 8) {
                    Text(model.book == nil ? "The next chapter starts here." : "No chapters found.").font(Instrument.body(13))
                    Text(model.book == nil ? "Choose a book to see its chapters." : "Use headings such as # Chapter 1 — Title.")
                        .font(Instrument.body(11)).foregroundStyle(Instrument.muted)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.progress.items) { item in chapterRow(item) }
                    }
                }.scrollIndicators(.automatic)
            }
            if model.active {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text("\(model.progress.cachedUnits) clips saved · \(model.status.lowercased())").font(Instrument.mono(9)).foregroundStyle(Instrument.muted)
                }
            }
        }.frame(minHeight: 110, maxHeight: .infinity)
    }
    private func chapterRow(_ item: JobItem) -> some View {
        let current = model.active && model.progress.items.first(where: { !$0.complete })?.id == item.id
        return HStack(spacing: 10) {
            Text(String(format: "%02d", Int(item.id) ?? 0)).font(Instrument.mono(10)).foregroundStyle(Instrument.dim).frame(width: 22)
            Text(item.title).font(Instrument.body(12)).lineLimit(1).help(item.title)
            Spacer(minLength: 8)
            if item.warnings > 0 { Label("\(item.warnings)", systemImage: "exclamationmark.triangle").font(Instrument.mono(9)).foregroundStyle(.orange).help("\(item.warnings) warnings in the chapter report") }
            if let duration = item.duration { Text(durationText(duration)).font(Instrument.mono(9)).foregroundStyle(Instrument.muted) }
            Image(systemName: item.complete ? "checkmark.circle.fill" : "circle").font(.system(size: 12)).foregroundStyle(item.complete || current ? Instrument.cyan : Instrument.dim)
        }.padding(.horizontal, 8).padding(.vertical, 9)
            .background(current ? Instrument.cyan.opacity(0.07) : .clear)
            .overlay(alignment: .bottom) { Rectangle().fill(Instrument.line).frame(height: 1) }
            .accessibilityElement(children: .combine)
            .accessibilityValue(item.complete ? "Complete" : "Waiting")
    }
    private func durationText(_ seconds: Double) -> String { String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let message = model.error {
                Label(message, systemImage: "exclamationmark.circle").font(Instrument.body(11)).foregroundStyle(Instrument.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            if model.result != nil {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ready to listen.").font(Instrument.body(15, weight: .medium))
                        Text("\(model.progress.completedCount) chapters · M4B").font(Instrument.mono(9)).foregroundStyle(Instrument.muted)
                    }
                    Spacer()
                    Button("Open in Finder", action: model.reveal).buttonStyle(InstrumentButton())
                    Button(action: model.play) { Label("Play", systemImage: "play.fill") }.buttonStyle(InstrumentButton(primary: true))
                }
            } else {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.status).font(Instrument.body(12, weight: .medium))
                        Text(model.active ? "You can stop and resume later." : (model.disabledReason ?? "One voice. Every chapter.")).font(Instrument.body(10)).foregroundStyle(Instrument.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if model.active {
                        Button("Cancel", action: model.runner.cancel).buttonStyle(InstrumentButton()).disabled(model.runner.state == .cancelling)
                    } else {
                        Button(action: model.render) { Label("Render", systemImage: "waveform") }.buttonStyle(InstrumentButton(primary: true)).disabled(model.disabledReason != nil || model.isPreview)
                    }
                }
            }
            HStack {
                Text("ON YOUR MAC").font(Instrument.mono(8)).tracking(1.4).foregroundStyle(Instrument.dim)
                Spacer()
                if model.result != nil { Button("Render again", action: model.render).font(Instrument.body(10)).buttonStyle(.plain).disabled(model.disabledReason != nil || model.isPreview) }
                if model.engine == nil && !model.isPreview {
                    Button(EngineSetup.title) { model.showEngineSetup = true }.font(Instrument.body(10)).buttonStyle(.plain).foregroundStyle(Instrument.cyan)
                }
                Button(model.showLog ? "Hide log" : "Log") { model.showLog.toggle() }.font(Instrument.body(10)).buttonStyle(.plain)
                SettingsLink { Image(systemName: "slider.horizontal.3").font(.system(size: 12)) }.buttonStyle(.plain).help("Settings · ⌘,")
            }.foregroundStyle(Instrument.muted)
            if let note = model.notificationNote { Text(note).font(Instrument.body(10)).foregroundStyle(Instrument.muted) }
            if model.showLog {
                ScrollView { Text(model.log.isEmpty ? "No log yet." : model.log).font(Instrument.mono(9)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(height: 90).padding(10).background(Instrument.void)
                if !model.jobs.isEmpty {
                    ForEach(model.jobs.suffix(3)) { job in Text("\(job.title) · \(job.state.label)").font(Instrument.body(10)).foregroundStyle(Instrument.muted) }
                }
            }
        }.padding(.top, 12).overlay(alignment: .top) { Rectangle().fill(Instrument.line).frame(height: 1) }
    }
}
