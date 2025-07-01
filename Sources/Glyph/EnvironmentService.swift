import Foundation

/// Service for managing environment variables and .env file configuration
@MainActor
class EnvironmentService: ObservableObject {
    static let shared = EnvironmentService()
    
    @Published var isConfigured = false
    @Published var availableKeys: Set<String> = []
    
    private var envVariables: [String: String] = [:]
    
    private init() {
        loadEnvironmentVariables()
    }
    
    // MARK: - Environment Loading
    
    private func loadEnvironmentVariables() {
        // First load from .env file
        loadDotEnvFile()
        
        // Then merge with system environment variables (they take precedence)
        mergeSystemEnvironment()
        
        // Track which keys are available
        updateAvailableKeys()
        
        isConfigured = !envVariables.isEmpty
    }
    
    private func loadDotEnvFile() {
        guard let envPath = Bundle.main.path(forResource: ".env", ofType: nil) ?? findDotEnvFile() else {
            print("📄 No .env file found - using system environment variables only")
            return
        }
        
        do {
            let envContent = try String(contentsOfFile: envPath)
            parseDotEnvContent(envContent)
            print("✅ Loaded .env file from: \(envPath)")
        } catch {
            print("⚠️ Error reading .env file: \(error)")
        }
    }
    
    private func findDotEnvFile() -> String? {
        let possiblePaths = [
            // Current working directory
            FileManager.default.currentDirectoryPath + "/.env",
            // Project root (common locations)
            Bundle.main.bundlePath + "/../../../.env",
            Bundle.main.bundlePath + "/../../.env",
            Bundle.main.bundlePath + "/../.env",
            // User home directory
            NSHomeDirectory() + "/.env"
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        return nil
    }
    
    private func parseDotEnvContent(_ content: String) {
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip empty lines and comments
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                continue
            }
            
            // Parse KEY=VALUE format
            let components = trimmedLine.components(separatedBy: "=")
            guard components.count >= 2 else { continue }
            
            let key = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = components.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Remove quotes if present
            let cleanValue = value.hasPrefix("\"") && value.hasSuffix("\"") ? String(value.dropFirst().dropLast()) : value
            
            envVariables[key] = cleanValue
        }
    }
    
    private func mergeSystemEnvironment() {
        // System environment variables take precedence
        for (key, value) in ProcessInfo.processInfo.environment {
            envVariables[key] = value
        }
    }
    
    private func updateAvailableKeys() {
        let requiredKeys = ["OPENAI_API_KEY", "TAVILY_API_KEY", "LANGCHAIN_API_KEY"]
        availableKeys = Set(requiredKeys.filter { getAPIKey(for: $0) != nil })
    }
    
    // MARK: - API Key Access
    
    func getAPIKey(for key: String) -> String? {
        // First check our loaded environment variables
        if let value = envVariables[key], !value.isEmpty {
            return value
        }
        
        // Fallback to UserDefaults for development/testing
        return UserDefaults.standard.string(forKey: key)
    }
    
    func hasAPIKey(for key: String) -> Bool {
        return getAPIKey(for: key) != nil
    }
    
    func validateAPIKeys() -> [String: Bool] {
        let requiredKeys = [
            "OPENAI_API_KEY",
            "TAVILY_API_KEY"
        ]
        
        let optionalKeys = [
            "LANGCHAIN_API_KEY"
        ]
        
        var status: [String: Bool] = [:]
        
        for key in requiredKeys + optionalKeys {
            status[key] = hasAPIKey(for: key)
        }
        
        return status
    }
    
    // MARK: - Configuration Status
    
    var isFullyConfigured: Bool {
        hasAPIKey(for: "OPENAI_API_KEY") && hasAPIKey(for: "TAVILY_API_KEY")
    }
    
    var missingRequiredKeys: [String] {
        let required = ["OPENAI_API_KEY", "TAVILY_API_KEY"]
        return required.filter { !hasAPIKey(for: $0) }
    }
    
    var configurationMessage: String {
        if isFullyConfigured {
            return "✅ All required API keys configured"
        } else {
            let missing = missingRequiredKeys.joined(separator: ", ")
            return "⚠️ Missing required API keys: \(missing)"
        }
    }
    
    // MARK: - Development Helpers
    
    func setAPIKey(_ key: String, value: String) {
        // For development/testing only
        UserDefaults.standard.set(value, forKey: key)
        envVariables[key] = value
        updateAvailableKeys()
    }
    
    func clearAPIKey(_ key: String) {
        UserDefaults.standard.removeObject(forKey: key)
        envVariables.removeValue(forKey: key)
        updateAvailableKeys()
    }
    
    func reloadConfiguration() {
        envVariables.removeAll()
        loadEnvironmentVariables()
    }
} 