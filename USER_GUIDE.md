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
The app automatically selects the optimal storage location for your platform, ensuring files are both secure and accessible to other dictionary readers (like Goldendict or ColorDict).

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
- **Multi-Selection**: Check individual items or use the group headers to select entire categories at once.
- **Direct Download**: Use the **Download** button at the bottom to fetch all selected items.
- **State Preservation**: You can switch to other tabs or browse different groups without losing your current selection.
- **Refresh**: Use the **Refresh** icon in the top AppBar to check for new additions to the repository.

### 2. Your lists (Customized Sources)
Track and update dictionaries from private repositories or custom web sources.
- **Adding Sources**: Expand the **"Add Customized Source"** section. Give your source a name and paste either a direct download URL or a block of markdown text containing links.
- **Automatic Parsing**: The app will scan your pasted text for all valid dictionary links and present them as a trackable list.
- **Management**: Each source can be expanded to view individual files or deleted entirely using the trash icon.
- **Bulk Sync**: Use the floating action button to download all updates across all your custom lists simultaneously.

---

## 🔄 Smart Updates & Syncing
- **Update Detection**: The app identifies "Update Available" when a file on the server has a newer timestamp than your local copy.
- **Auto-Selection**: New dictionaries and identified updates are automatically highlighted and pre-selected for one-tap downloading.
- **Global Refresh**: Click the **Refresh** icon in the top AppBar to perform a comprehensive check of all repository and custom sources.
- **Active Monitoring**: Real-time progress bars show individual download status, and a "Stop All" action is available for emergency cancellations.

---

## ❓ Frequently Asked Questions
**Q: Why don't my changes appear after I switch tabs?**

**A:** The app uses caching to ensure a fast, responsive experience. If you expect new dictionaries to be available, use the **Refresh** button in the AppBar.

**Q: Can I change the storage folder?**

**A:** Currently, the app uses standardized paths to ensure compatibility with system-wide file access policies and other dictionary apps.

**Q: What file formats are supported?**

**A:** The app primarily manages compressed dictionary archives (e.g., `.tar.gz`, `.zip`, `.dz`). These are compatible with most modern StarDict, Dictd, Mdict and Slob-based dictionary readers.
