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
    var path: String // Full job URL (with build id)
    var buildId: String
    var status: JobStatus = .unknown
    var lastChecked: Date = Date()
    var futureJobs: [FutureJobConfig] = []
    
    var displayName: String {
        let pathString: String
        if let url = URL(string: path), url.scheme != nil {
            pathString = url.path
        } else {
            pathString = path
        }

        let parts = pathString.split(separator: "/")
        let names = parts.filter { $0 != "job" && Int($0) == nil }
        return names.joined(separator: " / ")
    }

    init(
        id: UUID = UUID(),
        path: String,
        buildId: String,
        status: JobStatus = .unknown,
        lastChecked: Date = Date(),
        futureJobs: [FutureJobConfig] = []
    ) {
        self.id = id
        self.path = path
        self.buildId = buildId
        self.status = status
        self.lastChecked = lastChecked
        self.futureJobs = futureJobs
    }

    enum CodingKeys: String, CodingKey {
        case id, path, buildId, status, lastChecked, futureJobs, futureJob
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        path = try container.decode(String.self, forKey: .path)
        buildId = try container.decode(String.self, forKey: .buildId)
        status = try container.decodeIfPresent(JobStatus.self, forKey: .status) ?? .unknown
        lastChecked = try container.decodeIfPresent(Date.self, forKey: .lastChecked) ?? Date()

        let decodedFutureJobs = try container.decodeIfPresent([FutureJobConfig].self, forKey: .futureJobs) ?? []
        if decodedFutureJobs.isEmpty, let legacyFuture = try container.decodeIfPresent(FutureJobConfig.self, forKey: .futureJob) {
            futureJobs = [legacyFuture]
        } else {
            futureJobs = decodedFutureJobs
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(path, forKey: .path)
        try container.encode(buildId, forKey: .buildId)
        try container.encode(status, forKey: .status)
        try container.encode(lastChecked, forKey: .lastChecked)
        try container.encode(futureJobs, forKey: .futureJobs)
    }
}

struct JobParam: Identifiable, Codable, Hashable {
    var id = UUID()
    var key: String = ""
    var value: String = ""
}

struct FutureJobConfig: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var url: String = ""
    var params: [JobParam] = []

    enum CodingKeys: String, CodingKey {
        case id, url, params
    }

    init(id: UUID = UUID(), url: String = "", params: [JobParam] = []) {
        self.id = id
        self.url = url
        self.params = params
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        params = try container.decodeIfPresent([JobParam].self, forKey: .params) ?? []
    }
}

struct JenkinsResponse: Codable {
    let result: String?
    let building: Bool?
}
