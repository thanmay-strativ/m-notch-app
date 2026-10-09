#!/bin/sh
# Installs or updates m_notch from the latest GitHub release. Paste into Terminal:
#   curl -fsSL https://raw.githubusercontent.com/thanmay-strativ/m-notch-app/main/install.sh | sh
# It downloads m_notch.zip and its SHA-256, checks them, puts m_notch.app in /Applications and opens it.
# Files that curl downloads are not quarantined, so macOS does not ask you to "Open Anyway".
set -eu

base=https://github.com/thanmay-strativ/m-notch-app/releases/latest/download
target=/Applications/m_notch.app

if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
    echo "m_notch needs a Mac with Apple silicon (M1 or newer). This one is $(uname -s) $(uname -m)." >&2
    exit 1
fi
macos=$(sw_vers -productVersion)
if [ "${macos%%.*}" -lt 15 ]; then
    echo "m_notch needs macOS 15 or newer. This Mac has macOS $macos." >&2
    exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
echo "Downloading the latest m_notch..."
curl -fsSL -o "$work/m_notch.zip" "$base/m_notch.zip"
curl -fsSL -o "$work/m_notch.zip.sha256" "$base/m_notch.zip.sha256"
if ! (cd "$work" && shasum -a 256 -c m_notch.zip.sha256 >/dev/null); then
    echo "The download does not match its SHA-256 ($(cat "$work/m_notch.zip.sha256")). Nothing was installed." >&2
    exit 1
fi
ditto -x -k "$work/m_notch.zip" "$work/unzipped"

if pgrep -x m_notch >/dev/null; then
    echo "Quitting the running m_notch..."
    pkill -x m_notch
    sleep 1
fi
if ! { rm -rf "$target" && ditto "$work/unzipped/m_notch.app" "$target"; }; then
    echo "Could not write $target. Ask an administrator of this Mac to run the command, or drag m_notch.app into Applications yourself." >&2
    exit 1
fi
open "$target"
echo "Installed m_notch $(defaults read "$target/Contents/Info" CFBundleShortVersionString) in Applications."
echo "Look for its icon in the menu bar. It will ask once to connect Claude Code."
