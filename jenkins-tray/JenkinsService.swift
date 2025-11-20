import Foundation
import AppKit
import Combine
import UserNotifications
import Security
import AVFoundation

class JenkinsService: ObservableObject {
    @Published var jobs: [Job] = []
    @Published var url: String = ""
    @Published var username: String = ""
    @Published var password: String = ""
    
    var isConfigured: Bool {
        return !url.isEmpty && !username.isEmpty && !password.isEmpty
    }
    
    private var timer: Timer?
    private let synthesizer = AVSpeechSynthesizer()
    private let jobsKey = "saved_jenkins_jobs"
    private let urlKey = "jenkins_url"
    private let usernameKey = "jenkins_username"
    
    init() {
        loadSettings()
        loadJobs()
        startMonitoring()
    }
    
    func loadSettings() {
        url = UserDefaults.standard.string(forKey: urlKey) ?? ""
        username = UserDefaults.standard.string(forKey: usernameKey) ?? ""
        password = KeychainHelper.standard.read(service: "jenkins-tray", account: "jenkins_password") ?? ""
    }
    
    func saveSettings() {
        UserDefaults.standard.set(url, forKey: urlKey)
        UserDefaults.standard.set(username, forKey: usernameKey)
        
        if !password.isEmpty {
            KeychainHelper.standard.save(password, service: "jenkins-tray", account: "jenkins_password")
        }
        
        // Trigger an immediate check when settings change
        checkAllJobs()
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
        var cleanedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle full URL input
        if let inputUrl = URL(string: cleanedPath), inputUrl.scheme != nil {
            // User pasted a full URL (e.g., https://jenkins.com/me/my-views/view/all/job/dev/job/build/123/api/json)
            // Extract the path component
            var fullPath = inputUrl.path
            
            // Remove /api/json if present (user might paste the full API URL)
            if fullPath.hasSuffix("/api/json") {
                fullPath = String(fullPath.dropLast(9)) // Remove "/api/json"
            }
            
            // Find the first "/job/" occurrence and extract everything from there
            if let jobRange = fullPath.range(of: "/job/") {
                // Extract everything from the first "/job/" forward
                cleanedPath = String(fullPath[jobRange.lowerBound...])
                // Remove leading slash to get "job/..."
                cleanedPath = cleanedPath.hasPrefix("/") ? String(cleanedPath.dropFirst()) : cleanedPath
            } else {
                // No "/job/" found, use the whole path (minus /api/json if it was there)
                cleanedPath = fullPath.hasPrefix("/") ? String(fullPath.dropFirst()) : fullPath
            }
        } else {
            // Not a full URL, but check if it contains "/job/" and extract from there
            // Also remove /api/json if present
            if cleanedPath.hasSuffix("/api/json") {
                cleanedPath = String(cleanedPath.dropLast(9))
            }
            
            if let jobRange = cleanedPath.range(of: "/job/") {
                cleanedPath = String(cleanedPath[jobRange.lowerBound...])
                cleanedPath = cleanedPath.hasPrefix("/") ? String(cleanedPath.dropFirst()) : cleanedPath
            }
        }
        
        // Remove trailing slashes and normalize (remove any double slashes in the path)
        cleanedPath = cleanedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        cleanedPath = normalizePath(cleanedPath)
        
        // Extract build ID (last component) - must be a number
        let components = cleanedPath.split(separator: "/")
        guard let last = components.last, let buildIdInt = Int(last) else {
            // Invalid format - no build ID found
            print("Error: Could not extract build ID from path: \(cleanedPath)")
            return
        }
        
        let buildId = String(buildIdInt)
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
        // Check every 10 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkAllJobs()
        }
    }
    
    func checkAllJobs() {
        guard isConfigured else { return }
        for job in jobs {
            // We continue checking even if it failed previously, to recover from network errors
            if job.status != .success && job.status != .failure && job.status != .aborted {
                checkJob(job)
            }
        }
    }
    
    func getApiUrl(for job: Job) -> String {
        guard !url.isEmpty else { return "" }
        
        // Construct URL ensuring no double slashes (except in protocol)
        // Remove trailing slashes from base URL (but preserve protocol)
        var baseUrl = url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        // Normalize job path (remove leading/trailing slashes and double slashes)
        var jobPath = job.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        jobPath = normalizePath(jobPath)
        
        // Construct the full URL: baseUrl + "/" + jobPath + "/api/json"
        // This ensures exactly one slash between each component
        return "\(baseUrl)/\(jobPath)/api/json"
    }
    
    func checkJob(_ job: Job) {
        guard !url.isEmpty else { return }
        
        let fullUrlString = getApiUrl(for: job)
        
        guard let apiURL = URL(string: fullUrlString) else {
            print("Invalid URL: \(fullUrlString)")
            updateJobStatus(job, status: .unknown)
            return
        }
        
        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 15 // Timeout after 15 seconds
        
        // Auth
        if !username.isEmpty && !password.isEmpty {
            let loginString = "\(username):\(password)"
            if let loginData = loginString.data(using: .utf8) {
                let base64LoginString = loginData.base64EncodedString()
                request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
            }
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            // Handle network error
            if let error = error {
                print("Network error for \(job.buildId): \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.updateJobStatus(job, status: .networkError)
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                 if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                     print("Auth Error for \(job.buildId)")
                     DispatchQueue.main.async {
                         self.updateJobStatus(job, status: .authError)
                     }
                     return
                 }
                 
                 if httpResponse.statusCode == 404 {
                     print("Job not found (404): \(fullUrlString)")
                     DispatchQueue.main.async {
                         self.updateJobStatus(job, status: .unknown) // Or a specific 'notFound' status
                     }
                     return
                 }
                 
                 if httpResponse.statusCode != 200 {
                     print("HTTP Error \(httpResponse.statusCode) for \(job.buildId)")
                     DispatchQueue.main.async {
                         self.updateJobStatus(job, status: .networkError)
                     }
                     return
                 }
            }
            
            guard let data = data else { return }
            
            do {
                let jenkinsResp = try JSONDecoder().decode(JenkinsResponse.self, from: data)
                
                DispatchQueue.main.async {
                    if let result = jenkinsResp.result {
                        // Job finished
                        let newStatus = JobStatus(rawValue: result) ?? .unknown
                        self.updateJobStatus(job, status: newStatus)
                    } else if let building = jenkinsResp.building, building {
                        self.updateJobStatus(job, status: .running)
                    } else {
                        // Result is null and building is false (e.g. in queue or just started)
                        self.updateJobStatus(job, status: .running)
                    }
                }
            } catch {
                print("Decoding error for \(job.buildId): \(error)")
                // Try to print string to debug
                if let str = String(data: data, encoding: .utf8) {
                    print("Response: \(str)")
                }
                DispatchQueue.main.async {
                    self.updateJobStatus(job, status: .unknown)
                }
            }
        }.resume()
    }
    
    func updateJobStatus(_ job: Job, status: JobStatus) {
        if let index = self.jobs.firstIndex(where: { $0.id == job.id }) {
            var updatedJob = self.jobs[index]
            updatedJob.lastChecked = Date()
            
            // Only notify if status changed AND it's a completion status
            if updatedJob.status != status {
                updatedJob.status = status
                
                if status == .success || status == .failure || status == .aborted {
                    self.notify(job: updatedJob)
                }
            }
            
            self.jobs[index] = updatedJob
            self.saveJobs()
        }
    }
    
    func notify(job: Job) {
        let text = "Job number \(job.buildId) done. Status: \(job.status.rawValue)"
        DispatchQueue.main.async {
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            self.synthesizer.speak(utterance)
        }
        
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
    
    // Helper function to remove double slashes from paths
    // This only works on paths (not full URLs with protocols)
    private func normalizePath(_ path: String) -> String {
        var normalized = path
        // Remove all double slashes (but preserve single slashes)
        while normalized.contains("//") {
            normalized = normalized.replacingOccurrences(of: "//", with: "/")
        }
        return normalized
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

class KeychainHelper {
    static let standard = KeychainHelper()
    private init() {}
    
    func save(_ data: Data, service: String, account: String) {
        let query = [
            kSecValueData: data,
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ] as CFDictionary
        
        // Delete existing item
        SecItemDelete(query)
        
        // Add new item
        SecItemAdd(query, nil)
    }
    
    func save(_ string: String, service: String, account: String) {
        if let data = string.data(using: .utf8) {
            save(data, service: service, account: account)
        }
    }
    
    func read(service: String, account: String) -> Data? {
        let query = [
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecClass: kSecClassGenericPassword,
            kSecReturnData: true
        ] as CFDictionary
        
        var result: AnyObject?
        SecItemCopyMatching(query, &result)
        
        return result as? Data
    }
    
    func read(service: String, account: String) -> String? {
        let data: Data? = read(service: service, account: account)
        if let data = data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    func delete(service: String, account: String) {
        let query = [
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecClass: kSecClassGenericPassword,
        ] as CFDictionary
        
        SecItemDelete(query)
    }
}

