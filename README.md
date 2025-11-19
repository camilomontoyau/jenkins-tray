# Jenkins Tray Monitor

A macOS menu bar application to monitor Jenkins jobs, built with Swift and SwiftUI.

## Features
- Monitor multiple Jenkins jobs simultaneously.
- Notifications (Speech & System) when a job finishes.
- Persists settings and job list locally (Password stored securely in Keychain).
- "Window" style menu bar app for easy interaction.

## Requirements
- macOS 13.0 (Ventura) or later.
- Xcode 14+ (for full development/archiving).

## How to Run (Development)
You can run the app immediately using the included script, which builds and signs it for local use:
```bash
./create_bundle.sh
open jenkins-tray.app
```

## App Store & Archiving
To prepare this app for the App Store, you must create a full Xcode Project (since `Package.swift` alone does not support App Store signing features):

1. **Create Xcode Project**:
   - Open Xcode -> File -> New -> Project.
   - Select **macOS** -> **App**.
   - Name it `JenkinsTray`.
   - Ensure Interface is **SwiftUI** and Language is **Swift**.

2. **Import Code**:
   - Drag the Swift files from `Sources/jenkins-tray/` (`App.swift`, `JenkinsService.swift`, `Models.swift`, `Views.swift`) into your new Xcode project.
   - Delete the default `ContentView.swift` and `JenkinsTrayApp.swift` created by Xcode, and use the ones you imported.

3. **Configure Signing**:
   - Click on the Project icon (top left).
   - Select your **Target**.
   - Go to the **Signing & Capabilities** tab.
   - Add your Team and Bundle Identifier.
   - **Important**: Click "+ Capability" and add **App Sandbox**.
   - Under App Sandbox, check **Outgoing Connections (Client)** to allow Jenkins API access.

4. **Archive**:
   - Select "Product" -> "Archive".
   - Use "Distribute App" -> "App Store Connect".
