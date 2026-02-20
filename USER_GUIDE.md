# StarDict Manager User Guide

A production-ready, cross-platform StarDict dictionary manager built with Flutter.

## Features
- **Remote Sync**: Automatically parse GitHub Markdown sources for dictionary links.
- **Cross-Platform**: Intelligent storage path management for Android, iOS, and Desktop.
- **Modern UI**: Material 3 design with dynamic color support and responsive layouts.
- **Sync Center**: Bulk update and version checking for all your dictionaries.

## Storage Locations
By default, dictionaries are stored in:
- **Android/iOS**: App Documents directory.
- **Desktop (macOS/Windows/Linux)**: `~/Downloads/StarDictData` or a hidden folder in your home directory.

You can override this path in **Settings** using the directory picker.

## Adding Custom Sources
1. Go to the **Stardict Sources** screen.
2. Click the **+** (Add) icon in the top right.
3. You can either:
   - Provide a **URL/Webpage** to a remote Markdown/text file.
   - **Select Local File** containing dictionary download links.
   - **Paste List** of URLs directly into a textbox.

## Smart Selection & Downloading
When expanding a dictionary source card:
- **New** dictionaries are **selected by default**.
- **Update Available** dictionaries are **selected by default**.
- **Up to Date** dictionaries are **unselected by default**.

You can download dictionaries source-by-source or use the **Global Download Button** at the bottom of the screen to download all selected dictionaries across all your sources in one batch. Download progress is shown for each file and the overall batch.

## Development Tip
Run `flutter analyze` to ensure code quality.
Use `dart run build_runner build` to regenerate database schemas if models are changed.
