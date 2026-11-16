# Narrateur

Turn a Markdown book into an audiobook, on your own Mac, in one window: choose the book, choose a narrator, press Render, then listen.

Narrateur is the Mac app for [book-audio](https://github.com/valx-vex/book-audio), a free engine that reads books aloud with the open speech model Qwen3-TTS. The book is read on your Mac. There is no account to create and no cloud service, and the text of your book is never sent anywhere. The only thing fetched from the internet is the speech model itself, the first time.

You get one M4B file with chapters (it opens in Apple Books and remembers where you stopped) and one MP3 per chapter.

## What you need

- A Mac with Apple Silicon (M1 or later).
- macOS 14 or later.
- About 10 GB of free disk space. Each speech model is about 4.5 GB, and one kind of voice needs two of them.
- [Homebrew](https://brew.sh), to install the engine.

## The quick way: one line

Open **Terminal** (in Applications, then Utilities), paste this line, and press Return:

    curl -fsSL https://raw.githubusercontent.com/valx-vex/narrateur/main/install.sh | bash

It checks your Mac, installs what is missing (Homebrew, ffmpeg, uv, the engine), puts Narrateur in the Applications folder of your home, downloads the reading voice once (about 4.5 GB), and opens the app. If macOS asks for your password, it is for Homebrew: type it and press Return (nothing shows while you type). Running it again is safe. To see exactly what it does before you run it, read [install.sh](install.sh).

If you prefer to do each step yourself, read on.

## 1. Download the app and open it

1. Download `Narrateur-<version>-macos-arm64.zip` from the [releases page](https://github.com/valx-vex/narrateur/releases) and double-click it to unzip.
2. Move `Narrateur.app` into your Applications folder.
3. Open it. The first time, macOS stops you. Narrateur is free and open source, and it is not notarized by Apple, which requires a paid developer account. You tell macOS once that you want it:
   - **macOS 15 or later.** Double-click the app. macOS says it could not verify it: click **Done**. Open **System Settings**, go to **Privacy & Security**, scroll down to the line about Narrateur and click **Open Anyway**, then confirm.
   - **macOS 14.** Right-click the app (or Control-click it), choose **Open**, then **Open** again in the dialog.

After that first time, it opens like any other app.

To check your download, compare the result of `shasum -a 256 Narrateur-<version>-macos-arm64.zip` with the SHA-256 published next to the file.

## 2. Install the engine

The app shows an **Engine setup** sheet as long as it cannot find the engine. Open Terminal and paste these two lines, one after the other:

```bash
brew install ffmpeg uv
uv tool install --python 3.12 git+https://github.com/valx-vex/book-audio
```

Then click **Check again** in the app.

The first line needs Homebrew. The second gives you the `book-audio` command, in `~/.local/bin`, with the Python packages it needs. Narrateur looks there by itself. At the end, uv may warn that `~/.local/bin` is not on your PATH and suggest `uv tool update-shell`: you can ignore that warning, the app finds the engine all the same. `uv tool update-shell` is only needed to type `book-audio` in Terminal.

If you are curious, `book-audio doctor` tells you whether the machine is ready; it only looks, and downloads nothing. If Terminal answers `command not found: book-audio`, run `uv tool update-shell`, then open a new Terminal window and try again: on a new Mac, Terminal does not look in `~/.local/bin` until you have done this once. The app does not need it.

## 3. Your first audiobook

The engine comes with a small example: two short fables.

1. Get it. In Terminal: `git clone https://github.com/valx-vex/book-audio`. You now have a `book-audio` folder in your home folder.
2. In Narrateur, click **Choose a book** and pick `book-audio/examples/two-fables/fables.md`. You can also drop the file on the window. Its two chapters appear.
3. Keep the narrator **Ryan** for this first try: it needs one speech model, where **Warm narrator** needs two.
4. Press **Render**. The first time, the engine downloads the speech model from Hugging Face, about 4.5 GB, without any account. During the download the window shows no progress: click **Log** at the bottom to watch it. Then the chapters are checked off one by one.
5. When the window says **Ready to listen**, press **Play**, or **Open in Finder**. The audiobook is `fables.audiobook/audio/Two Fables.m4b`, next to `fables.md`.

You can press **Cancel** during a render and come back later: every sentence already read is kept.

## Your own book

A book is one Markdown file (`.md`). Each chapter starts with a heading such as:

```markdown
# Chapter 1 — The North Wind and the Sun
```

That is `# Chapter `, then a number, then, if the chapter has a title, a dash, a colon or a full stop and the title. `# Chapter 1 - Title`, `# Chapter 1: Title`, `# Chapter 1. Title` and a bare `# Chapter 11` are all read. A full stop needs a space after it: `# Chapter 1.5 Title` is not a chapter. Two chapters cannot have the same number (`01` is `1`); a `# Chapter 0` is fine, for a prologue. Everything before the first chapter heading is the title page and is not read aloud; the first `# ` line there gives the book its title. A picture with the same name as the book (`My Book.png`), or a `cover.png` in the same folder, becomes the cover.

Narrateur never changes your Markdown file. It creates a folder next to it, `My Book.audiobook/`, which holds the settings of the book (`book.toml`), the audio and a log. If you already wrote a `book.toml` yourself, you can open that file instead of the Markdown.

You can change the title and the author in the window: press Return to save. If you change the narrator after some chapters are rendered, they have to be read again; the app asks before it does.

The engine's README explains [how a book is read](https://github.com/valx-vex/book-audio#how-a-book-is-read) and how long it takes.

## Voices

The first time Narrateur finds its voices folder empty, it writes two starter voices there. Neither needs a recording.

- **Ryan** (`narrator-ryan`): one of the nine voices that come with the model. One model to download.
- **Warm narrator** (`narrator-warm`): a voice the model invents from a written description. Two models to download (about 9 GB): one invents the voice, one reads the book with it.

Your voices live in `~/Library/Application Support/Narrateur/Voices`. A voice is a folder with a `voice.toml` file in it, and there are three kinds.

**A preset voice.** The nine names are `serena`, `vivian`, `uncle_fu`, `ryan`, `aiden`, `ono_anna`, `sohee`, `eric` and `dylan`. An optional `description` line sets the style of the reading.

```toml
name = "Serena"
owner = "me"
language = "English"
model = "customvoice"
voice = "serena"
```

**A voice described in words.** You write what the narrator sounds like, and the model invents the voice.

```toml
name = "Old sailor"
owner = "me"
language = "English"
model = "voicedesign"
description = "An old man with a low, rough voice, telling a story slowly by the fire."
```

**A voice cloned from a recording.** Put a short, clean recording named `reference.wav` (about fifteen seconds) in the folder, and the exact words spoken in it in `reference.txt`. Only clone a voice you have the right to use: your own, or one whose owner agreed.

```toml
name = "My voice"
owner = "me"
language = "English"
model = "base"
```

Narrateur looks for these two names in the voice's folder. To use others, add `reference = "take-2.wav"` and `transcript = "take-2.txt"` lines. A `ref_audio` or `ref_text` line, the way the engine's `book.toml` names them, is not read in `voice.toml`: the voice then waits for its `reference.wav`, and says so next to its name.

`owner`, `language` and `model` are required; `name` is the folder's name if you leave it out. A voice with something missing stays in the list, with the reason next to it. The easiest way to add a voice is to copy a starter folder, rename it and edit its `voice.toml`. Narrateur reads the folder again each time you come back to it from another app (after adding a voice in the Finder, for example), when it starts, and when you press **Apply** in Settings.

`language` is one of the ten the speech model reads: `Chinese`, `English`, `French`, `German`, `Italian`, `Japanese`, `Korean`, `Portuguese`, `Russian` and `Spanish`, in capitals or not, or `auto` to let the model guess. A `voice` line names a preset voice and only goes with `model = "customvoice"`: if you copy the Ryan folder to make a described or a cloned voice, remove that line. A voice the engine would refuse stays in the list, unavailable, with the engine's reason next to it. A new book takes the language of its narrator; if a book carries a language the engine does not read, choosing another narrator gives the book that narrator's language.

## Settings

`⌘,` opens the settings.

- **Engine.** Narrateur looks for `book-audio` in your `PATH`, then in `~/.local/bin`. To use another copy, give the path of its executable here.
- **Voices folder.** Where your voices are kept: a folder that already exists (the **Choose…** button opens a panel on the folder in use, where you can also make a new one). If the folder holds no voice, the two starter voices are written there. If the field is empty, or does not name an existing folder, Narrateur uses its own folder, `~/Library/Application Support/Narrateur/Voices`, and says so under the field once you press **Apply**. If the field names a single voice, a folder with its own `voice.toml` (easy to pick by mistake in that panel), Narrateur uses the folder that holds it and says so too: nothing is written into a voice. It never creates a folder from what is typed.
- **Default author.** The name written in new books. It starts as the full name of your Mac account.

## When something goes wrong

- **macOS refuses to open the app.** See step 1: it has to be allowed once.
- **The Engine setup sheet keeps coming back.** Let both commands finish in Terminal, then click **Check again**. The file `~/.local/bin/book-audio` should now exist. In Terminal, `~/.local/bin/book-audio doctor` says what is missing.
- **Terminal answers `command not found: book-audio`.** The engine is installed, but Terminal does not look in `~/.local/bin` yet. Run `uv tool update-shell`, then open a new Terminal window. You can also type the whole path: `~/.local/bin/book-audio doctor`.
- **Nothing seems to move during the first render.** The speech model is downloading. Click **Log**.
- **"Needs attention".** Click **Log**: the last line that starts with `book-audio:` says what happened. The engine's README lists these messages under [When something goes wrong](https://github.com/valx-vex/book-audio#when-something-goes-wrong).
- **"No chapters found".** The book needs headings like `# Chapter 1 — Title`, with a number.
- **"Cannot read the chapter heading".** After `# Chapter ` the heading needs a number written in digits, then a dash, a colon or a full stop and a space before the title: `# Chapter 3 — Title`, not `# Chapter Three`, not `# Chapter 3 Title` and not `# Chapter 1.5 Title`.
- **"Chapter 3 appears twice".** Two headings carry the same number. Give each chapter its own.
- **You need the disk space back.** `book-audio doctor` shows where the speech models are stored. They can be deleted, and are downloaded again when a voice needs them.

## Building from the sources

You need Apple's Command Line Tools with Swift 6 (`xcode-select --install`). Xcode itself is not needed, and there is no Xcode project.

```bash
git clone https://github.com/valx-vex/narrateur
cd narrateur
scripts/test.sh        # the tests
scripts/release.sh     # builds build/release/Narrateur-<version>-macos-arm64.zip and its SHA-256; installs nothing
scripts/build-app.sh   # builds the app and installs it in ~/Applications
```

`scripts/test.sh` and the build scripts read `scripts/swift-env.sh`, which points at the Command Line Tools. The version number is written once, in `assets/Narrateur-Info.plist`. The app is signed ad hoc; it is not notarized.

To run the app against a checkout of the engine instead of an installed one, start it with `BOOK_AUDIO_PROJECT` set to that folder (this needs `uv`):

```bash
BOOK_AUDIO_PROJECT=/path/to/book-audio build/release/Narrateur.app/Contents/MacOS/Narrateur
```

`Sources/NarrateurCore` holds everything that can be tested without a window: book settings, chapters, voices, progress read from the disk, the search for the engine, and the runner that starts one engine process at a time and can cancel it. `Sources/Narrateur` holds the window.

## License and credits

MIT, see [LICENSE](LICENSE). Copyright (c) 2026 Valentin Passera and the valx table.

The app carries two typefaces, Space Grotesk and JetBrains Mono, under the SIL Open Font License. It does not include the engine, the speech models or ffmpeg; each comes with its own license. All of this is listed in [THIRD_PARTY.md](THIRD_PARTY.md).

Finished with love for Patricia and Ocean.
