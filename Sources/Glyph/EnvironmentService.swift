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
            print("🔍 Bundle path: \(Bundle.main.bundlePath)")
            print("🔍 Current directory: \(FileManager.default.currentDirectoryPath)")
            return
        }
        
        do {
            let envContent = try String(contentsOfFile: envPath)
            print("✅ Loaded .env file from: \(envPath)")
            print("🔍 .env file size: \(envContent.count) characters")
            parseDotEnvContent(envContent)
        } catch {
            print("⚠️ Error reading .env file: \(error)")
        }
    }
    
    private func findDotEnvFile() -> String? {
        let possiblePaths = [
            // Current working directory
            FileManager.default.currentDirectoryPath + "/.env",
            // Project root from bundle (for .build/Glyph.app/Contents/MacOS location)
            Bundle.main.bundlePath + "/../../../../.env",
            Bundle.main.bundlePath + "/../../../.env",
            Bundle.main.bundlePath + "/../../.env",
            Bundle.main.bundlePath + "/../.env",
            // User home directory
            NSHomeDirectory() + "/.env"
        ]
        
        print("🔍 Searching for .env file in paths:")
        for path in possiblePaths {
            print("🔍   Checking: \(path)")
            if FileManager.default.fileExists(atPath: path) {
                print("🔍   ✅ Found at: \(path)")
                return path
            } else {
                print("🔍   ❌ Not found")
            }
        }
        
        return nil
    }
    
    private func parseDotEnvContent(_ content: String) {
        let lines = content.components(separatedBy: .newlines)
        print("🔍 Parsing .env with \(lines.count) lines")
        
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
            
            // Log API keys found
            if key.contains("API_KEY") {
                let maskedValue = String(cleanValue.prefix(10)) + "..." + String(cleanValue.suffix(10))
                print("🔍 Found API key: \(key) = \(maskedValue)")
            }
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
        
        // Debug: Log all environment variables loaded
        print("🔍 Total environment variables loaded: \(envVariables.count)")
        for key in requiredKeys {
            let hasKey = getAPIKey(for: key) != nil
            print("🔍 API Key status: \(key) = \(hasKey ? "✅ Found" : "❌ Missing")")
        }
        
        // Log LangSmith configuration status
        if hasAPIKey(for: "LANGCHAIN_API_KEY") {
            let tracingEnabled = getAPIKey(for: "LANGCHAIN_TRACING_V2") == "true"
            let project = getAPIKey(for: "LANGCHAIN_PROJECT") ?? "default"
            print("🔍 LangSmith configured: API key ✅, Tracing: \(tracingEnabled ? "✅" : "❌"), Project: \(project)")
        }
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