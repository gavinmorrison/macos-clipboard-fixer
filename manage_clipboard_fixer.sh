#!/bin/bash
# Copyright (c) 2025 Gavin Morrison. Licensed under the MIT License.
# For the latest version and more information, visit:
# https://github.com/gavinmorrison/macos-clipboard-fixer/

# Manages the installation and launchd service for macos-clipboard-fixer.

# --- Configuration ---
APP_NAME="ClipboardFixer"
SCRIPT_NAME="fix_clipboard.py"
VENV_DIR=".venv"
REQUIREMENTS="pyobjc-framework-Cocoa"
DEFAULT_INSTALL_DIR="${HOME}/Library/Application Support/${APP_NAME}" # Default install location

# Generate the default service label using the current username
CURRENT_USER=$(whoami)
# If you want to change the label, edit it here AND update the uninstall section accordingly.
SERVICE_LABEL="com.${CURRENT_USER}.clipboardfixer"
# --- End Configuration ---

PLIST_DIR="${HOME}/Library/LaunchAgents"
PLIST_FILENAME="${SERVICE_LABEL}.plist"
PLIST_PATH="${PLIST_DIR}/${PLIST_FILENAME}"

# --- Functions ---
print_info() {
    echo "INFO: $1"
}

print_warning() {
    echo "WARN: $1"
}

print_error() {
    echo "ERROR: $1" >&2
}

usage() {
    echo "Usage: $0 install | uninstall | status"
    echo "  install    : Installs the script and sets up the launchd service."
    echo "  uninstall  : Uninstalls the launchd service and optionally removes installed files."
    echo "  status     : Checks the status of the launchd service."
    exit 1
}

# --- Installation Function ---
do_install() {
    print_info "Starting installation..."

    # 1. Check OS
    if [[ "$(uname)" != "Darwin" ]]; then
        print_error "This script is only for macOS."
        exit 1
    fi

    # 2. Get Installation Directory
    read -p "Enter installation directory [${DEFAULT_INSTALL_DIR}]: " INSTALL_DIR
    INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}" # Use default if empty

    # Expand ~ character
    INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"

    print_info "Will install to: ${INSTALL_DIR}"

    # 3. Create directory if needed
    if [ ! -d "$INSTALL_DIR" ]; then
        print_info "Creating installation directory..."
        if ! mkdir -p "$INSTALL_DIR"; then
            print_error "Failed to create directory: ${INSTALL_DIR}"
            exit 1
        fi
    fi

    # 4. Find source script path (assuming manage script is in the same dir as fix_clipboard.py)
    SOURCE_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
    SOURCE_FIXER_SCRIPT="${SOURCE_SCRIPT_DIR}/${SCRIPT_NAME}"

    if [ ! -f "$SOURCE_FIXER_SCRIPT" ]; then
        print_error "Source script not found at: ${SOURCE_FIXER_SCRIPT}"
        print_error "Make sure ${SCRIPT_NAME} is in the same directory as this management script."
        exit 1
    fi

    # 5. Copy script to install directory
    TARGET_FIXER_SCRIPT="${INSTALL_DIR}/${SCRIPT_NAME}"
    print_info "Copying ${SCRIPT_NAME} to ${INSTALL_DIR}..."
    if ! cp "$SOURCE_FIXER_SCRIPT" "$TARGET_FIXER_SCRIPT"; then
        print_error "Failed to copy script."
        exit 1
    fi

    # 6. Create Virtual Environment in install directory
    TARGET_VENV_PATH="${INSTALL_DIR}/${VENV_DIR}"
    if [ -d "$TARGET_VENV_PATH" ]; then
        print_info "Virtual environment already exists at ${TARGET_VENV_PATH}. Skipping creation."
    else
        print_info "Creating virtual environment in ${TARGET_VENV_PATH}..."
        if ! python3 -m venv "$TARGET_VENV_PATH"; then
            print_error "Failed to create virtual environment."
            exit 1
        fi
    fi

    # 7. Install requirements
    TARGET_PIP_CMD="${TARGET_VENV_PATH}/bin/pip"
    print_info "Installing requirements ($REQUIREMENTS) into virtual environment..."
    if ! "$TARGET_PIP_CMD" install $REQUIREMENTS; then
        print_error "Failed to install requirements."
        exit 1
    fi

    # 8. Create and load launchd plist
    TARGET_PYTHON_EXEC="${TARGET_VENV_PATH}/bin/python3"
    print_info "Creating launchd plist file: ${PLIST_PATH}"
    mkdir -p "$PLIST_DIR" # Ensure LaunchAgents dir exists

    # Unload existing service first, if any
    if launchctl list | grep -q "$SERVICE_LABEL"; then
        print_info "Unloading existing service '$SERVICE_LABEL' before creating new one..."
        launchctl unload "$PLIST_PATH" 2>/dev/null
    fi

    cat << EOF > "$PLIST_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${SERVICE_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${TARGET_PYTHON_EXEC}</string>
        <string>${TARGET_FIXER_SCRIPT}</string>
        <!-- Add arguments like --interval here if needed -->
        <!-- <string>--interval</string> -->
        <!-- <string>0.5</string> -->
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <!-- Redirect both stdout and stderr to the same log file -->
    <key>StandardOutPath</key>
    <string>/tmp/${SERVICE_LABEL}.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/${SERVICE_LABEL}.log</string>
</dict>
</plist>
EOF

    if [ $? -ne 0 ]; then
        print_error "Failed to write plist file."
        exit 1
    fi

    print_info "Loading service '$SERVICE_LABEL' into launchd..."
    if ! launchctl load "$PLIST_PATH"; then
        print_error "Failed to load service into launchd."
        print_error "Check permissions or look for errors using 'launchctl list | grep ${SERVICE_LABEL}'"
        # Attempt to clean up plist if load failed
        rm -f "$PLIST_PATH"
        exit 1
    fi

    print_info "Installation complete!"
    print_info "Service '$SERVICE_LABEL' is running and will start on login."
    print_info "Installed files are in: ${INSTALL_DIR}"
    print_info "Logs (stdout & stderr) are directed to: /tmp/${SERVICE_LABEL}.log"
}

# --- Uninstallation Function ---
do_uninstall() {
    print_info "Starting uninstallation for service '$SERVICE_LABEL'..."

    # 1. Unload service
    print_info "Attempting to unload service from launchd..."
    if launchctl list | grep -q "$SERVICE_LABEL"; then
        if ! launchctl unload "$PLIST_PATH" 2>/dev/null; then
            print_warning "Failed to unload service '$SERVICE_LABEL'. It might already be stopped or have permissions issues."
            print_warning "Continuing with file removal..."
        else
            print_info "Service unloaded successfully."
        fi
    else
        print_info "Service '$SERVICE_LABEL' does not appear to be loaded."
    fi

    # 2. Remove plist file
    if [ -f "$PLIST_PATH" ]; then
        print_info "Removing plist file: ${PLIST_PATH}"
        if ! rm "$PLIST_PATH"; then
            print_warning "Failed to remove plist file. Check permissions."
        else
            print_info "Plist file removed."
        fi
    else
        print_info "Plist file not found at ${PLIST_PATH}. Nothing to remove."
    fi

    # 3. Ask to remove installation directory
    # Try to guess install dir based on plist content if possible (more robust)
    # This requires parsing the plist, which is tricky in bash. Let's assume default for now or ask.
    # A better approach would be to store the install path somewhere during install.
    # For simplicity now, we'll just use the default path or ask.

    DEFAULT_INSTALL_DIR_EXPANDED="${DEFAULT_INSTALL_DIR/#\~/$HOME}"
    INSTALL_DIR_TO_REMOVE=""

    if [ -d "$DEFAULT_INSTALL_DIR_EXPANDED" ]; then
         INSTALL_DIR_TO_REMOVE="$DEFAULT_INSTALL_DIR_EXPANDED"
    fi

    # If default doesn't exist, maybe it was installed elsewhere? Prompt user.
    if [ -z "$INSTALL_DIR_TO_REMOVE" ]; then
        read -p "Enter the directory where ${APP_NAME} was installed (leave blank to skip removal): " CUSTOM_INSTALL_DIR
        CUSTOM_INSTALL_DIR="${CUSTOM_INSTALL_DIR/#\~/$HOME}"
        if [ -d "$CUSTOM_INSTALL_DIR" ]; then
            INSTALL_DIR_TO_REMOVE="$CUSTOM_INSTALL_DIR"
        fi
    fi

    if [ -n "$INSTALL_DIR_TO_REMOVE" ]; then
        read -p "Do you want to remove the installation directory (${INSTALL_DIR_TO_REMOVE})? [y/N]: " REMOVE_CONFIRM
        if [[ "$REMOVE_CONFIRM" =~ ^[Yy]$ ]]; then
            print_info "Removing installation directory: ${INSTALL_DIR_TO_REMOVE}"
            if ! rm -rf "$INSTALL_DIR_TO_REMOVE"; then
                print_error "Failed to remove installation directory. Check permissions."
            else
                print_info "Installation directory removed."
            fi
        else
            print_info "Skipping removal of installation directory."
        fi
    else
         print_info "Could not determine installation directory to remove, or it doesn't exist."
    fi


    # 4. Optional: Remove log files
    print_info "You may want to manually remove log files:"
    print_info "  /tmp/${SERVICE_LABEL}.log"
    print_info "  /tmp/${SERVICE_LABEL}.err"

    print_info "Uninstallation complete."
}

# --- Status Function ---
do_status() {
    print_info "Checking status for service '$SERVICE_LABEL'..."
    if launchctl list | grep -q "$SERVICE_LABEL"; then
        echo "Service '$SERVICE_LABEL' appears to be LOADED."
        # Note: This doesn't guarantee the process is *running* without errors, just that launchd knows about it.
        # Check logs for runtime status.
        echo "Check logs for runtime details:"
        echo "  /tmp/${SERVICE_LABEL}.log"
        echo "  /tmp/${SERVICE_LABEL}.err"
    else
        echo "Service '$SERVICE_LABEL' appears to be UNLOADED or NOT INSTALLED."
    fi
}


# --- Main Argument Parsing ---
COMMAND=$1

if [ -z "$COMMAND" ]; then
    usage
fi

case $COMMAND in
    install)
        do_install
        ;;
    uninstall)
        do_uninstall
        ;;
    status)
        do_status
        ;;
    *)
        print_error "Invalid command: $COMMAND"
        usage
        ;;
esac

exit 0