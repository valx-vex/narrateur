#!/usr/bin/env bash
# Narrateur: one-line installer for macOS on Apple Silicon.
#
#   curl -fsSL https://raw.githubusercontent.com/valx-vex/narrateur/main/install.sh | bash
#
# What it does, in order, and only what is missing:
#   1. checks this Mac (Apple Silicon, macOS 14 or later, about 10 GB free);
#   2. installs Homebrew if it is not there (macOS asks for your password once);
#   3. installs ffmpeg and uv with Homebrew;
#   4. installs the book-audio engine from GitHub, in your home folder;
#   5. downloads Narrateur, checks it against the published checksum, and puts it in ~/Applications;
#   6. downloads the reading voice now (about 4.5 GB, once), so your first Render does not wait;
#   7. opens Narrateur.
# Running it again is safe: it updates what is there and keeps your books and voices.
# Options: NARRATEUR_SKIP_VOICE=1 (leave the voice for the first Render), NARRATEUR_NO_OPEN=1 (do not open the app).
set -euo pipefail
{ # read the whole script before running it: a command that reads stdin cannot cut it short under curl | bash

APP_VERSION="1.0.0"
APP_ZIP="Narrateur-${APP_VERSION}-macos-arm64.zip"
APP_URL="https://github.com/valx-vex/narrateur/releases/download/v${APP_VERSION}/${APP_ZIP}"
APP_SHA256="ebe876511f13ac7acf4243f86daf039789821e9bf8a7d35c37ed90fa1f4316ce"
ENGINE_URL="git+https://github.com/valx-vex/book-audio"
VOICE_MODEL="mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16"
APPS_DIR="$HOME/Applications"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok() { printf '    %s\n' "$*"; }
fail() { printf '\n\033[1mSorry:\033[0m %s\n' "$*" >&2; exit 1; }

step "1/7  Checking this Mac"
[ "$(uname -s)" = "Darwin" ] || fail "Narrateur runs on macOS only."
[ "$(uname -m)" = "arm64" ] || fail "Narrateur needs a Mac with Apple Silicon (M1 or later)."
version="$(sw_vers -productVersion)"; major="${version%%.*}"
[ "${major:-0}" -ge 14 ] || fail "Narrateur needs macOS 14 or later (this Mac has ${version})."
free_gb="$(df -g "$HOME" | awk 'NR==2 {print $4}')"
[ "${free_gb:-0}" -ge 10 ] || fail "Narrateur needs about 10 GB of free space (this Mac has ${free_gb} GB)."
ok "Apple Silicon, macOS ${version}, ${free_gb} GB free."

step "2/7  Homebrew"
if [ -x /opt/homebrew/bin/brew ]; then
  ok "Already here."
else
  ok "Installing Homebrew. If macOS asks for your password, type it and press Return (nothing shows while you type)."
  if [ -r /dev/tty ]; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/tty
  else
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  [ -x /opt/homebrew/bin/brew ] || fail "Homebrew did not install. See https://brew.sh, then run this line again."
fi
eval "$(/opt/homebrew/bin/brew shellenv)"

step "3/7  ffmpeg and uv"
for formula in ffmpeg uv; do
  if brew list --formula "$formula" >/dev/null 2>&1; then ok "${formula}: already here."; else brew install "$formula"; fi
done

step "4/7  The book-audio engine"
uv tool install --force --python 3.12 "$ENGINE_URL"
[ -x "$HOME/.local/bin/book-audio" ] || fail "The engine did not install in ~/.local/bin."
ok "Installed in ~/.local/bin/book-audio. Narrateur finds it there; you can ignore any note about your PATH."

step "5/7  Narrateur ${APP_VERSION}"
work="$(mktemp -d)"
curl -fL --progress-bar -o "${work}/${APP_ZIP}" "$APP_URL"
got="$(shasum -a 256 "${work}/${APP_ZIP}" | cut -d' ' -f1)"
[ "$got" = "$APP_SHA256" ] || fail "The download does not match the published app (checksum ${got}). Nothing was installed."
ditto -x -k "${work}/${APP_ZIP}" "${work}/unzipped"
[ -d "${work}/unzipped/Narrateur.app" ] || fail "The download did not contain Narrateur.app."
mkdir -p "$APPS_DIR"
if [ -d "${APPS_DIR}/Narrateur.app" ]; then
  mv "${APPS_DIR}/Narrateur.app" "${HOME}/.Trash/Narrateur (replaced $(date '+%Y-%m-%d %H.%M.%S')).app"
  ok "The previous Narrateur went to the Trash."
fi
ditto "${work}/unzipped/Narrateur.app" "${APPS_DIR}/Narrateur.app"
ok "Installed: ${APPS_DIR}/Narrateur.app (the temporary download stays in the system's temporary folder, which macOS empties by itself)."

step "6/7  The reading voice (about 4.5 GB, once)"
if [ "${NARRATEUR_SKIP_VOICE:-0}" = "1" ]; then
  ok "Skipped. Narrateur downloads it at your first Render."
else
  py="${HOME}/.local/share/uv/tools/book-audio/bin/python"
  [ -x "$py" ] || fail "The engine's Python is missing; run this line again."
  ok "Downloading ${VOICE_MODEL}. It can take a while; the bars show the progress."
  "$py" -c 'import sys; from huggingface_hub import snapshot_download; snapshot_download(sys.argv[1])' "$VOICE_MODEL" \
    || fail "The voice download stopped. Run this line again: it picks up where it stopped."
  ok "The voice is ready."
fi

step "7/7  Opening Narrateur"
if [ "${NARRATEUR_NO_OPEN:-0}" = "1" ]; then ok "Not opened (NARRATEUR_NO_OPEN=1)."; else open "${APPS_DIR}/Narrateur.app"; fi
printf '\nDone. Narrateur is in %s. Choose a Markdown book, choose a narrator, press Render.\n' "$APPS_DIR"
}
