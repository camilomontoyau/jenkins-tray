import SwiftUI

@main
struct JenkinsTrayApp: App {
    @StateObject private var service = JenkinsService()
    
    var body: some Scene {
        MenuBarExtra("Jenkins tray", systemImage: "hammer.fill") {
            ContentView(service: service)
        }
        .menuBarExtraStyle(.window)
    }
}

