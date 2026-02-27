# Dictionary Updater User Guide

A production-ready, cross-platform dictionary manager built with Flutter.

## Features
- **Indic-dict Repository**: Browse and download hundreds of scholarly dictionaries directly from the repository.
- **Customized Lists**: Paste direct links or markdown lists to track your own dictionary sources.
- **Smart Versioning**: Automatically identifies updates based on filenames and timestamps.
- **Unified Sync Center**: Manage all your dictionaries from a single, tabbed interface.
- **Cross-Platform Storage**: Dictionaries are automatically stored in the best location for your device.

## Storage Locations
To simplify your experience, the app automatically chooses a secure and accessible storage location.

- **macOS / Windows / Linux**: Saved to your system **Downloads** folder (`Downloads/DictionaryData`).
- **iOS**: Accessible through the system **Files** app under **"On My iPhone > Dictionary Updater"**.
- **Android**: Stored in external storage under `Android/data/com.example.sdu/files/DictionaryData`.

## Managing Dictionaries
Open the **Sync Center** from the sidebar drawer to manage your sources.

### Indic-dict Repository Tab
1. Browse the scholarly dictionary categories.
2. Select the items you wish to download. Multiple selections across different groups are supported.
3. Click the **Download** button at the bottom.
4. The list is automatically kept in state when you switch tabs, but you can manually refresh it using the **Refresh** icon in the header.

### Customized Lists Tab
1. Expand the **"Add Customized Source"** section.
2. Provide a name and paste a direct URL or a block of markdown text containing dictionary links.
3. Dictionaries found in the text will appear for tracking and download.
4. Click the floating **Download** button to start processing your selections.

## Smart Updates & Refresh
- **Refresh**: Click the **Refresh icon** in the top AppBar to check both repository and customized sources for newer versions.
- **Detection**: The app identifies "Update Available" when the upstream filename has a newer timestamp than your local version.
- **Auto-Selection**: New dictionaries and updates are automatically pre-selected for your convenience.

## Sync Center Controls
- **Global Actions**: Use the floating actions to "Download All" or "Stop All" active downloads.
- **Direct Downloads**: Individual items in the Indic-dict tab show a progress bar during download.
- **Clear List**: You can delete customized sources by clicking the delete icon on their respective cards.
