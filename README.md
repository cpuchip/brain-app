# Brain App

Cross-platform Flutter app for the Brain second-brain system. Capture thoughts, classify with AI, manage entries with subtasks — all synced through the brain ecosystem.

## Platforms

| Platform | Status |
|----------|--------|
| Android | Supported |
| Windows | Supported |
| iOS | Planned |
| macOS | Planned |

## Ecosystem

Brain App is one of three components:

| Component | Location | Purpose |
|-----------|----------|---------|
| **brain.exe** | `scripts/brain/` (separate git repo) | Local brain — capture, classify, store, search |
| **ibeco.me** | `scripts/becoming/` (in scripture-study) | Cloud hub — relay, web UI, practices, journaling |
| **brain-app** (this repo) | `scripts/brain-app/` | Flutter mobile/desktop app |

The app connects to either brain.exe directly (LAN) or through the ibeco.me relay (remote).

## Setup

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.38+
- For Android: Android Studio + SDK
- For Windows: Visual Studio with Desktop C++ workload

### Configuration

Create a `.env` file in the project root:

```env
# brain.exe direct connection (LAN)
BRAIN_URL=http://localhost:8445

# Or ibeco.me relay (remote)
# BRAIN_URL=https://ibeco.me
```

### Build & Run

```powershell
# Get dependencies
flutter pub get

# Run on connected device / emulator
flutter run

# Build release APK
flutter build apk --release

# Build Windows desktop
flutter build windows --release
```

### Quick Start (Windows)

```powershell
powershell -ExecutionPolicy Bypass -File start.ps1
```

## Features

- Thought capture with speech-to-text
- AI classification (categories: people, projects, ideas, actions, study, journal)
- Entry CRUD with subtask management
- Full-text and semantic search
- Offline support with local SQLite cache + sync
- Home screen widget
- Local notifications for reminders

## Project Structure

```
lib/
├── main.dart        # Entry point
├── screens/         # App screens (capture, entries, detail, search, settings)
├── services/        # API, auth, storage, notifications, sync
└── widgets/         # Reusable UI components
```
