# Dictionary Updater User Guide

A production-ready, cross-platform dictionary manager built with Flutter.

## Features
- **Indic-dict Repository**: Browse and download hundreds of scholarly dictionaries directly from the repository.
- **Remote Sync**: Automatically parse webpage or markdown sources for dictionary links.
- **Cross-Platform Storage**: Dictionaries are automatically stored in the best location for your device.
- **Sync Center**: Bulk update and version checking for all your dictionaries with a single tap.
- **Modern UI**: Clean, responsive interface designed for visual feedback and efficiency.

## Storage Locations
To simplify your experience, the app automatically chooses a secure and accessible storage location. You no longer need to configure paths manually.

- **macOS / Windows / Linux**: Dictionaries are saved to your system **Downloads** folder (`Downloads/DictionaryData`). This makes them easily accessible to other dictionary viewers.
- **iOS**: Files are stored in the app container and are accessible through the system **Files** app under **"On My iPhone > Dictionary Updater"**.
- **Android**: Files are stored in external storage under `Android/data/com.example.sdu/files/DictionaryData`, visible to most file managers.

## Adding Dictionaries
1. Open the sidebar drawer and select the **Sources** tab.
2. Click the **+** (Add) button in the header.
3. Choose one of the two methods:
   - **Indic-dict Repository**: Browse scholarly dictionary categories and select files to add to your sync list.
   - **Download from Web**: Paste a direct URL or a block of markdown text containing dictionary links.

## Smart Updates & Refresh
- **Refresh**: Click the Refresh icon in the Sync Center to check your sources for newer versions.
- **Detection**: The app identifies "Update Available" when the upstream filename has a newer timestamp than your local version.
- **Auto-Selection**: New dictionaries and updates are automatically selected for you in the Sync Center.

## Sync Center Management
- **Download Confirmation**: Before any download starts, you will see a summary of the total size and the destination folder.
- **Download All**: Use the floating action button at the bottom to download all selected dictionaries across all sources in one go. You only need to confirm once!
- **Download Group**: You can also download all items within a single group by expanding its card and clicking "Download".
- **Stopping**: Use the "Stop All" button if you need to pause or cancel active downloads.
