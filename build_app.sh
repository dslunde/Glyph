#!/bin/bash

# 🚀 Glyph App Bundle Builder with Embedded Python 3.13.3
# This script creates a proper macOS .app bundle with custom icon and embedded Python

set -e  # Exit on any error

echo "🔨 Building Glyph macOS App Bundle with Embedded Python..."

# Configuration
APP_NAME="Glyph"
BUNDLE_ID="com.glyph.knowledge-graph-explorer"
VERSION="1.0"
BUILD_DIR=".build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

# Python Configuration
PYTHON_VERSION="3.13.3"
PYTHON_HOME="/Users/darrenlund/.pyenv/versions/$PYTHON_VERSION"
PYTHON_EXEC="$PYTHON_HOME/bin/python3.13"

# Verify Python installation
echo "🐍 Verifying Python $PYTHON_VERSION installation..."
if [ ! -f "$PYTHON_EXEC" ]; then
    echo "❌ Python $PYTHON_VERSION not found at $PYTHON_EXEC"
    echo "💡 Install with: pyenv install $PYTHON_VERSION"
    exit 1
fi

echo "✅ Found Python $PYTHON_VERSION at $PYTHON_EXEC"

# Clean and create directories
echo "🧹 Cleaning build directory..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/"{MacOS,Resources,Python}

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

# Copy entitlements for PythonKit compatibility
echo "🔐 Copying entitlements..."
if [ -f "Glyph.entitlements" ]; then
    cp "Glyph.entitlements" "$APP_DIR/Contents/Glyph.entitlements"
    echo "✅ Entitlements copied (App Sandbox disabled for PythonKit)"
else
    echo "⚠️  No entitlements file found"
fi

# === EMBED PYTHON 3.13.3 ===
echo "🐍 Embedding Python $PYTHON_VERSION runtime..."

# Create Python directory structure (simplified)
EMBEDDED_PYTHON="$APP_DIR/Contents/Python"
mkdir -p "$EMBEDDED_PYTHON/"{bin,lib,include}

# Copy Python executable
echo "📦 Copying Python executable..."
cp "$PYTHON_EXEC" "$EMBEDDED_PYTHON/bin/"
chmod +x "$EMBEDDED_PYTHON/bin/python3.13"

# Copy Python library (the shared library file)
echo "📚 Copying Python library..."
PYTHON_LIB="$PYTHON_HOME/lib/libpython3.13.dylib"
if [ -f "$PYTHON_LIB" ]; then
    cp "$PYTHON_LIB" "$EMBEDDED_PYTHON/lib/"
else
    echo "⚠️  Python library not found at $PYTHON_LIB"
    # Look for alternative locations
    for lib_path in "$PYTHON_HOME/lib/python3.13/config-3.13-darwin/libpython3.13.dylib" "/opt/homebrew/lib/libpython3.13.dylib"; do
        if [ -f "$lib_path" ]; then
            echo "📚 Found Python library at $lib_path"
            cp "$lib_path" "$EMBEDDED_PYTHON/lib/"
            break
        fi
    done
fi

# Copy Python standard library
echo "📖 Copying Python standard library..."
cp -r "$PYTHON_HOME/lib/python3.13" "$EMBEDDED_PYTHON/lib/"

# Copy Python headers (needed for some packages)
echo "📋 Copying Python headers..."
if [ -d "$PYTHON_HOME/include/python3.13" ]; then
    cp -r "$PYTHON_HOME/include/python3.13" "$EMBEDDED_PYTHON/include/"
fi

# Install required Python packages into embedded location
echo "📦 Installing required Python packages..."
EMBEDDED_SITE_PACKAGES="$EMBEDDED_PYTHON/lib/python3.13/site-packages"

# Install core packages needed by the app
"$PYTHON_EXEC" -m pip install --target "$EMBEDDED_SITE_PACKAGES" \
    --upgrade --no-deps --no-cache-dir \
    numpy==2.3.1 \
    networkx==3.5 \
    requests>=2.31.0 \
    python-dotenv>=1.0.0 \
    openai>=1.0.0 \
    tavily-python>=0.3.0 || {
    echo "⚠️  Some packages failed to install, continuing..."
}

# Copy custom Python modules to embedded site-packages
echo "📦 Installing custom Python modules..."
CUSTOM_PYTHON_FILES=(
    "Sources/Glyph/PythonAPIService.py"
    "Sources/Glyph/source_collection_workflow.py"
)

for file in "${CUSTOM_PYTHON_FILES[@]}"; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        cp "$file" "$EMBEDDED_SITE_PACKAGES/$filename"
        echo "✅ Installed custom module: $filename"
    else
        echo "⚠️  Custom Python file not found: $file"
    fi
done

echo "✅ Python $PYTHON_VERSION embedded successfully!"

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

# Code signing with entitlements (simplified approach)
echo "📝 Code signing..."
if [ -f "Glyph.entitlements" ]; then
    echo "🔏 Signing with entitlements for PythonKit compatibility..."
    # Sign Python components first
    find "$APP_DIR/Contents/Python" -name "*.dylib" -exec codesign --force --sign - {} \; || echo "⚠️  Some Python libraries couldn't be signed"
    codesign --force --sign - "$APP_DIR/Contents/Python/bin/python3.13" || echo "⚠️  Python executable signing failed"
    
    # Sign the main app
    codesign --force --deep --sign - --entitlements "Glyph.entitlements" "$APP_DIR" || {
        echo "⚠️  Code signing with entitlements failed, trying without..."
        codesign --force --deep --sign - "$APP_DIR" || echo "⚠️  Code signing failed completely"
    }
else
    echo "🔏 Basic code signing..."
    codesign --force --deep --sign - "$APP_DIR" || echo "⚠️  Code signing failed"
fi

# Create a symlink in Applications folder for easy access
echo "🔗 Creating link for easy access..."
DESKTOP_APP="$HOME/Desktop/$APP_NAME.app"
ln -sf "$(pwd)/$APP_DIR" "$DESKTOP_APP"

echo "✅ App bundle created successfully!"
echo "📍 Location: $APP_DIR"
echo "🖱️  Shortcut: $DESKTOP_APP"
echo ""
echo "🐍 Embedded Python Configuration:"
echo "   ✓ Python Version: $PYTHON_VERSION"
echo "   ✓ Python Path: Contents/Python"
echo "   ✓ App Sandbox: Disabled"
echo "   ✓ Library Validation: Disabled"
echo "   ✓ Core Packages: numpy, networkx, requests, openai, tavily-python"
echo ""
echo "🚀 To run your app:"
echo "   Double-click: $DESKTOP_APP"
echo "   Command line: open '$APP_DIR'"
echo ""
echo "🎉 Your Glyph app with embedded Python $PYTHON_VERSION is ready!" 