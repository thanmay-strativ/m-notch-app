#!/bin/sh
# Usage: scripts/dev.sh test   run the unit tests
#        scripts/dev.sh build  build build/m_notch.app and sign it locally (scripts/release.sh uses this)
#        scripts/dev.sh app    build, then (re)launch it
set -eu
cd "$(dirname "$0")/.."

# The macOS 27 SDK turns SwiftUI's @State into a macro whose plugin ships only with full Xcode.
# Without Xcode, build against the macOS 26 SDK that the Command Line Tools also install.
if ! xcodebuild -version >/dev/null 2>&1 && [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk ]; then
    export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
fi

app=build/m_notch.app

build_app() {
    version=$(cat VERSION)
    swift build -c release
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS"
    cp .build/release/MNotch "$app/Contents/MacOS/m_notch"
    mkdir -p "$app/Contents/Resources"
    clang -fobjc-arc -O2 -dynamiclib -framework Foundation Adapters/NowPlayingAdapter.m \
        -o "$app/Contents/Resources/NowPlayingAdapter.dylib"
    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.mnotch</string>
    <key>CFBundleName</key><string>m_notch</string>
    <key>CFBundleExecutable</key><string>m_notch</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSCalendarsFullAccessUsageDescription</key><string>m_notch shows your next meeting in the notch, with a Join button for its video link.</string>
</dict>
</plist>
PLIST
    codesign --force --sign - "$app"
    echo "Built $app $version"
}

case "${1:-}" in
test)
    plugins=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
    if [ -d "$plugins" ]; then
        swift test --scratch-path .build/tests -Xswiftc -plugin-path -Xswiftc "$plugins"
    else
        swift test --scratch-path .build/tests
    fi
    ;;
build)
    build_app
    ;;
app)
    build_app
    pkill -x m_notch || true
    open "$app"
    echo "Launched $app"
    ;;
*)
    echo "Usage: scripts/dev.sh test|build|app" >&2
    exit 64
    ;;
esac
