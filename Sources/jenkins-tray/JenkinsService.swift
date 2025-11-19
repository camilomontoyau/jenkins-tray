import Foundation
import AppKit
import Combine
import UserNotifications

class JenkinsService: ObservableObject {
    @Published var jobs: [Job] = []
    @Published var url: String = ""
    @Published var username: String = ""
    @Published var password: String = ""
    
    private var timer: Timer?
    private let synthesizer = NSSpeechSynthesizer()
    private let jobsKey = "saved_jenkins_jobs"
    private let urlKey = "jenkins_url"
    private let usernameKey = "jenkins_username"
    private let passwordKey = "jenkins_password" // In a real app, use Keychain
    
    init() {
        loadSettings()
        loadJobs()
        startMonitoring()
    }
    
    func loadSettings() {
        url = UserDefaults.standard.string(forKey: urlKey) ?? ""
        username = UserDefaults.standard.string(forKey: usernameKey) ?? ""
        password = UserDefaults.standard.string(forKey: passwordKey) ?? ""
    }
    
    func saveSettings() {
        UserDefaults.standard.set(url, forKey: urlKey)
        UserDefaults.standard.set(username, forKey: usernameKey)
        UserDefaults.standard.set(password, forKey: passwordKey)
        // Restart monitoring if settings change might be good, but next tick will pick it up
    }
    
    func loadJobs() {
        if let data = UserDefaults.standard.data(forKey: jobsKey),
           let decoded = try? JSONDecoder().decode([Job].self, from: data) {
            jobs = decoded
        }
    }
    
    func saveJobs() {
        if let encoded = try? JSONEncoder().encode(jobs) {
            UserDefaults.standard.set(encoded, forKey: jobsKey)
        }
    }
    
    func addJob(path: String) {
        let cleanedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        // Extract build ID (last component)
        let components = cleanedPath.split(separator: "/")
        guard let last = components.last, let _ = Int(last) else {
            // If no build ID found, maybe assume it's a job path and user wants latest? 
            // But requirement says "identify the job and its id".
            // We'll assume the format includes the ID at the end.
            return
        }
        
        let buildId = String(last)
        let newJob = Job(path: cleanedPath, buildId: buildId, status: .running) // Assume running initially
        
        DispatchQueue.main.async {
            if !self.jobs.contains(where: { $0.path == cleanedPath }) {
                self.jobs.append(newJob)
                self.saveJobs()
                self.checkJob(newJob) // Check immediately
            }
        }
    }
    
    func removeJob(id: UUID) {
        jobs.removeAll { $0.id == id }
        saveJobs()
    }
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkAllJobs()
        }
    }
    
    func checkAllJobs() {
        for job in jobs {
            if job.status == .running || job.status == .unknown {
                checkJob(job)
            }
        }
    }
    
    func checkJob(_ job: Job) {
        guard !url.isEmpty else { return }
        
        // Construct URL
        // Base: https://my-jenkins.company.com
        // Path: job/development/job/whatever/job/my-job-name/9694
        // Full: https://my-jenkins.company.com/job/development/job/whatever/job/my-job-name/9694/api/json
        
        let baseUrl = url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let jobPath = job.path
        let fullUrlString = "\(baseUrl)/\(jobPath)/api/json"
        
        guard let apiURL = URL(string: fullUrlString) else { return }
        
        var request = URLRequest(url: apiURL)
        
        // Auth
        if !username.isEmpty && !password.isEmpty {
            let loginString = "\(username):\(password)"
            if let loginData = loginString.data(using: .utf8) {
                let base64LoginString = loginData.base64EncodedString()
                request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
            }
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data else { return }
            
            if let httpResponse = response as? HTTPURLResponse {
                 // print("Status code: \(httpResponse.statusCode)")
                 if httpResponse.statusCode != 200 {
                     // Handle error or wait
                     return
                 }
            }
            
            do {
                let jenkinsResp = try JSONDecoder().decode(JenkinsResponse.self, from: data)
                
                DispatchQueue.main.async {
                    if let index = self.jobs.firstIndex(where: { $0.id == job.id }) {
                        var updatedJob = self.jobs[index]
                        updatedJob.lastChecked = Date()
                        
                        if let result = jenkinsResp.result {
                            // Job finished
                            let newStatus = JobStatus(rawValue: result) ?? .unknown
                            if updatedJob.status != newStatus {
                                updatedJob.status = newStatus
                                self.notify(job: updatedJob)
                            }
                        } else if let building = jenkinsResp.building, building {
                            updatedJob.status = .running
                        }
                        
                        self.jobs[index] = updatedJob
                        self.saveJobs()
                    }
                }
            } catch {
                print("Decoding error: \(error)")
            }
        }.resume()
    }
    
    func notify(job: Job) {
        let text = "Job number \(job.buildId) done. Status: \(job.status.rawValue)"
        synthesizer.startSpeaking(text)
        
        // Notification content matching the screenshot style
        let title = "Jenkins Monitor"
        let subtitle = "Job #\(job.buildId)"
        let body = "Status: \(job.status.rawValue)"
        
        if Bundle.main.bundleIdentifier != nil {
            let content = UNMutableNotificationContent()
            content.title = title
            content.subtitle = subtitle
            content.body = body
            content.sound = UNNotificationSound.default
            
            let request = UNNotificationRequest(identifier: job.id.uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        } else {
            // Fallback for CLI/Development mode using AppleScript
            sendFallbackNotification(title: title, subtitle: subtitle, body: body)
        }
    }
    
    func sendFallbackNotification(title: String, subtitle: String, body: String) {
        // AppleScript: display notification "message" with title "title" subtitle "subtitle"
        // Sanitize inputs (basic)
        let safeTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let safeSubtitle = subtitle.replacingOccurrences(of: "\"", with: "\\\"")
        let safeBody = body.replacingOccurrences(of: "\"", with: "\\\"")
        
        let script = "display notification \"\(safeBody)\" with title \"\(safeTitle)\" subtitle \"\(safeSubtitle)\""
        
        let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-e", script]
        process.launch()
    }
}
