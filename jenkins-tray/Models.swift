import Foundation

enum JobStatus: String, Codable {
    case running = "running"
    case success = "SUCCESS"
    case failure = "FAILURE"
    case aborted = "ABORTED"
    case authError = "AUTH_ERROR"
    case networkError = "NETWORK_ERROR"
    case unknown = "UNKNOWN"
}

struct Job: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var path: String // The full path string like "job/dev/..."
    var buildId: String
    var status: JobStatus = .unknown
    var lastChecked: Date = Date()
    
    var displayName: String {
        let parts = path.split(separator: "/")
        let names = parts.filter { $0 != "job" && Int($0) == nil }
        return names.joined(separator: " / ")
    }
}

struct JenkinsResponse: Codable {
    let result: String?
    let building: Bool?
}
