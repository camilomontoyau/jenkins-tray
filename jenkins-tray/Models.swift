import Foundation

enum JobStatus: String, Codable {
    case running
    case success = "SUCCESS"
    case failure = "FAILURE"
    case aborted = "ABORTED"
    case authError = "AUTH_ERROR"
    case networkError = "NETWORK_ERROR"
    case unknown
}

struct Job: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var path: String // The full path string like "job/dev/..."
    var buildId: String
    var status: JobStatus = .unknown
    var lastChecked: Date = Date()
    
    var displayName: String {
        // Extract a readable name if possible, or just use path
        // path: job/development/job/whatever/job/my-job-name/9694/
        let parts = path.split(separator: "/")
        // filter out "job" and numbers?
        let names = parts.filter { $0 != "job" && Int($0) == nil }
        return names.joined(separator: " / ")
    }
}

struct JenkinsResponse: Codable {
    let result: String?
    let building: Bool?
}

