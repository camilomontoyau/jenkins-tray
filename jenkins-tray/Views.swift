import SwiftUI
import UserNotifications
import AppKit

struct ContentView: View {
    @StateObject var service = JenkinsService()
    @State private var newJobPath: String = ""
    @State private var showSettings = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Jenkins tray")
                    .font(.headline)
                Spacer()
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            
            if showSettings {
                SettingsView(service: service, isPresented: $showSettings)
                    .padding()
                    .transition(.move(edge: .top))
            }
            
            Divider()
            
            // Add Job
            if service.isConfigured {
                HStack {
                    TextField("Paste job path here...", text: $newJobPath)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            addJob()
                        }
                    
                    Button("Add") {
                        addJob()
                    }
                }
                .padding()
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("Please configure settings to add jobs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Settings") {
                        showSettings = true
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Job List
            List {
                ForEach(service.jobs) { job in
                    JobRow(job: job, service: service) {
                        service.removeJob(id: job.id)
                    }
                }
            }
            .listStyle(.plain)
            .frame(minHeight: 200)
            
            Divider()
            
            HStack {
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .padding()
            }
        }
        .frame(width: 350)
        .onAppear {
            // Request notification permission only if running as a bundle
            if Bundle.main.bundleIdentifier != nil {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            }
        }
    }
    
    func addJob() {
        guard !newJobPath.isEmpty else { return }
        service.addJob(path: newJobPath)
        newJobPath = ""
    }
}

struct JobRow: View {
    let job: Job
    let service: JenkinsService
    var onDelete: () -> Void
    
    @State private var copied = false
    
    var statusColor: Color {
        switch job.status {
        case .success: return .green
        case .failure: return .red
        case .aborted: return .gray
        case .running: return .blue
        case .unknown: return .orange
        case .authError: return .orange
        case .networkError: return .red
        }
    }
    
    var statusIcon: String {
        switch job.status {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .aborted: return "stop.circle.fill"
        case .running: return "arrow.triangle.2.circlepath.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        case .authError: return "lock.slash.fill"
        case .networkError: return "wifi.slash"
        }
    }
    
    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
            
            VStack(alignment: .leading) {
                Text("Build #\(job.buildId)")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                Text(job.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            
            if job.status == .running {
                ProgressView()
                    .scaleEffect(0.5)
            }
            
            Button(action: {
                let apiUrl = service.getApiUrl(for: job)
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(apiUrl, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    copied = false
                }
            }) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundColor(copied ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.vertical, 4)
    }
}

struct SettingsView: View {
    @ObservedObject var service: JenkinsService
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Settings").font(.subheadline).bold()
            
            TextField("Jenkins URL", text: $service.url)
                .textFieldStyle(.roundedBorder)
            
            TextField("Username", text: $service.username)
                .textFieldStyle(.roundedBorder)
            
            SecureField("Password / Token", text: $service.password)
                .textFieldStyle(.roundedBorder)
            
            Button("Save & Close") {
                service.saveSettings()
                isPresented = false
            }
            .padding(.top, 5)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 2)
    }
}

