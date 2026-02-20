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
1. Go to the **Sync Center**.
2. Click **Add Source**.
3. You can either:
   - Provide a **URL** to a remote Markdown/text file.
   - **Upload a local file** containing dictionary download links.

## Smart Selection Logic
When browsing a dictionary source:
- **New** dictionaries (not yet downloaded) are **selected by default**.
- **Update Available** dictionaries (newer version found via HEAD request) are **selected by default**.
- **Up to Date** dictionaries are **unselected by default**.
This allows for a "one-click" update experience. You can manually toggle selections using the checkboxes/radio markers.

## Development Tip
Run `flutter analyze` to ensure code quality.
Use `dart run build_runner build` to regenerate database schemas if models are changed.
