import SwiftUI
import UserNotifications
import AppKit
import Combine

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
                    .foregroundColor(job.futureJobs.isEmpty ? .secondary : .blue)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .help("Configure Future Run")
            
            // Trigger Future Job Immediately Button
            Button(action: {
                if let firstFuture = job.futureJobs.first {
                    let remaining = Array(job.futureJobs.dropFirst())
                    service.triggerFutureJob(config: firstFuture, parent: job, remainingChain: remaining)
                }
            }) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(
                        (job.status == .success && !job.futureJobs.isEmpty) ? .yellow : .gray.opacity(0.3)
                    )
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .disabled(job.status != .success || job.futureJobs.isEmpty)
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
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.center()
        window.title = "Future Run Configuration - \(job.displayName)"
        window.isReleasedWhenClosed = false
        
        let view = FutureJobConfigView(job: job, service: service, isPresented: Binding(
            get: { true },
            set: { if !$0 { window.close() } }
        ))
        
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum ConfigFocusField: Hashable {
    case url(UUID)
    case key(UUID, UUID)
    case value(UUID, UUID)
    
    var stepId: UUID {
        switch self {
        case .url(let stepId):
            return stepId
        case .key(let stepId, _):
            return stepId
        case .value(let stepId, _):
            return stepId
        }
    }
}

class FutureJobConfigViewModel: ObservableObject {
    @Published var steps: [FutureJobConfig] = []
    @Published var selectedConfig: FutureJobConfig?
    
    @Published var currentFocus: ConfigFocusField?
    @Published var requestedFocus: ConfigFocusField?
    @Published var activeStepId: UUID?
    
    var monitor: Any?
    
    func setup(job: Job) {
        if !job.futureJobs.isEmpty {
            steps = job.futureJobs
        } else {
            steps = [FutureJobConfig()]
        }
        
        activeStepId = steps.first?.id
        if let firstStep = steps.first {
            requestedFocus = .url(firstStep.id)
        }
        
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == 48 { // Tab
                if let focus = self.currentFocus,
                   case .value(let stepId, let paramId) = focus,
                   let lastStep = self.steps.last,
                   stepId == lastStep.id,
                   let lastParamId = lastStep.params.last?.id,
                   paramId == lastParamId {
                    
                    DispatchQueue.main.async {
                        self.addParam(to: stepId)
                    }
                    return nil
                }
            }
            return event
        }
    }
    
    func updateFocus(_ focus: ConfigFocusField?) {
        currentFocus = focus
        if let focus = focus {
            activeStepId = focus.stepId
        }
    }
    
    func reset() {
        let newStep = FutureJobConfig()
        steps = [newStep]
        selectedConfig = nil
        activeStepId = newStep.id
        requestedFocus = .url(newStep.id)
    }
    
    func addStep() {
        let newStep = FutureJobConfig()
        steps.append(newStep)
        activeStepId = newStep.id
        requestedFocus = .url(newStep.id)
    }
    
    func removeStep(at index: Int) {
        guard steps.indices.contains(index), steps.count > 1 else { return }
        let removedId = steps[index].id
        steps.remove(at: index)
        if activeStepId == removedId {
            activeStepId = steps.first?.id
            if let firstStep = steps.first {
                requestedFocus = .url(firstStep.id)
            }
        }
    }
    
    func addParam(to stepId: UUID?) {
        let targetId = stepId ?? activeStepId ?? steps.last?.id
        guard let targetId = targetId,
              let index = steps.firstIndex(where: { $0.id == targetId }) else {
            return
        }
        
        let newParam = JobParam()
        steps[index].params.append(newParam)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.requestedFocus = .key(targetId, newParam.id)
        }
    }
    
    func applyPreset(_ config: FutureJobConfig) {
        if steps.isEmpty {
            addStep()
        }
        let targetId = activeStepId ?? steps.last?.id
        guard let targetId = targetId,
              let index = steps.firstIndex(where: { $0.id == targetId }) else {
            return
        }
        
        steps[index].url = config.url
        steps[index].params = config.params
        requestedFocus = .url(targetId)
    }
    
    func cleanup() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

struct FutureJobConfigView: View {
    var job: Job
    @ObservedObject var service: JenkinsService
    @Binding var isPresented: Bool
    
    @StateObject private var viewModel = FutureJobConfigViewModel()
    @FocusState private var focusedField: ConfigFocusField?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Future Run Configuration")
                .font(.headline)
            
            Text("Trigger this job when parent finishes successfully:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button(action: {
                viewModel.reset()
            }) {
                Label("New Configuration", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .padding(.bottom, 2)

            HStack {
                Text("Saved Configs:")
                Picker("", selection: $viewModel.selectedConfig) {
                    Text("Select a preset...").tag(nil as FutureJobConfig?)
                    ForEach(service.savedConfigs, id: \.id) { config in
                        Text(config.url).tag(config as FutureJobConfig?)
                    }
                }
                .disabled(service.savedConfigs.isEmpty)
                .onChange(of: viewModel.selectedConfig) { newValue in
                    if let config = newValue {
                        viewModel.applyPreset(config)
                        viewModel.selectedConfig = nil
                    }
                }
            }
            
            Text("Steps")
                .font(.subheadline)
                .padding(.top, 6)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.steps.indices, id: \.self) { index in
                        let stepBinding = $viewModel.steps[index]
                        let stepId = stepBinding.wrappedValue.id
                        
                        GroupBox(label: HStack {
                            Text("Step \(index + 1)")
                                .font(.subheadline)
                            Spacer()
                            if viewModel.steps.count > 1 {
                                Button(action: {
                                    viewModel.removeStep(at: index)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove Step")
                            }
                        }) {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Job Path (e.g. job/my-project)", text: stepBinding.url)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focusedField, equals: .url(stepId))
                                
                                Text("Parameters")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(stepBinding.params) { $param in
                                        HStack {
                                            TextField("Key", text: $param.key)
                                                .textFieldStyle(.roundedBorder)
                                                .focused($focusedField, equals: .key(stepId, $param.wrappedValue.id))
                                            
                                            TextField("Value", text: $param.value)
                                                .textFieldStyle(.roundedBorder)
                                                .focused($focusedField, equals: .value(stepId, $param.wrappedValue.id))
                                            
                                            Button(action: {
                                                viewModel.steps[index].params.removeAll { $0.id == $param.wrappedValue.id }
                                            }) {
                                                Image(systemName: "minus.circle.fill")
                                                    .foregroundColor(.red)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                
                                Button(action: {
                                    viewModel.addParam(to: stepId)
                                }) {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Add Parameter")
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.top, 4)
                        }
                    }
                    
                    Button(action: {
                        viewModel.addStep()
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Step")
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            
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
        .onChange(of: focusedField) { viewModel.updateFocus($0) }
        .onChange(of: viewModel.requestedFocus) { focusedField = $0 }
        .onAppear {
            viewModel.setup(job: job)
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }
    
    func saveConfig() {
        var updatedJob = job
        let cleanedSteps = viewModel.steps.compactMap { step -> FutureJobConfig? in
            let trimmedUrl = step.url.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedUrl.isEmpty {
                return nil
            }
            var cleaned = step
            cleaned.url = trimmedUrl
            cleaned.params = step.params.filter { !$0.key.isEmpty }
            return cleaned
        }
        
        updatedJob.futureJobs = cleanedSteps
        cleanedSteps.forEach { service.saveFutureConfig($0) }
        
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
