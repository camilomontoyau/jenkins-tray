import SwiftUI

@main
struct JenkinsTrayApp: App {
    var body: some Scene {
        MenuBarExtra("Jenkins tray", systemImage: "hammer.fill") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}

