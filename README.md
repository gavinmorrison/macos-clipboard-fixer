# macOS Clipboard Fixer

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python Version](https://img.shields.io/badge/python-3.9%2B-blue.svg)](https://www.python.org/downloads/)
[![PyObjC](https://img.shields.io/badge/dependency-PyObjC-orange.svg)](https://pyobjc.readthedocs.io/en/latest/)

A simple Python script for macOS that monitors the clipboard and automatically removes extraneous URL data when copying images from applications like Safari, ensuring cleaner pasting into other apps.

---

## Table of Contents

*   [The Problem](#the-problem)
*   [The Solution](#the-solution)
*   [Requirements](#requirements)
*   [Installation](#installation)
*   [Usage](#usage)
*   [Deployment (Running in the Background)](#deployment-running-in-the-background)
*   [Contributing](#contributing)
*   [License](#license)

---

## The Problem

When copying images from certain applications on macOS (notably Safari), the clipboard often contains *both* the image data (e.g., TIFF or PNG) and the source URL as plain text. While this can sometimes be useful, many applications don't handle this combination gracefully when pasting. This can lead to unexpected behavior, such as pasting the URL instead of the intended image.

## The Solution

This script, `fix_clipboard.py`, runs quietly in the background, monitoring the macOS clipboard. It specifically looks for instances where both image data and URL text are present simultaneously (but it's not a file copy operation).

When this pattern is detected, the script automatically:
1.  Clears the current clipboard contents.
2.  Re-copies *only* the image data back onto the clipboard (preferring TIFF format, falling back to PNG if necessary).

This ensures that pasting into applications that primarily expect image data works smoothly and predictably.

## Requirements

*   **Python 3:** Developed and tested with Python 3.9+, but should be compatible with most modern Python 3 versions.
*   **PyObjC:** Python bindings for Apple's Objective-C frameworks are required to interact with the native clipboard. Specifically, the `pyobjc-framework-Cocoa` package is needed.

## Installation

1.  **Clone the Repository:**
    ```bash
    git clone https://github.com/gavinmorrison/macos-clipboard-fixer.git
    cd macos-clipboard-fixer
    ```
    Alternatively, you can just download the `fix_clipboard.py` script directly.

2.  **Set up a Virtual Environment (Recommended):**
    Using a virtual environment prevents conflicts with system-wide packages.
    ```bash
    # Create the virtual environment directory
    python3 -m venv .venv

    # Activate the virtual environment (macOS)
    source .venv/bin/activate
    ```

3.  **Install Dependencies:**
    With the virtual environment active, install the required PyObjC package:
    ```bash
    pip install pyobjc-framework-Cocoa
    ```
    *(To deactivate the virtual environment when done, simply run the command `deactivate`)*

## Usage

Ensure your virtual environment is active (if you created one) by running `source .venv/bin/activate`.

Run the script directly from your terminal:

```bash
python3 fix_clipboard.py
```

The script will log status messages to the console indicating when it starts and when it modifies the clipboard. You can leave this terminal window open to keep the script running, or use a deployment method (see below) to run it persistently in the background.

**Command-Line Options:**

*   `--debug`: Enables more verbose (debug level) logging output. Useful for troubleshooting or understanding exactly what the script is seeing on the clipboard.
    ```bash
    python3 fix_clipboard.py --debug
    ```
*   `-i <seconds>`, `--interval <seconds>`: Specifies how often (in seconds) the script should check the clipboard contents. The default is `1.0` second. Setting this lower (e.g., `0.5`) makes the script more responsive but uses slightly more resources.
    ```bash
    python3 fix_clipboard.py --interval 0.5
    ```

To stop the script if it's running in the foreground, press `Ctrl+C` in the terminal.

## Deployment (Running in the Background)

For the script to run automatically every time you log in, using `launchd` (the standard macOS service manager) is the recommended approach.

1.  **Determine Absolute Paths:**
    You'll need the absolute paths to your Python executable (within the virtual environment, if used) and the `fix_clipboard.py` script.
    *   **Python Path:** While the virtual environment is active, run `which python3`.
    *   **Script Path:** Navigate to the directory containing `fix_clipboard.py` and run `pwd`. Note the full path.

2.  **Create a Launch Agent `.plist` File:**
    Create a file named `com.yourusername.clipboardfixer.plist` (use a unique identifier, following reverse-DNS notation) inside the `~/Library/LaunchAgents/` directory. Paste the following content into the file, **replacing the placeholder paths** with the absolute paths you found in step 1.

    ```xml
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>com.yourusername.clipboardfixer</string> <!-- MUST be unique! -->

        <key>ProgramArguments</key>
        <array>
            <!-- Path to Python executable (inside .venv if used) -->
            <string>/absolute/path/to/.venv/bin/python3</string>
            <!-- Path to the script -->
            <string>/absolute/path/to/fix_clipboard.py</string>
            <!-- Optional: Add arguments like --interval here -->
            <!-- <string>--interval</string> -->
            <!-- <string>0.5</string> -->
        </array>

        <!-- Run the script when the user logs in -->
        <key>RunAtLoad</key>
        <true/>

        <!-- Keep the script running; restart if it crashes -->
        <key>KeepAlive</key>
        <true/>

        <!-- Optional: Redirect standard output and error to log files -->
        <key>StandardOutPath</key>
        <string>/tmp/clipboardfixer.log</string>
        <key>StandardErrorPath</key>
        <string>/tmp/clipboardfixer.err</string>
    </dict>
    </plist>
    ```

3.  **Load the Launch Agent:**
    Open the Terminal application and run the following command to load and start your new background service:
    ```bash
    launchctl load ~/Library/LaunchAgents/com.yourusername.clipboardfixer.plist
    ```

4.  **Verify (Optional):**
    The script should now be running. You can check the log files specified (`/tmp/clipboardfixer.log` and `/tmp/clipboardfixer.err`) or use `launchctl list | grep clipboardfixer` to confirm the service is loaded.

5.  **To Unload (Stop the Service):**
    If you need to stop the background script permanently:
    ```bash
    launchctl unload ~/Library/LaunchAgents/com.yourusername.clipboardfixer.plist
    ```

6.  **To Reload (After Updating Script or Plist):**
    If you modify the script or the `.plist` file, you need to unload and then load the service again for the changes to take effect:
    ```bash
    launchctl unload ~/Library/LaunchAgents/com.yourusername.clipboardfixer.plist
    launchctl load ~/Library/LaunchAgents/com.yourusername.clipboardfixer.plist
    ```

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.