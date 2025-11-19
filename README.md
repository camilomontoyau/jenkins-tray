# Jenkins Tray Monitor

A macOS menu bar application to monitor Jenkins jobs, built with Swift and SwiftUI.

## Features
- Monitor multiple Jenkins jobs simultaneously.
- Notifications (Speech & System) when a job finishes.
- Persists settings and job list locally.
- "Window" style menu bar app for easy interaction.

## Requirements
- macOS 13.0 (Ventura) or later.
- Xcode 14+ (for full development/archiving).

## How to Run (Development)
You can run the app directly from the command line:
```bash
swift run
```

## Usage
1. Click the "Hammer" icon in the menu bar.
2. Click the "Gear" icon to open settings.
3. Enter your Jenkins URL (e.g., `https://jenkins.company.com`), Username, and Password/Token.
4. Click "Save & Close".
5. Paste a job path (e.g., `job/folder/job/name/123/`) in the text field and click "Add".
6. The job will appear in the list and update automatically.

## App Store & Archiving
To prepare this app for the App Store:

1. **Generate Xcode Project**:
   Open the `Package.swift` file in Xcode. Xcode will treat it as a project.

2. **Configure Signing**:
   - Click on the `jenkins-tray` target.
   - Go to "Signing & Capabilities".
   - Add your Team.
   - Set a unique Bundle Identifier (e.g., `com.yourname.jenkins-tray`).
   - Ensure "App Sandbox" is enabled if required (default for App Store).
   - If Sandboxed, ensure "Outgoing Connections (Client)" is checked to allow network access.

3. **Archive**:
   - Select "Product" -> "Archive".
   - Once archived, use the Organizer to "Distribute App" -> "App Store Connect".

