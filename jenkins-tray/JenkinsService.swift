import Foundation
import Combine

final class JenkinsService: ObservableObject {
    // Settings
    @Published var url: String = ""
    @Published var username: String = ""
    @Published var password: String = ""
    
    // Jobs
    @Published private(set) var jobs: [Job] = []
    
    var isConfigured: Bool {
        // Basic check that settings are present
        !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - Public API
    func addJob(path: String) {
        var cleanedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle full URL input
        if cleanedPath.lowercased().hasPrefix("http") {
            if let url = URL(string: cleanedPath) {
                let fullPath = url.path
                cleanedPath = fullPath.hasPrefix("/") ? String(fullPath.dropFirst()) : fullPath
            }
        }
        
        cleanedPath = cleanedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        // Extract build ID (last component)
        let components = cleanedPath.split(separator: "/")
        guard let last = components.last, Int(last) != nil else {
            return
        }
        
        let buildId = String(last)
        let newJob = Job(path: cleanedPath, buildId: buildId, status: .unknown)
        
        if !jobs.contains(where: { $0.path == cleanedPath }) {
            jobs.append(newJob)
            saveJobs()
            checkJob(newJob)
        }
    }
    
    func removeJob(id: UUID) {
        if let idx = jobs.firstIndex(where: { $0.id == id }) {
            jobs.remove(at: idx)
            saveJobs()
        }
    }
    
    func saveSettings() {
        // Persist settings as needed. This is a stub to satisfy the UI.
    }
    
    // MARK: - Private helpers
    private func saveJobs() {
        // Persist jobs array to storage if needed
    }
    
    private func checkJob(_ job: Job) {
        // Replace with real network call. For now, simulate an update to demonstrate flow.
        // After some background work, update status on main thread.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            if let idx = self.jobs.firstIndex(where: { $0.path == job.path }) {
                // Randomly assign a status for placeholder logic
                let statuses: [JobStatus] = [.running, .success, .failure, .aborted, .unknown]
                self.jobs[idx].status = statuses.randomElement() ?? .unknown
                self.jobs[idx].lastChecked = Date()
            }
        }
    }
}
