import Foundation

/// Service for managing local data persistence
class PersistenceService: ObservableObject {
    private let userDefaults = UserDefaults.standard
    private let projectsKey = "GlyphProjects"
    private let settingsKey = "GlyphSettings"
    
    // MARK: - Project Persistence
    
    func saveProjects(_ projects: [Project]) {
        do {
            let encoded = try JSONEncoder().encode(projects)
            userDefaults.set(encoded, forKey: projectsKey)
            print("✅ Saved \(projects.count) projects")
        } catch {
            print("❌ Failed to save projects: \(error)")
        }
    }
    
    func loadProjects() -> [Project] {
        guard let data = userDefaults.data(forKey: projectsKey) else {
            print("📂 No saved projects found")
            return []
        }
        
        do {
            let projects = try JSONDecoder().decode([Project].self, from: data)
            print("✅ Loaded \(projects.count) projects")
            return projects
        } catch {
            print("❌ Failed to load projects: \(error)")
            return []
        }
    }
    
    func deleteAllProjects() {
        userDefaults.removeObject(forKey: projectsKey)
        print("🗑️ Deleted all projects")
    }
    
    // MARK: - Settings Persistence
    
    struct AppSettings: Codable {
        var isOnlineMode: Bool = true
        var pythonPath: String = ""
        var lastPythonCheck: Date?
        var selectedTheme: String = "system"
        var autoSave: Bool = true
        var maxRecentProjects: Int = 10
    }
    
    func saveSettings(_ settings: AppSettings) {
        do {
            let encoded = try JSONEncoder().encode(settings)
            userDefaults.set(encoded, forKey: settingsKey)
            print("✅ Settings saved")
        } catch {
            print("❌ Failed to save settings: \(error)")
        }
    }
    
    func loadSettings() -> AppSettings {
        guard let data = userDefaults.data(forKey: settingsKey) else {
            print("📋 Using default settings")
            return AppSettings()
        }
        
        do {
            let settings = try JSONDecoder().decode(AppSettings.self, from: data)
            print("✅ Settings loaded")
            return settings
        } catch {
            print("❌ Failed to load settings, using defaults: \(error)")
            return AppSettings()
        }
    }
    
    // MARK: - File System Utilities
    
    /// Get documents directory for the app
    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    /// Export project to JSON file
    func exportProject(_ project: Project) -> URL? {
        let documentsPath = getDocumentsDirectory()
        let fileName = "\(project.name.replacingOccurrences(of: " ", with: "_")).json"
        let fileURL = documentsPath.appendingPathComponent(fileName)
        
        do {
            let encoded = try JSONEncoder().encode(project)
            try encoded.write(to: fileURL)
            print("✅ Project exported to: \(fileURL.path)")
            return fileURL
        } catch {
            print("❌ Failed to export project: \(error)")
            return nil
        }
    }
    
    /// Import project from JSON file
    func importProject(from url: URL) -> Project? {
        do {
            let data = try Data(contentsOf: url)
            let project = try JSONDecoder().decode(Project.self, from: data)
            print("✅ Project imported from: \(url.path)")
            return project
        } catch {
            print("❌ Failed to import project: \(error)")
            return nil
        }
    }
    
    // MARK: - Cache Management
    
    /// Clear all cached data
    func clearCache() {
        // Remove temporary files if any
        let tempDirectory = FileManager.default.temporaryDirectory
        let glyphTempPath = tempDirectory.appendingPathComponent("Glyph")
        
        if FileManager.default.fileExists(atPath: glyphTempPath.path) {
            do {
                try FileManager.default.removeItem(at: glyphTempPath)
                print("🧹 Cache cleared")
            } catch {
                print("❌ Failed to clear cache: \(error)")
            }
        }
    }
    
    /// Get app storage information
    func getStorageInfo() -> [String: Any] {
        let documentsPath = getDocumentsDirectory()
        
        var totalSize: Int64 = 0
        var fileCount = 0
        
        if let enumerator = FileManager.default.enumerator(at: documentsPath, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                do {
                    let fileAttributes = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                    if let fileSize = fileAttributes.fileSize {
                        totalSize += Int64(fileSize)
                        fileCount += 1
                    }
                } catch {
                    print("⚠️ Error reading file size: \(error)")
                }
            }
        }
        
        return [
            "totalSize": totalSize,
            "fileCount": fileCount,
            "documentsPath": documentsPath.path
        ]
    }
} 