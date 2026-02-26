# Dictionary Updater User Guide

A production-ready, cross-platform dictionary manager built with Flutter.

## Features
- **Indic-dict Repository**: Browse and download hundreds of scholarly dictionaries directly from the repository.
- **Remote Sync**: Automatically parse webpage/markdown sources for dictionary links.
- **Local Import**: Easily import dictionary indices or files from your local storage.
- **Cross-Platform**: Intelligent storage path management for Android, iOS, and Desktop.
- **Modern UI**: Polished interface with expandable sections and responsive layouts.
- **Sync Center**: Bulk update and version checking for all your dictionaries.

## Storage Settings
By default, dictionaries are stored in the application's support directory.
**Crucial Step**: On the first run, you are prompted to select a storage folder. 
- If you skip this, dictionaries will not be downloaded.
- You can set or change the storage folder anytime in **Settings** > **Select Download Folder**.
- On Desktop, a common choice is `~/Downloads/StarDictData`.

## Adding Dictionaries
1. Go to the **Sources** tab via the sidebar drawer.
2. Click the **Add** button in the header.
3. Choose one of the three premium options:
   - **Indic-dict Repository**: Navigate through categories and select scholarly dictionaries for download.
   - **Import Local File**: Select a local `.md`, `.txt`, or `.zip` file containing dictionary links.
   - **Download from Web**: Paste a direct link or a block of markdown text containing links.

## Smart Updates & Refresh
- Click **Refresh** in the header to check all sources for updates.
- **Indic-dict Updates**: The app intelligently detects when a dictionary has a newer version (indicated by a change in timestamp in the filename).
- **Replacement Notice**: If an update is found, you will see a notice. Downloading the new version will automatically delete the old file to save space.

## Sync Center Management
- Expand a source card to see available dictionaries.
- **Selection Logic**:
  - **New** and **Update Available** items are auto-selected.
  - **Up-to-Date** items are unselected.
- Use the **Global Sync Button** at the bottom to download all selected items across all sources at once.
