# Dictionary Updater User Guide

A powerful, cross-platform utility designed for scholarly dictionary management. Effortlessly browse, download, and synchronize hundreds of dictionaries from the **Indic-dict** repository or your own custom lists.

---

## 🚀 Core Features
- **Unified Sync Center**: A centralized dashboard for all dictionary management.
- **Official Repository Integration**: Direct access to the comprehensive Indic-dict collection.
- **Custom Source Tracking**: Monitor and update dictionaries from any web link or markdown list.
- **Automated Version Tracking**: Intelligent update detection based on file timestamps.
- **Cross-Platform Storage**: Native file management for macOS, Windows, Linux, iOS, and Android.

---

## 📂 Storage & File Access
The app automatically selects the optimal storage location for your platform, ensuring files are both secure and accessible to other dictionary readers (like [HDICT](https://apps.apple.com/in/app/hdict/id6759493062)).

| Platform | Recommended Location | Access Method |
| :--- | :--- | :--- |
| **macOS / Windows / Linux** | `Downloads/DictionaryData` | Standard File Explorer / Finder |
| **iOS** | App Sandbox | System **Files** app > "On My iPhone" > "Dictionary Updater" |
| **Android** | External App Data | `Android/data/com.example.sdu/files/DictionaryData` |

---

## 🛠 Managing Your Dictionaries

Navigation is handled via the **Sync Center**, accessible from the side drawer. The interface is split into two primary tabs:

### 1. Indic-dict (Official Repository)
This tab connects you directly to hundreds of scholarly dictionaries.
- **Browsing**: Explore dictionaries organized by language and category.
- **Multi-Selection**: Check individual items or use group headers to select entire categories at once.
- **Direct Download**: Use the **Download** button at the bottom to fetch all selected items.
- **State Preservation**: Switch tabs or browse different groups without losing your selection.

### 2. Your lists (Customized Sources)
Track and update dictionaries from private repositories or custom web sources.
- **Adding Sources**: Expand **"Add Customized Source"**, give it a name, and paste a direct URL or a block of markdown text.
- **Automatic Parsing**: The app scans pasted text for dictionary links and presents them as a trackable list.
- **Management**: Expand sources to view files or delete them using the trash icon.

---

## 🔄 Smart Updates & Syncing

- **Prominent Refresh**: The core of the app is the large **"Refresh Dictionaries"** button at the top of the Sync Center. Click it to perform a comprehensive check of all repository and custom sources.
- **Last Checked Timestamp**: Directly below the Refresh button, you'll see exactly when your collection was last updated.
- **Summary Statistics**: Every tab features a status header showing:
    - **Total Available**: All dictionaries found in the source.
    - **Downloaded**: Items already on your device (Up to date + Newer version available).
    - **Up to date**: Files that match the latest server version.
    - **Newer version**: Files that have an update available.
- **Update Detection**: The app identifies updates by comparing the **timestamp** embedded in the filename (e.g., `...__2023-12-01...`) with your local copy.
- **Batch Progress**: During downloads, a persistent progress bar shows the overall batch status (e.g., "5/12 downloaded").
- **Integrated Stop All**: A prominent **"Stop All"** button appears during active downloads for immediate cancellation.

---

## 📖 How to Use Downloaded Dictionaries

Once your dictionaries are downloaded, you can use them with any dictionary reader of your choice.

- **Recommended Reader**: We recommend using **[HDICT](https://apps.apple.com/in/app/hdict/id6759493062)** for the best experience on mobile and desktop.
- **Universal Compatibility**: The downloaded files are in standard formats compatible with most readers that support StarDict, MDict, or DICTD.
- **Accessing Files**: Refer to the **Storage & File Access** table above to find precisely where your files are stored on your device.

---

## ❓ Frequently Asked Questions
**Q: Why don't my changes appear after I switch tabs?**

**A:** The app uses caching for responsiveness. If you expect new dictionaries to be available, use the prominent **Refresh Dictionaries** button.

**Q: Can I change the storage folder?**

**A:** Currently, the app uses standardized paths to ensure compatibility with system-wide file access policies and other dictionary apps.

**Q: What file formats are supported?**

**A:** The app primarily manages compressed dictionary archives (e.g., `.tar.gz`, `.zip`, `.dz`). These are compatible with most modern StarDict, Dictd, Mdict and Slob-based dictionary readers.
