#!/bin/bash

# install_python_packages.sh
# Install Python packages for Glyph's embedded Python environment

set -e  # Exit on any error

echo "🐍 Glyph Python Package Installer"
echo "=================================="

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to find Python executable
find_python() {
    local python_cmd=""
    
    # Check for different Python commands in order of preference
    if command_exists python3.13; then
        python_cmd="python3.13"
    elif command_exists python3; then
        python_cmd="python3"
    elif command_exists python; then
        python_cmd="python"
    else
        echo "❌ No Python installation found"
        return 1
    fi
    
    echo "$python_cmd"
}

# Function to get Python version
get_python_version() {
    local python_cmd="$1"
    $python_cmd --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'
}

# Function to check if pip is available
check_pip() {
    local python_cmd="$1"
    if $python_cmd -m pip --version >/dev/null 2>&1; then
        return 0
    else
        echo "⚠️ pip not available for $python_cmd"
        return 1
    fi
}

# Function to install packages
install_packages() {
    local python_cmd="$1"
    local requirements_file="$2"
    
    echo "📦 Installing packages from $requirements_file..."
    echo "🐍 Using Python: $python_cmd ($(get_python_version "$python_cmd"))"
    
    # First, upgrade pip itself
    echo "🔧 Upgrading pip..."
    $python_cmd -m pip install --upgrade pip
    
    # Install packages from requirements.txt
    echo "📋 Installing requirements..."
    $python_cmd -m pip install -r "$requirements_file"
    
    echo "✅ Package installation completed"
}

# Function to install packages for embedded Python
install_embedded_packages() {
    local app_bundle="$1"
    local python_path="$app_bundle/Contents/Python"
    local python_executable="$python_path/bin/python3.13"
    
    if [[ -x "$python_executable" ]]; then
        echo "🎯 Found embedded Python: $python_executable"
        
        if check_pip "$python_executable"; then
            install_packages "$python_executable" "requirements.txt"
            return 0
        else
            echo "⚠️ pip not available in embedded Python"
            return 1
        fi
    else
        echo "⚠️ Embedded Python not found at: $python_executable"
        return 1
    fi
}

# Function to create virtual environment
create_venv() {
    local python_cmd="$1"
    local venv_path="$2"
    
    echo "🏗️ Creating virtual environment at $venv_path..."
    $python_cmd -m venv "$venv_path"
    
    # Activate and install packages
    source "$venv_path/bin/activate"
    install_packages "$venv_path/bin/python" "requirements.txt"
    deactivate
}

# Main installation logic
main() {
    echo "🔍 Checking Python environment..."
    
    # Check if requirements.txt exists
    if [[ ! -f "requirements.txt" ]]; then
        echo "❌ requirements.txt not found in current directory"
        exit 1
    fi
    
    # Look for existing app bundle
    local app_bundle=""
    if [[ -d "Glyph.app" ]]; then
        app_bundle="Glyph.app"
        echo "📱 Found app bundle: $app_bundle"
    elif [[ -d ".build/release/Glyph.app" ]]; then
        app_bundle=".build/release/Glyph.app"
        echo "📱 Found app bundle: $app_bundle"
    fi
    
    # Try embedded Python first
    if [[ -n "$app_bundle" ]]; then
        echo "🎯 Attempting to install packages in embedded Python..."
        if install_embedded_packages "$app_bundle"; then
            echo "🎉 Successfully installed packages in embedded Python!"
            exit 0
        fi
    fi
    
    # Fall back to system Python
    echo "🔄 Falling back to system Python installation..."
    
    local python_cmd
    if ! python_cmd=$(find_python); then
        echo "❌ No suitable Python installation found"
        echo "💡 Please install Python 3.8+ and try again"
        exit 1
    fi
    
    echo "🐍 Found Python: $python_cmd ($(get_python_version "$python_cmd"))"
    
    # Check if pip is available
    if ! check_pip "$python_cmd"; then
        echo "❌ pip is not available"
        echo "💡 Please install pip for your Python installation"
        exit 1
    fi
    
    # Ask user preference for installation method
    echo ""
    echo "Choose installation method:"
    echo "1) Install globally (may require sudo)"
    echo "2) Install in user directory (--user flag)"
    echo "3) Create virtual environment"
    read -p "Enter choice (1-3): " choice
    
    case $choice in
        1)
            echo "🌍 Installing globally..."
            install_packages "$python_cmd" "requirements.txt"
            ;;
        2)
            echo "👤 Installing in user directory..."
            $python_cmd -m pip install --user -r requirements.txt
            ;;
        3)
            local venv_path="./venv"
            read -p "Virtual environment path [$venv_path]: " input_path
            if [[ -n "$input_path" ]]; then
                venv_path="$input_path"
            fi
            create_venv "$python_cmd" "$venv_path"
            ;;
        *)
            echo "❌ Invalid choice"
            exit 1
            ;;
    esac
    
    echo ""
    echo "🎉 Installation completed successfully!"
    echo "💡 You may need to restart Glyph to pick up the new packages"
}

# Script options
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [--help|--check|--embedded-only]"
        echo ""
        echo "Options:"
        echo "  --help          Show this help message"
        echo "  --check         Check Python environment without installing"
        echo "  --embedded-only Only try embedded Python installation"
        exit 0
        ;;
    --check)
        echo "🔍 Checking Python environment..."
        if python_cmd=$(find_python); then
            echo "✅ Python found: $python_cmd ($(get_python_version "$python_cmd"))"
            if check_pip "$python_cmd"; then
                echo "✅ pip is available"
            else
                echo "❌ pip not available"
            fi
        else
            echo "❌ No Python found"
        fi
        exit 0
        ;;
    --embedded-only)
        echo "🎯 Embedded Python only mode"
        app_bundle=""
        if [[ -d "Glyph.app" ]]; then
            app_bundle="Glyph.app"
        elif [[ -d ".build/release/Glyph.app" ]]; then
            app_bundle=".build/release/Glyph.app"
        fi
        
        if [[ -n "$app_bundle" ]]; then
            if install_embedded_packages "$app_bundle"; then
                echo "🎉 Successfully installed packages in embedded Python!"
            else
                echo "❌ Failed to install packages in embedded Python"
                exit 1
            fi
        else
            echo "❌ No app bundle found"
            exit 1
        fi
        exit 0
        ;;
esac

# Run main function
main "$@" 