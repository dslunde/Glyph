#!/bin/bash

# 🚀 Glyph App Bundle Builder
# This script creates a proper macOS .app bundle with custom icon

set -e  # Exit on any error

echo "🔨 Building Glyph macOS App Bundle..."

# Configuration
APP_NAME="Glyph"
BUNDLE_ID="com.glyph.knowledge-graph-explorer"
VERSION="1.0"
BUILD_DIR=".build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

# Clean and create directories
echo "🧹 Cleaning build directory..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/"{MacOS,Resources}

# Build the Swift executable
echo "⚙️  Building Swift executable..."
swift build -c release

# Copy executable
echo "📦 Copying executable..."
cp ".build/release/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

# Copy Info.plist
echo "📋 Copying Info.plist..."
cp "Info.plist" "$APP_DIR/Contents/Info.plist"

# Copy app icon
echo "🎨 Copying app icon..."
cp -r "Sources/Glyph/Resources/AppIcon.appiconset" "$APP_DIR/Contents/Resources/"

# Use Apple-compliant dark mode icon from Resources folder
echo "🔧 Setting up optimized icon..."
RESOURCES_ICONS="Sources/Glyph/Resources/Icons"

if [ -f "$RESOURCES_ICONS/AppIcon_AppleDark.icns" ]; then
    echo "🍎 Using Apple-compliant dark mode icon"
    cp "$RESOURCES_ICONS/AppIcon_AppleDark.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
elif [ -f "$RESOURCES_ICONS/AppIcon_Dark.icns" ]; then
    echo "🌙 Using dark mode optimized icon"
    cp "$RESOURCES_ICONS/AppIcon_Dark.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
elif [ -f "$RESOURCES_ICONS/AppIcon.icns" ]; then
    echo "💡 Using standard optimized icon"
    cp "$RESOURCES_ICONS/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
elif command -v iconutil >/dev/null 2>&1; then
    echo "🔧 Converting iconset to .icns format..."
    iconutil -c icns "$APP_DIR/Contents/Resources/AppIcon.appiconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
    rm -rf "$APP_DIR/Contents/Resources/AppIcon.appiconset"
else
    echo "⚠️  iconutil not found, keeping .appiconset format"
fi

# Set file permissions
echo "🔐 Setting permissions..."
chmod -R 755 "$APP_DIR"

# Create a symlink in Applications folder for easy access
echo "🔗 Creating link for easy access..."
DESKTOP_APP="$HOME/Desktop/$APP_NAME.app"
ln -sf "$(pwd)/$APP_DIR" "$DESKTOP_APP"

echo "✅ App bundle created successfully!"
echo "📍 Location: $APP_DIR"
echo "🖱️  Shortcut: $DESKTOP_APP"
echo ""
echo "🚀 To run your app:"
echo "   Double-click: $DESKTOP_APP"
echo "   Command line: open '$APP_DIR'"
echo ""
echo "🎉 Your Glyph app with custom icon is ready!" 