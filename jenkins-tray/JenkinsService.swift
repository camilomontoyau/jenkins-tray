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
    @Published var futureJobDelay: Int = 2 // Default delay in minutes
    @Published var savedConfigs: [FutureJobConfig] = []
    
    var isConfigured: Bool {
        return !url.isEmpty && !username.isEmpty && !password.isEmpty
    }
    
    private var timer: Timer?
    private let synthesizer = AVSpeechSynthesizer()
    private let jobsKey = "saved_jenkins_jobs"
    private let urlKey = "jenkins_url"
    private let usernameKey = "jenkins_username"
    private let delayKey = "jenkins_future_delay"
    private let configsKey = "saved_future_configs"
    
    init() {
        loadSettings()
        loadJobs()
        startMonitoring()
    }
    
    func loadSettings() {
        url = UserDefaults.standard.string(forKey: urlKey) ?? ""
        username = UserDefaults.standard.string(forKey: usernameKey) ?? ""
        password = KeychainHelper.standard.read(service: "jenkins-tray", account: "jenkins_password") ?? ""
        
        // Load delay, default to 2 if not set (or set to 0 explicitly by user, though "integer(forKey:)" returns 0 if missing)
        // To distinguish between missing (default 2) and 0, we can check object.
        if UserDefaults.standard.object(forKey: delayKey) != nil {
            futureJobDelay = UserDefaults.standard.integer(forKey: delayKey)
        } else {
            futureJobDelay = 2
        }
        
        // Load saved configs
        if let data = UserDefaults.standard.data(forKey: configsKey),
           let decoded = try? JSONDecoder().decode([FutureJobConfig].self, from: data) {
            savedConfigs = decoded
        }
    }
    
    func saveSettings() {
        UserDefaults.standard.set(url, forKey: urlKey)
        UserDefaults.standard.set(username, forKey: usernameKey)
        UserDefaults.standard.set(futureJobDelay, forKey: delayKey)
        
        if let encoded = try? JSONEncoder().encode(savedConfigs) {
            UserDefaults.standard.set(encoded, forKey: configsKey)
        }
        
        if !password.isEmpty {
            KeychainHelper.standard.save(password, service: "jenkins-tray", account: "jenkins_password")
        }
        
        // Trigger an immediate check when settings change
        checkAllJobs()
    }
    
    func saveFutureConfig(_ config: FutureJobConfig) {
        var normalized = config
        normalized.url = normalizeJobUrl(config.url)

        if let existingIndex = savedConfigs.firstIndex(where: { normalizeJobUrl($0.url) == normalized.url }) {
            normalized.id = savedConfigs[existingIndex].id
            savedConfigs[existingIndex] = normalized
        } else {
            savedConfigs.append(normalized)
        }
        saveSettings()
    }
    
    func loadJobs() {
        if let data = UserDefaults.standard.data(forKey: jobsKey),
           let decoded = try? JSONDecoder().decode([Job].self, from: data) {
            
            // Deduplicate based on path
            var uniqueJobs = [Job]()
            var seenPaths = Set<String>()
            
            for job in decoded {
                if !seenPaths.contains(job.path) {
                    uniqueJobs.append(job)
                    seenPaths.insert(job.path)
                }
            }
            jobs = uniqueJobs
        }
    }
    
    func saveJobs() {
        if let encoded = try? JSONEncoder().encode(jobs) {
            UserDefaults.standard.set(encoded, forKey: jobsKey)
        }
    }
    
    // Helper methods to normalize and resolve full job URLs
    private func normalizeJobUrl(_ input: String) -> String {
        var cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasSuffix("/api/json") {
            cleaned = String(cleaned.dropLast(9))
        }
        while cleaned.hasSuffix("/") {
            cleaned.removeLast()
        }
        return cleaned
    }

    private func resolveJobUrl(_ input: String) -> String {
        let cleaned = normalizeJobUrl(input)
        if let parsed = URL(string: cleaned), parsed.scheme != nil {
            return cleaned
        }

        guard !url.isEmpty else { return cleaned }
        let base = normalizeJobUrl(url)
        let baseTrimmed = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let pathTrimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if pathTrimmed.isEmpty {
            return baseTrimmed
        }
        return "\(baseTrimmed)/\(pathTrimmed)"
    }

    private func extractBuildId(from input: String) -> String? {
        let cleaned = resolveJobUrl(input)
        let pathString: String
        if let parsed = URL(string: cleaned), parsed.scheme != nil {
            pathString = parsed.path
        } else {
            pathString = cleaned
        }
        let components = pathString.split(separator: "/")
        guard let last = components.last, let buildIdInt = Int(last) else {
            return nil
        }
        return String(buildIdInt)
    }

    func addJob(path: String, futureJobs: [FutureJobConfig] = []) {
        let cleanedUrl = resolveJobUrl(path)
        
        guard let buildId = extractBuildId(from: cleanedUrl) else {
            print("Error: Could not extract build ID from url: \(cleanedUrl)")
            return
        }
        
        let newJob = Job(path: cleanedUrl, buildId: buildId, status: .running, lastChecked: Date(), futureJobs: futureJobs)
        
        DispatchQueue.main.async {
            if !self.jobs.contains(where: { $0.path == cleanedUrl }) {
                self.jobs.insert(newJob, at: 0)
                self.saveJobs()
                self.checkJob(newJob) // Check immediately
            }
        }
    }
    
    func removeJob(id: UUID) {
        jobs.removeAll { $0.id == id }
        saveJobs()
    }
    
    func updateJob(_ job: Job) {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
            saveJobs()
        }
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
        let resolved = resolveJobUrl(job.path)
        guard !resolved.isEmpty else { return "" }
        return "\(resolved)/api/json"
    }

    func getJobWebUrl(for job: Job) -> URL? {
        let resolved = resolveJobUrl(job.path)
        return resolved.isEmpty ? nil : URL(string: resolved)
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
                
                if status == .success, let firstFuture = updatedJob.futureJobs.first {
                    let remainingChain = Array(updatedJob.futureJobs.dropFirst())
                    let delaySeconds = Double(futureJobDelay * 60)
                    print("Scheduling future job trigger in \(futureJobDelay) minutes (\(delaySeconds) seconds)")
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds) { [weak self] in
                        self?.triggerFutureJob(config: firstFuture, parent: updatedJob, remainingChain: remainingChain)
                    }
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
    
    // MARK: - Future Job Triggering
    
    func triggerFutureJob(config: FutureJobConfig, parent: Job, remainingChain: [FutureJobConfig] = []) {
        guard !config.url.isEmpty else { return }
        
        // Construct build URL from the full job URL (no path extraction)
        let baseJobUrl = resolveJobUrl(config.url)
        let endpoint = config.params.isEmpty ? "build" : "buildWithParameters"
        let buildUrlString = "\(baseJobUrl)/\(endpoint)"
        
        guard var components = URLComponents(string: buildUrlString) else {
            print("Invalid URL for future job: \(buildUrlString)")
            return
        }
        
        // Add Query Params
        if !config.params.isEmpty {
            components.queryItems = config.params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        
        guard let apiURL = components.url else { return }
        
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        
        // Auth
        if !username.isEmpty && !password.isEmpty {
            let loginString = "\(username):\(password)"
            if let loginData = loginString.data(using: .utf8) {
                let base64LoginString = loginData.base64EncodedString()
                request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
            }
        }
        
        // For some Jenkins versions, crumb issuer might be needed, but assuming basic auth or token is enough for now.
        // Or if CSRF is enabled, we might need a crumb.
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Error triggering future job: \(error.localizedDescription)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 201, let location = httpResponse.allHeaderFields["Location"] as? String {
                    // Location header points to queue item
                    print("Future job triggered. Queue Item: \(location)")
                    self.monitorQueueItem(url: location, jobPath: baseJobUrl, remainingChain: remainingChain)
                } else {
                    print("Failed to trigger future job. Status: \(httpResponse.statusCode)")
                }
            }
        }.resume()
    }
    
    func monitorQueueItem(url: String, jobPath: String, remainingChain: [FutureJobConfig] = []) {
        // Poll the queue item until we get an executable URL
        guard let queueUrl = URL(string: url + "api/json") else { return }
        
        var request = URLRequest(url: queueUrl)
        if !username.isEmpty && !password.isEmpty {
            let loginString = "\(username):\(password)"
            if let loginData = loginString.data(using: .utf8) {
                let base64LoginString = loginData.base64EncodedString()
                request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
            }
        }
        
        // We need a delayed recursive call or a separate timer. 
        // A simple recursive dispatch after delay is easiest for this one-off task.
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { [weak self] in
            URLSession.shared.dataTask(with: request) { data, response, error in
                guard let self = self else { return }
                
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    if let executable = json["executable"] as? [String: Any],
                       let number = executable["number"] as? Int {
                        
                        // We found the build!
                        print("Queue item executed. Build #\(number)")
                        
                        // Instead of relying on executable["url"], construct path from jobPath and number
                        let newJobUrl = "\(jobPath)/\(number)"
                        self.addJob(path: newJobUrl, futureJobs: remainingChain)
                        
                    } else {
                        // Still in queue or logic differs, keep polling
                        // Add a limit to avoid infinite loops? 
                        // For now just keep polling every 5 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            self.monitorQueueItem(url: url, jobPath: jobPath, remainingChain: remainingChain)
                        }
                    }
                }
            }.resume()
        }
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

