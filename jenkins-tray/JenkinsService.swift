    func addJob(path: String) {
        var cleanedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle full URL input
        if cleanedPath.lowercased().hasPrefix("http") {
            if let url = URL(string: cleanedPath) {
                // url.path returns "/job/dev/..."
                // We want "job/dev/..." (no leading slash)
                let fullPath = url.path
                if fullPath.hasPrefix("/") {
                    cleanedPath = String(fullPath.dropFirst())
                } else {
                    cleanedPath = fullPath
                }
            }
        }
        
        cleanedPath = cleanedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
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
