#!/usr/bin/env python3

"""
Monitors the macOS clipboard and fixes an issue where copying images from
Safari also includes the source URL, which can cause problems when pasting
into certain applications.

If an image (TIFF/PNG) and a URL (plain text) are detected simultaneously
on the clipboard (and it's not a file path), the script clears the clipboard
and re-copies *only* the image data.
"""

import time
import argparse
import logging
from typing import List, Tuple, Optional, Any

# Attempt to import AppKit from pyobjc, which provides access to macOS native APIs
try:
    import AppKit
except ImportError:
    # Provide helpful error message if PyObjC is not installed
    logging.error(
        "Error: PyObjC bindings for AppKit not found. "
        "Please install pyobjc-framework-Cocoa: "
        "pip install pyobjc-framework-Cocoa"
    )
    exit(1) # Exit if essential dependency is missing

# --- Constants ---
DEFAULT_POLL_INTERVAL = 1.0  # Default time in seconds between clipboard checks

# --- Logging Setup ---
# Configure basic logging to standard output
logging.basicConfig(
    level=logging.INFO, # Default level, can be overridden by --debug flag
    format='%(asctime)s - %(levelname)s - %(message)s', # Include timestamp, level, and message
    datefmt='%Y-%m-%d %H:%M:%S' # Timestamp format
)
# Get a logger instance for the script
log = logging.getLogger(__name__)

# --- Clipboard Functions ---

def get_clipboard_contents() -> Tuple[Optional[List[str]], Optional[str]]:
    """
    Retrieves the current types and plain text content from the general pasteboard.

    Uses AppKit.NSPasteboard to interact with the system clipboard.

    Returns:
        A tuple containing:
        - A list of pasteboard types (strings like 'public.tiff', 'public.utf8-plain-text'),
          or None if an error occurs during access.
        - The plain text content (string), if available, or None if not present or an error occurs.
    """
    try:
        # Access the shared system pasteboard
        pb = AppKit.NSPasteboard.generalPasteboard()
        # Get a list of data types currently available on the pasteboard
        types = pb.types()
        # Specifically request the string content
        # Using NSPasteboardTypeString is the standard way to get plain text.
        plain_text_content = pb.stringForType_(AppKit.NSPasteboardTypeString)
        return types, plain_text_content
    except Exception as e:
        # Log errors if clipboard access fails (e.g., permissions issues, rare OS errors)
        log.error(f"Error accessing clipboard: {e}")
        return None, None # Return None to indicate failure

def has_image_and_text(types: Optional[List[str]]) -> bool:
    """
    Checks if the pasteboard types indicate the specific problematic pattern:
    an image AND plain text, but NOT primarily a file copy operation.

    Args:
        types: A list of pasteboard type strings, or None if clipboard access failed.

    Returns:
        True if the pattern is matched, False otherwise.
    """
    # If types is None, it means get_clipboard_contents failed, so return False
    if not types:
        return False

    # Check for common image types provided by AppKit
    # NSPasteboardTypeTIFF is common for screenshots and Safari image copies
    # NSPasteboardTypePNG is another possibility
    has_image = any(t in types for t in [AppKit.NSPasteboardTypeTIFF, AppKit.NSPasteboardTypePNG])

    # Check if plain text is present (NSPasteboardTypeString).
    # In the target scenario (Safari image copy), this usually holds the URL,
    # but the check itself is just for the presence of *any* plain text type.
    has_text = AppKit.NSPasteboardTypeString in types

    # Check if it looks like a file copy operation (e.g., copying a file in Finder)
    # We want to IGNORE these cases, as they might legitimately have file URLs and image previews.
    # NSPasteboardTypeFileURL is the modern way macOS represents file paths on the clipboard.
    # 'public.file-path' is an older type, included for broader compatibility just in case.
    has_file = any(t in types for t in [AppKit.NSPasteboardTypeFileURL, "public.file-path"])

    # Log the findings for debugging purposes
    log.debug(f"Clipboard check: Has image: {has_image}, Has text: {has_text}, Has file: {has_file}")

    # The target condition: image is present, plain text is present, but it's NOT a file copy
    return has_image and has_text and not has_file

def copy_image_only() -> bool:
    """
    Attempts to isolate and re-copy *only* the image data to the clipboard.

    It reads the image data (preferring TIFF), clears the clipboard,
    and then writes only the image data back.

    Returns:
        True if the image was successfully found and re-copied, False otherwise.
    """
    try:
        pb = AppKit.NSPasteboard.generalPasteboard()

        # Try to get image data. Prioritize TIFF as it's often the primary format
        # used by macOS for copies like this and might retain more information.
        image_data = pb.dataForType_(AppKit.NSPasteboardTypeTIFF)
        image_type = AppKit.NSPasteboardTypeTIFF # Keep track of which type we found

        # If TIFF data wasn't found, fall back to checking for PNG data.
        if not image_data:
            image_data = pb.dataForType_(AppKit.NSPasteboardTypePNG)
            image_type = AppKit.NSPasteboardTypePNG

        # Proceed only if we actually found image data (either TIFF or PNG)
        if image_data:
            # IMPORTANT: Store the image data and its type *before* clearing.
            # We need to hold onto it temporarily.
            # Using a list allows for potentially adding multiple types later if needed.
            data_to_write = [(image_type, image_data)]

            # Clear *all* current contents from the pasteboard.
            # This removes the unwanted URL string and any other types.
            pb.clearContents()

            # Write *only* the stored image data back to the now-empty pasteboard.
            # This loop currently runs only once, but is structured for potential future extension.
            for type_str, data in data_to_write:
                 pb.setData_forType_(data, type_str)

            log.info("✅ Re-copied image only to clipboard.")
            return True # Indicate success
        else:
            # Log if no suitable image data was found to perform the fix
            log.debug("No TIFF or PNG image data found on clipboard to re-copy.")
            return False # Indicate failure (no image found)
    except Exception as e:
        # Log errors if modifying the clipboard fails
        log.error(f"Error modifying clipboard: {e}")
        return False # Indicate failure (error occurred)

# --- Main Loop ---

def main(poll_interval: float):
    """
    The main execution function that runs the monitoring loop.

    Args:
        poll_interval: The time in seconds to wait between clipboard checks.
    """
    log.info(f"📋 Clipboard fixer running. Poll interval: {poll_interval}s. Press Ctrl+C to stop.")

    # Variables to store the state of the clipboard from the previous check
    # Initialized to None to ensure the first check runs
    last_types: Optional[List[str]] = None
    last_plain_text: Optional[str] = None

    # Infinite loop to continuously monitor the clipboard
    while True:
        try:
            # Get the current state of the clipboard
            current_types, current_plain_text = get_clipboard_contents()

            # Determine if the clipboard has changed since the last check.
            # Also consider the case where the previous read failed (current_types would be None then).
            # We compare both the list of types and the plain text content.
            clipboard_changed = (current_types != last_types or current_plain_text != last_plain_text)

            # Process only if the clipboard changed AND the read was successful (current_types is not None)
            if clipboard_changed and current_types is not None:
                # Print separator directly for visual clarity in debug, outside formal log message
                if log.isEnabledFor(logging.DEBUG):
                    print("\n--- Clipboard Changed ---")
                log.debug(f"Types: {current_types}")
                # Log the actual plain text content for better debugging insight
                log.debug(f"Plain Text: '{current_plain_text}'")

                # Check if the new clipboard state matches the problematic pattern
                if has_image_and_text(current_types):
                    log.info("Detected image + text pattern. Attempting fix...")
                    # Attempt to fix the clipboard by re-copying only the image
                    copy_image_only()
                else:
                    # Log if the pattern wasn't matched
                    log.debug("Clipboard content doesn't match target pattern. Ignoring.")

            # Update the 'last known state' variables for the next iteration's comparison.
            # Only update if the read was successful to avoid losing the last good state on error.
            if current_types is not None:
                last_types = current_types
                last_plain_text = current_plain_text

            # Pause execution for the specified interval before the next check
            time.sleep(poll_interval)

        except KeyboardInterrupt:
            # Gracefully handle Ctrl+C press to stop the script
            log.info("👋 KeyboardInterrupt detected. Stopping.")
            break # Exit the while loop
        except Exception as e:
            # Catch any other unexpected errors during the loop
            log.error(f"Unexpected error in main loop: {e}", exc_info=True) # Log traceback
            # Sleep for a longer interval to prevent spamming logs if a persistent error occurs
            time.sleep(poll_interval * 5)


# --- Script Entry Point ---

# This block executes only when the script is run directly (not imported as a module)
if __name__ == "__main__":
    # Set up command-line argument parsing
    parser = argparse.ArgumentParser(
        description="Fixes macOS clipboard issues when copying images from Safari.",
        # Automatically show default values in help message
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    # Argument for enabling debug logging
    parser.add_argument(
        '--debug',
        action='store_true', # Makes it a flag (no value needed)
        help="Enable debug level logging."
    )
    # Argument for setting the polling interval
    parser.add_argument(
        '-i', '--interval', # Allow both short and long forms
        type=float,         # Expect a floating-point number
        default=DEFAULT_POLL_INTERVAL, # Use the constant defined earlier
        help="Polling interval in seconds to check clipboard."
    )
    # Parse the arguments provided by the user
    args = parser.parse_args()

    # If the --debug flag was provided, set the logger level to DEBUG
    if args.debug:
        log.setLevel(logging.DEBUG)
        log.debug("Debug mode enabled.")

    # Call the main function, passing the specified (or default) polling interval
    main(poll_interval=args.interval)