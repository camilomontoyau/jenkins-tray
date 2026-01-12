import SwiftUI
import UserNotifications
import AppKit

struct ContentView: View {
    @ObservedObject var service: JenkinsService
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
    @State private var showFutureConfig = false
    
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
            
            Button(action: {
                if let url = service.getJobWebUrl(for: job) {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Image(systemName: "link")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            
            // Future Run Config Button
            Button(action: {
                openConfigWindow()
            }) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(job.futureJob != nil ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .help("Configure Future Run")
            
            // Trigger Future Job Immediately Button
            Button(action: {
                if let futureJob = job.futureJob {
                    service.triggerFutureJob(config: futureJob, parent: job)
                }
            }) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(
                        (job.status == .success && job.futureJob != nil) ? .yellow : .gray.opacity(0.3)
                    )
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .disabled(job.status != .success || job.futureJob == nil)
            .help("Trigger Future Job Now")
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .help(job.path) // Show full path on hover
        }
        .padding(.vertical, 4)
    }
    
    func openConfigWindow() {
        // Create a new window for configuration
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.center()
        window.title = "Future Run Configuration - \(job.displayName)"
        window.isReleasedWhenClosed = false // Keep window alive? No, we want it released but SwiftUI might handle it.
        // Actually, for simple window:
        
        let view = FutureJobConfigView(job: job, service: service, isPresented: Binding(
            get: { true },
            set: { if !$0 { window.close() } }
        ))
        
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct FutureJobConfigView: View {
    var job: Job
    @ObservedObject var service: JenkinsService
    @Binding var isPresented: Bool
    
    @State private var futureUrl: String = ""
    @State private var params: [JobParam] = []
    @State private var selectedConfig: FutureJobConfig?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Future Run Configuration")
                .font(.headline)
            
            Text("Trigger this job when parent finishes successfully:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if !service.savedConfigs.isEmpty {
                HStack {
                    Text("Saved Configs:")
                    Picker("", selection: $selectedConfig) {
                        Text("Select a preset...").tag(nil as FutureJobConfig?)
                        ForEach(service.savedConfigs, id: \.self) { config in
                            Text(config.url).tag(config as FutureJobConfig?)
                        }
                    }
                    .onChange(of: selectedConfig) { newValue in
                        if let config = newValue {
                            futureUrl = config.url
                            params = config.params
                        }
                    }
                }
            }
            
            TextField("Job Path (e.g. job/my-project)", text: $futureUrl)
                .textFieldStyle(.roundedBorder)
            
            Text("Parameters")
                .font(.subheadline)
                .padding(.top, 5)
            
            ScrollView {
                VStack {
                    ForEach($params) { $param in
                        HStack {
                            TextField("Key", text: $param.key)
                            TextField("Value", text: $param.value)
                            Button(action: {
                                params.removeAll { $0.id == param.id }
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            Button(action: {
                params.append(JobParam())
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Parameter")
                }
            }
            .buttonStyle(.plain)
            
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                Spacer()
                Button("Save") {
                    saveConfig()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 10)
        }
        .padding()
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            if let config = job.futureJob {
                futureUrl = config.url
                params = config.params
            }
        }
    }
    
    func saveConfig() {
        var updatedJob = job
        // Filter out empty params
        let validParams = params.filter { !$0.key.isEmpty }
        let newConfig = FutureJobConfig(url: futureUrl, params: validParams)
        
        if futureUrl.isEmpty {
             updatedJob.futureJob = nil
        } else {
            updatedJob.futureJob = newConfig
            // Save to history
            service.saveFutureConfig(newConfig)
        }
        
        service.updateJob(updatedJob)
        isPresented = false
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
            
            HStack {
                Text("Future Job Delay (min):")
                TextField("Minutes", value: $service.futureJobDelay, formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                Stepper("", value: $service.futureJobDelay, in: 0...60)
            }
            .padding(.top, 5)
            
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

