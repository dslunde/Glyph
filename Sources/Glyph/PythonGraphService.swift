import Foundation
import PythonKit

/// Service for Python-based graph analysis and AI operations
@MainActor
class PythonGraphService: ObservableObject {
    @Published var isInitialized = false
    @Published var isOnlineMode = true
    @Published var lastError: String?
    @Published var pythonAvailable = false
    @Published var availableModules: [String: Bool] = [:]
    @Published var pythonPath: String = ""
    
    private var python: PythonObject?
    private var sys: PythonObject?
    
    // Static flag to ensure Python is configured only once
    private static var pythonConfigured = false
    
    // Enable Python with robust error handling
    private static let pythonDisabled = false
    
    init() {
        if Self.pythonDisabled {
            // Skip Python initialization entirely
            print("🚫 Python initialization disabled - using mock data only")
            pythonAvailable = false
            isInitialized = true
            lastError = "Python disabled for stability"
        } else {
            // Ensure Python is configured before any initialization
            Self.ensurePythonConfigured()
            // Then attempt to initialize Python with error handling
            initializePython()
        }
    }
    
    static func ensurePythonConfigured() {
        guard !pythonConfigured else { return }
        pythonConfigured = true
        
        print("🐍 Configuring Python environment...")
        
        // Get the app bundle path
        let bundlePath = Bundle.main.bundlePath
        
        // Try embedded Python first, then system Python
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
            print("⚠️ Embedded Python not found - using system Python")
            print("   Missing: \(pythonExecutable) or \(pythonLibraryPath)")
            
            // Try to use system Python
            if let systemPython = findSystemPython() {
                print("✅ Found system Python: \(systemPython)")
            } else {
                print("❌ No Python installation found")
            }
        }
    }
    
    static func findSystemPython() -> String? {
        let possiblePaths = [
            "/usr/bin/python3",
            "/usr/local/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/bin/python",
            ProcessInfo.processInfo.environment["PYTHONPATH"] ?? ""
        ]
        
        let fileManager = FileManager.default
        for path in possiblePaths {
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }
    
    private func initializePython() {
        print("🐍 Attempting to initialize Python with error handling...")
        
        do {
            // Try to access basic Python functionality with proper error handling  
            let sysModule = try Python.attemptImport("sys")
            
            // If we get here, basic Python is available
            self.sys = sysModule
            self.pythonAvailable = true
            
            // Get Python path info safely
            self.pythonPath = String(describing: sysModule.executable)
            
            // Print Python configuration info
            print("🐍 Python initialized successfully:")
            print("   Version: \(sysModule.version)")
            print("   Executable: \(sysModule.executable)")
            print("   Path: \(sysModule.path)")
            
            // Test core modules with graceful degradation
            testPythonModules()
            
            print("✅ Python initialization completed")
            isInitialized = true
            lastError = nil
            
        } catch {
            print("⚠️ Python initialization failed: \(error)")
            pythonAvailable = false
            isInitialized = false
            lastError = "Python initialization failed: \(error.localizedDescription)"
            
            // Still mark as initialized so app can work with mock data
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.isInitialized = true
                self.lastError = "Python unavailable - using mock data mode"
            }
        }
    }
    
    private func testPythonModules() {
        print("📦 Testing Python modules...")
        
        let requiredModules = [
            "sys": "System module",
            "os": "Operating system interface", 
            "json": "JSON encoder/decoder",
            "urllib": "URL handling modules",
            "re": "Regular expressions"
        ]
        
        let optionalModules = [
            "numpy": "Numerical computing",
            "networkx": "Network analysis",
            "pandas": "Data manipulation",
            "requests": "HTTP library",
            "transformers": "Transformer models",
            "torch": "PyTorch",
            "openai": "OpenAI API client",
            "tavily": "Tavily search client"
        ]
        
        // Test required modules first
        for (module, description) in requiredModules {
            if testModuleImport(module, description: description) {
                availableModules[module] = true
            } else {
                availableModules[module] = false
                print("❌ Required module '\(module)' not available")
            }
        }
        
        // Test optional modules
        for (module, description) in optionalModules {
            if testModuleImport(module, description: description) {
                availableModules[module] = true
            } else {
                availableModules[module] = false
                print("⚠️ Optional module '\(module)' not available - some features will be limited")
            }
        }
        
        let availableCount = availableModules.values.filter { $0 }.count
        let totalCount = availableModules.count
        print("📋 Module availability: \(availableCount)/\(totalCount) modules available")
    }
    
    private func testModuleImport(_ moduleName: String, description: String) -> Bool {
        do {
            _ = try Python.attemptImport(moduleName)
            print("✅ \(moduleName): \(description)")
            return true
        } catch {
            print("❌ \(moduleName): Not available (\(error.localizedDescription))")
            return false
        }
    }
    
    // MARK: - Python Status Check
    
    func checkPythonStatus() -> String {
        if Self.pythonDisabled {
            return "Python disabled - using mock data mode"
        } else if pythonAvailable && isInitialized {
            let availableCount = availableModules.values.filter { $0 }.count
            let totalCount = availableModules.count
            return "Python available (\(availableCount)/\(totalCount) modules) - Path: \(pythonPath)"
        } else if pythonAvailable {
            return "Python available but not fully initialized"
        } else {
            return "Python not available - using mock data mode"
        }
    }
    
    func getModuleStatus() -> [String: Bool] {
        return availableModules
    }
    
    func hasModule(_ moduleName: String) -> Bool {
        return availableModules[moduleName] == true
    }
    
    // MARK: - Safe Module Usage
    
    private func safeImport(_ moduleName: String) -> PythonObject? {
        do {
            return try Python.attemptImport(moduleName)
        } catch {
            print("⚠️ Failed to import \(moduleName): \(error)")
            return nil
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
    
    // MARK: - Network Analysis (with NetworkX if available)
    
    func analyzeGraphStructure(graphData: GraphData) -> [String: Any] {
        guard hasModule("networkx"), let nx = safeImport("networkx") else {
            return mockGraphAnalysis(graphData: graphData)
        }
        
        // Convert to NetworkX format and analyze
        let G = nx.DiGraph()
        
        // Add nodes and edges (simplified for safety)
        for node in graphData.nodes {
            G.add_node(node.id.uuidString)  
        }
        
        for edge in graphData.edges {
            G.add_edge(edge.sourceId.uuidString, edge.targetId.uuidString)
        }
        
        // Calculate basic metrics
        let nodeCount = Int(G.number_of_nodes()) ?? 0
        let edgeCount = Int(G.number_of_edges()) ?? 0
        let density = Double(nx.density(G)) ?? 0.0
        
        return [
            "nodes": nodeCount,
            "edges": edgeCount, 
            "density": density,
            "analysis_method": "networkx",
            "available_algorithms": ["centrality", "community_detection", "shortest_paths"]
        ]
    }
    
    private func mockGraphAnalysis(graphData: GraphData) -> [String: Any] {
        return [
            "nodes": graphData.nodes.count,
            "edges": graphData.edges.count,
            "density": Double(graphData.edges.count) / Double(max(1, graphData.nodes.count * (graphData.nodes.count - 1))),
            "analysis_method": "mock",
            "available_algorithms": ["basic_stats"]
        ]
    }
    
    // MARK: - API Integration with Fallbacks
    
    func searchWithTavily(queries: [String], limit: Int = 5, apiKey: String) async throws -> [[String: Any]] {
        guard isInitialized else {
            throw APIError.networkError("Python not initialized")
        }
        
        if hasModule("tavily") && hasModule("requests") {
            // TODO: Implement real Tavily integration
            print("📡 Real Tavily integration available but not yet implemented")
        }
        
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
    
    func generateSearchQueries(topic: String, apiKey: String) async throws -> [String] {
        guard isInitialized else {
            throw APIError.networkError("Python not initialized")
        }
        
        if hasModule("openai") {
            // TODO: Implement real OpenAI integration
            print("🤖 Real OpenAI integration available but not yet implemented")
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
    
    // MARK: - Package Installation Support
    
    func installRequiredPackages() async throws {
        guard pythonAvailable else {
            throw APIError.networkError("Python not available")
        }
        
        print("📦 Checking for package installation capability...")
        
        // Check if we can install packages
        if hasModule("pip") {
            print("✅ pip is available - package installation possible")
            // TODO: Implement package installation from requirements.txt
        } else {
            print("⚠️ pip not available - cannot install packages automatically")
            print("💡 Packages need to be pre-installed in the Python environment")
        }
    }
    
    // MARK: - Online/Offline Mode
    
    func toggleOnlineMode() {
        isOnlineMode.toggle()
    }
    
    // MARK: - Dependency Check
    
    func checkPythonDependencies() -> [String: Bool] {
        return availableModules
    }
} 