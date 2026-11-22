# Knot - MVP Feature List

## Core Features ✅
- Create/delete projects
- Create text notes (markdown)
- Create voice notes (audio recording)
- Audio player with visualizer
- Wiki links [[note]]
- Inter-project links [[project:note]]
- Graph visualization with physics
- Voice nodes (green with ripple effect)
- Global search across all projects
- Note preview on long press
- [[note]] renders as @note in view mode
- Backlinks shown in note preview

## App Structure
- Home screen - projects list
- Graph screen - knowledge graph
- Note detail screen - text editor + audio player

## Settings (app_config.dart)
- maxProjects: 3
- maxVoiceRecordingSeconds: 300 (5 min)
- voiceFirstEnabled: false
- isPremium: false

---

## Premium Features (Not Implemented Yet)
- Unlimited voice recording
- Unlimited projects
- Cloud sync
- Transcription (offline/online)
- Voice commands
- Export PDF
- Home screen widget
- Focus mode

---

## Production Improvements (Suggestions)

### 1. Robust Note Parsing - Bidirectional Linking
- Instead of scanning every file for links on graph open (laggy with growth)
- Use lightweight JSON index mapping SourceNote -> TargetNote
- Use this index to draw edges in physics graph
- ✅ Graph renders instantly even with hundreds of nodes

### 2. Audio Waveform Persistence
- Generate .json or .peak file during recording
- Show "static" waveform on note card without loading audio
- Saves memory on previews

### 3. Premium Feature Gating
- Wrap premium features in config checks
- Use flutter_secure_storage for premium status (not easily wiped)

### 4. File System Safety Net
- **Soft Delete**: Move to .trash folder instead of hard delete
- **Atomic Saves**: Write to temp_file then rename to original

---

## Tech Stack
- Flutter (Dart)
- Local storage (file system)
- Audio recording (record package)
- Audio playback (audioplayers package)

