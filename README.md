# macOS Clipboard Fixer

[![Licence: MIT](https://img.shields.io/badge/Licence-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python Version](https://img.shields.io/badge/python-3.9%2B-blue.svg)](https://www.python.org/downloads/)
[![PyObjC](https://img.shields.io/badge/dependency-PyObjC-orange.svg)](https://pyobjc.readthedocs.io/en/latest/)

A simple Python script for macOS that monitors the clipboard and automatically removes extraneous URL data when copying images from applications like Safari, ensuring cleaner pasting into other apps. Includes a management script for easy installation and setup as a background service.

---

## Table of Contents

*   [The Problem](#the-problem)
*   [The Solution](#the-solution)
*   [Requirements](#requirements)
*   [Installation & Management](#installation--management)
*   [Usage (Manual)](#usage-manual)
*   [License](#license)

---

## The Problem

When copying images from certain applications on macOS (notably Safari), the clipboard often contains *both* the image data (e.g., TIFF or PNG) and the source URL as plain text. While this can sometimes be useful, many applications don't handle this combination gracefully when pasting. This can lead to unexpected behaviour, such as pasting the URL instead of the intended image.

## The Solution

This project provides `fix_clipboard.py`, a script that runs quietly in the background, monitoring the macOS clipboard. It specifically looks for instances where both image data and plain text are present simultaneously (but it's not a file copy operation).

When this pattern is detected, the script automatically:
1.  Clears the current clipboard contents.
2.  Re-copies *only* the image data back onto the clipboard (preferring TIFF format, falling back to PNG if necessary).

This ensures that pasting into applications that primarily expect image data works smoothly and predictably.

To simplify setup and running the script automatically on login, a management script `manage_clipboard_fixer.sh` is included.

## Requirements

*   **Python 3:** Developed and tested with Python 3.9+, but should be compatible with most modern Python 3 versions. Command `python3` must be available in your PATH.
*   **PyObjC:** Python bindings for Apple's Objective-C frameworks are required to interact with the native clipboard. The management script will install the necessary `pyobjc-framework-Cocoa` package automatically into a dedicated virtual environment.

## Installation & Management

The `manage_clipboard_fixer.sh` script handles installation, uninstallation, and status checking of the background service.

1.  **Download or Clone:**
    Get the project files, ensuring `manage_clipboard_fixer.sh` and `fix_clipboard.py` are in the same directory.
    ```bash
    git clone https://github.com/gavinmorrison/macos-clipboard-fixer.git
    cd macos-clipboard-fixer
    ```

2.  **Make the Management Script Executable:**
    ```bash
    chmod +x manage_clipboard_fixer.sh
    ```

3.  **Install:**
    Run the script with the `install` command. It will prompt you for an installation location (defaults to `~/Library/Application Support/ClipboardFixer`).
    ```bash
    ./manage_clipboard_fixer.sh install
    ```
    This command performs the following steps:
    *   Checks for Python 3.
    *   Asks for and creates the installation directory.
    *   Copies `fix_clipboard.py` to the installation directory.
    *   Creates a Python virtual environment (`.venv`) inside the installation directory.
    *   Installs `pyobjc-framework-Cocoa` into the virtual environment.
    *   Creates a `launchd` service `.plist` file in `~/Library/LaunchAgents/` configured to run the script from the installation directory using the virtual environment's Python. The service label defaults to `com.<your_username>.clipboardfixer`.
    *   Loads and starts the `launchd` service.

    The script will now run automatically whenever you log in. All logs (standard output and errors) are stored in `/tmp/com.<your_username>.clipboardfixer.log`.

    *(Customising the Service Label: If you need to use a different label (e.g., `com.mycompany.clipboardfixer`), edit the `SERVICE_LABEL` variable directly near the top of the `manage_clipboard_fixer.sh` script **before** running the `install` command.)*

4.  **Check Status:**
    You can check if the `launchd` service is loaded:
    ```bash
    ./manage_clipboard_fixer.sh status
    ```
    You can view the combined log file using:
    ```bash
    tail -f /tmp/com.<your_username>.clipboardfixer.log
    ```
    *(Replace `<your_username>` with your actual username, or use the customised label if you changed it.)*

5.  **Uninstall:**
    To stop the service and remove the `launchd` configuration:
    ```bash
    ./manage_clipboard_fixer.sh uninstall
    ```
    This command will:
    *   Unload the service from `launchd`.
    *   Remove the `.plist` file from `~/Library/LaunchAgents/`.
    *   Ask if you also want to remove the installation directory (containing the script and virtual environment).

    *(Note: If you customised the `SERVICE_LABEL` by editing the script before installation, ensure the script still has the same customised label when you run `uninstall`.)*
    You may need to manually delete the log file (`/tmp/com.<your_username>.clipboardfixer.log`) if desired.

## Usage (Manual)

If you prefer not to install the background service, you can still set up the environment manually and run the script directly for testing or temporary use.

1.  **Clone or Download:** Get the `fix_clipboard.py` script.
2.  **Set up Virtual Environment:**
    ```bash
    python3 -m venv .venv
    source .venv/bin/activate
    pip install pyobjc-framework-Cocoa
    ```
3.  **Run the Script:**
    While the virtual environment is active:
    ```bash
    python3 fix_clipboard.py
    ```
    Press `Ctrl+C` to stop it. Use `--debug` for verbose logging or `--interval <seconds>` to change the check frequency.

---

## Important Security Warning

This script interacts directly with your macOS clipboard, which can contain sensitive information, including passwords. Running any script as a background service carries inherent risks. While this script is designed to be simple and focused, **the author is not liable for any damages, data loss, or security breaches that may arise from its use, misuse, or any vulnerabilities.**

**Users are strongly advised to:**
*   **Review the source code (`fix_clipboard.py`) thoroughly** before installation to understand its functionality.
*   **Understand the implications** of running a script as a `launchd` service.
*   **Use this software at their own risk.**

---
## Disclaimer

Apple, macOS, and Safari are trademarks of Apple Inc., registered in the U.S. and other countries and regions. This project is not affiliated with, sponsored by, or endorsed by Apple Inc.
## Licence

This project is licensed under the MIT Licence. See the [LICENSE](LICENSE) file for details.