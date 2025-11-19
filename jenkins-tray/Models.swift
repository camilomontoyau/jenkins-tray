import Foundation

enum JobStatus: String, Codable {
    case running
    case success
    case failure
    case aborted
    case authError
    case networkError
    case unknown
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
