# Third-party fonts, software and models

Narrateur is released under the MIT license (see `LICENSE`). This file lists what is not ours: what travels inside the app, and what the app relies on without including it.

## Inside the app

Two typefaces, each under the SIL Open Font License, Version 1.1. Their license texts are in `assets/Fonts/` and are copied into the app next to the fonts (`Narrateur.app/Contents/Resources/Fonts/`).

| font | copyright | license text |
|---|---|---|
| Space Grotesk | Copyright 2020 The Space Grotesk Project Authors (https://github.com/floriankarsten/space-grotesk) | `assets/Fonts/SpaceGrotesk-OFL.txt` |
| JetBrains Mono | Copyright 2020 The JetBrains Mono Project Authors (https://github.com/JetBrains/JetBrainsMono) | `assets/Fonts/JetBrainsMono-OFL.txt` |

Nothing else from a third party is inside the app. It is written with Apple's SwiftUI and AppKit and has no package dependency.

## Not inside the app

Each of these is installed or downloaded on your Mac, under its own license.

**book-audio, the engine.** MIT license, same authors: https://github.com/valx-vex/book-audio. You install it yourself, and Narrateur runs it as a separate program. Its own `THIRD_PARTY.md` lists the Python packages it depends on, mlx-audio among them.

**The speech models.** The engine reads with Qwen3-TTS 1.7B, converted for MLX by the mlx-community organisation on Hugging Face:

- `mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16`
- `mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16`
- `mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16`

License: Apache-2.0, as stated on their Hugging Face pages. The models are not part of this repository or of the app, and neither redistributes them. The first time a voice needs one, the engine downloads it from Hugging Face into your local Hugging Face cache (about 4.5 GB each).

The starter voice `narrator-ryan` uses `ryan`, one of the preset speakers that come with the CustomVoice model. The starter voice `narrator-warm` holds only a description written for this app; the VoiceDesign model invents the voice from it on your Mac.

**ffmpeg.** The engine calls the `ffmpeg` and `ffprobe` programs that you install yourself (for example with `brew install ffmpeg`). They are external tools, not included here. FFmpeg is licensed under the LGPL or the GPL depending on how your copy was built: see https://ffmpeg.org/legal.html.
