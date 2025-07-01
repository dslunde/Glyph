import Foundation
import PythonKit

/// Service for Python-based graph analysis and AI operations
@MainActor
class PythonGraphService: ObservableObject {
    @Published var isInitialized = false
    @Published var isOnlineMode = true
    @Published var lastError: String?
    @Published var pythonAvailable = false
    
    private var python: PythonObject?
    private var sys: PythonObject?
    
    // Static flag to ensure Python is configured only once
    private static var pythonConfigured = false
    
    // TEMPORARY: Disable Python to prevent crashes
    private static let pythonDisabled = true
    
    init() {
        if Self.pythonDisabled {
            // Skip Python initialization entirely
            print("🚫 Python initialization disabled - using mock data only")
            pythonAvailable = false
            isInitialized = true // Mark as initialized so the app works
            lastError = "Python disabled for stability"
        } else {
            // Ensure Python is configured before any initialization
            Self.ensurePythonConfigured()
            // Then attempt to initialize Python
            initializePython()
        }
    }
    
    static func ensurePythonConfigured() {
        guard !pythonConfigured else { return }
        pythonConfigured = true
        
        print("🐍 Configuring embedded Python (static)...")
        
        // Get the app bundle path
        let bundlePath = Bundle.main.bundlePath
        
        // Set up paths for embedded Python 3.13.3
        let pythonPath = "\(bundlePath)/Contents/Python"
        let pythonExecutable = "\(pythonPath)/bin/python3.13"
        let pythonLibraryPath = "\(pythonPath)/lib/libpython3.13.dylib"
        
        print("   📁 Bundle: \(bundlePath)")
        print("   🏠 Python Home: \(pythonPath)")
        print("   📚 Python Library: \(pythonLibraryPath)")
        
        // Check if embedded Python exists
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: pythonExecutable) && 
           fileManager.fileExists(atPath: pythonLibraryPath) {
            
            print("✅ Found embedded Python files")
            
            // CRITICAL: Configure PythonKit to use embedded Python BEFORE any Python calls
            PythonLibrary.useLibrary(at: pythonLibraryPath)
            
            // Set environment variables
            setenv("PYTHONHOME", pythonPath, 1)
            setenv("PYTHONEXECUTABLE", pythonExecutable, 1)
            
            let pythonLibPath = "\(pythonPath)/lib/python3.13"
            let sitePackages = "\(pythonLibPath)/site-packages"
            let combinedPath = "\(pythonLibPath):\(sitePackages)"
            setenv("PYTHONPATH", combinedPath, 1)
            
            print("🔧 Embedded Python configured successfully")
        } else {
            print("⚠️  Embedded Python not found - using system Python")
            print("   Missing: \(pythonExecutable) or \(pythonLibraryPath)")
        }
    }
    
    private func configureEmbeddedPython() {
        // This method is now deprecated - configuration happens statically
        Self.ensurePythonConfigured()
    }
    
    private func initializePython() {
        print("🐍 Attempting to initialize Python...")
        
        // Try to access Python library - this should now use embedded Python
        let pythonLib: PythonObject
        let sysModule: PythonObject
        
        do {
            // This should now use our embedded Python
            pythonLib = Python.library
            sysModule = Python.import("sys")
        } catch {
            pythonAvailable = false
            isInitialized = false
            lastError = "Python library not accessible: \(error.localizedDescription)"
            print("⚠️ Python library not accessible: \(error)")
            print("💡 App will continue with mock data and reduced functionality")
            return
        }
        
        // If we get here, Python is available
        self.python = pythonLib
        self.sys = sysModule  
        self.pythonAvailable = true
        
        // Print Python configuration info
        print("🐍 Python initialized successfully:")
        print("   Version: \(sysModule.version)")
        print("   Executable: \(sysModule.executable)")
        print("   Path: \(sysModule.path)")
        
        // Simplified module loading - just try the basics
        print("📦 Testing core Python modules...")
        
        // Test numpy
        _ = pythonLib.import("numpy")
        print("📊 NumPy import completed")
        
        // Test networkx  
        _ = pythonLib.import("networkx")
        print("🕸️ NetworkX import completed")
        
        // Test json
        _ = pythonLib.import("json")
        print("📋 JSON import completed")
        
        print("✅ Python initialization completed")
        isInitialized = true
        lastError = nil
    }
    
    // MARK: - Python Status Check
    
    func checkPythonStatus() -> String {
        if Self.pythonDisabled {
            return "Python disabled - using mock data mode"
        } else if pythonAvailable && isInitialized {
            return "Python is available and initialized"
        } else if pythonAvailable {
            return "Python is available but not fully initialized"
        } else {
            return "Python is not available - using mock data mode"
        }
    }
    
    // MARK: - Graph Analysis
    
    func prepareDataForAI(graphData: GraphData) -> [String: Any] {
        // Convert Swift GraphData to Python-compatible format
        var nodes: [[String: Any]] = []
        var edges: [[String: Any]] = []
        
        for node in graphData.nodes {
            nodes.append([
                "id": node.id.uuidString,
                "label": node.label,
                "type": node.type.rawValue,
                "properties": node.properties,
                "position": ["x": node.position.x, "y": node.position.y]
            ])
        }
        
        for edge in graphData.edges {
            edges.append([
                "source": edge.sourceId.uuidString,
                "target": edge.targetId.uuidString,
                "label": edge.label,
                "weight": edge.weight,
                "properties": edge.properties
            ])
        }
        
        return [
            "nodes": nodes,
            "edges": edges,
            "metadata": [
                "totalNodes": graphData.metadata.totalNodes,
                "totalEdges": graphData.metadata.totalEdges,
                "algorithms": graphData.metadata.algorithms
            ]
        ]
    }
    
    // MARK: - Tavily Search Integration (Simplified)
    
    func searchWithTavily(queries: [String], limit: Int = 5, apiKey: String) async throws -> [[String: Any]] {
        guard isInitialized else {
            throw APIError.networkError("Python not initialized")
        }
        
        // For now, return mock data to avoid concurrency issues
        // TODO: Implement real Tavily integration with proper async handling
        return generateMockTavilyResults(queries: queries, limit: limit)
    }
    
    private func generateMockTavilyResults(queries: [String], limit: Int) -> [[String: Any]] {
        var results: [[String: Any]] = []
        
        for (index, query) in queries.prefix(limit).enumerated() {
            let result: [String: Any] = [
                "title": "Research on \(query)",
                "url": "https://example.com/article\(index + 1)",
                "content": "Comprehensive analysis of \(query) with detailed findings and expert insights. This article covers the fundamental concepts, latest developments, and practical applications in the field.",
                "score": Double.random(in: 0.7...0.95),
                "published_date": "2024-01-\(15 + index)"
            ]
            results.append(result)
        }
        
        return results
    }
    
    // MARK: - LLM Query Generation (Simplified)
    
    func generateSearchQueries(topic: String, apiKey: String) async throws -> [String] {
        guard isInitialized else {
            throw APIError.networkError("Python not initialized")
        }
        
        // Generate intelligent queries based on topic
        return [
            "\(topic) fundamentals and basic concepts",
            "\(topic) latest research and developments 2024",
            "\(topic) expert opinions and analysis",
            "\(topic) practical applications and case studies",
            "\(topic) controversies and different perspectives"
        ]
    }
    
    // MARK: - Reliability Scoring (Simplified)
    
    func scoreReliability(results: [[String: Any]], sourcePreferences: [String], apiKey: String) async throws -> [[String: Any]] {
        guard isInitialized else {
            throw APIError.networkError("Python not initialized")
        }
        
        return results.map { result in
            var scored = result
            
            // Simple reliability scoring based on URL domain
            let url = result["url"] as? String ?? ""
            let urlLower = url.lowercased()
            
            var score = 50
            if urlLower.contains("edu") || urlLower.contains("gov") {
                score = Int.random(in: 75...90)
            } else if urlLower.contains("org") {
                score = Int.random(in: 60...80)
            } else if urlLower.contains("com") || urlLower.contains("net") {
                score = Int.random(in: 40...70)
            }
            
            scored["reliabilityScore"] = score
            return scored
        }
    }
    
    // MARK: - Real API Integration (Future Implementation)
    
    func performRealTavilySearch(queries: [String], limit: Int, apiKey: String) -> [[String: Any]] {
        // This would be the real implementation using HTTP requests
        // Avoiding PythonKit for API calls to prevent concurrency issues
        
        print("📡 Real Tavily API integration placeholder")
        print("🔍 Queries: \(queries)")
        print("🔑 API Key present: \(!apiKey.isEmpty)")
        
        // TODO: Implement with URLSession for direct HTTP calls
        return generateMockTavilyResults(queries: queries, limit: limit)
    }
    
    func performRealOpenAIQueries(topic: String, apiKey: String) -> [String] {
        // This would be the real implementation using HTTP requests
        
        print("🤖 Real OpenAI API integration placeholder")
        print("💭 Topic: \(topic)")
        print("🔑 API Key present: \(!apiKey.isEmpty)")
        
        // TODO: Implement with URLSession for direct HTTP calls
        return [
            "\(topic) fundamentals and core principles",
            "\(topic) current research and latest findings",
            "\(topic) expert analysis and professional opinions",
            "\(topic) real-world applications and case studies",
            "\(topic) debates and alternative perspectives"
        ]
    }
    
    // MARK: - Online/Offline Mode
    
    func toggleOnlineMode() {
        isOnlineMode.toggle()
    }
    
    // MARK: - Dependency Check
    
    func checkPythonDependencies() -> [String: Bool] {
        guard let python = python else {
            return ["python": false]
        }
        
        var status: [String: Bool] = [:]
        
        let modules = ["numpy", "networkx", "tavily", "openai", "json"]
        
        for module in modules {
            if let _ = try? python.import(module) {
                status[module] = true
            } else {
                status[module] = false
            }
        }
        
        return status
    }
} 