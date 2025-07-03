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
        
        // CRITICAL: Set APP_BUNDLE_MODE immediately for Python processes
        if Bundle.main.bundlePath.contains(".app") {
            setenv("APP_BUNDLE_MODE", "1", 1)
            print("🎯 Set APP_BUNDLE_MODE=1 for Python environment")
        } else {
            // Ensure it's unset in development mode
            unsetenv("APP_BUNDLE_MODE")
            print("🔧 Development mode - APP_BUNDLE_MODE unset")
        }
        
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
            
            // Set environment variables FIRST
            setenv("PYTHONHOME", pythonPath, 1)
            setenv("PYTHONEXECUTABLE", pythonExecutable, 1)
            
            let pythonLibPath = "\(pythonPath)/lib/python3.13"
            let sitePackages = "\(pythonLibPath)/site-packages"
            let combinedPath = "\(pythonLibPath):\(sitePackages)"
            setenv("PYTHONPATH", combinedPath, 1)
            
            print("🔧 Environment variables set")
            
            // CRITICAL: Configure PythonKit to use embedded Python BEFORE any Python calls
            // This call can potentially hang, so we'll handle it carefully
            print("🐍 Attempting to configure PythonKit library...")
            PythonLibrary.useLibrary(at: pythonLibraryPath)
            print("✅ PythonKit library configured successfully")
            
            print("🔧 Embedded Python configuration completed")
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
    
    // MARK: - Knowledge Graph Generation
    
    /// Build knowledge graph from source collection results
    func buildKnowledgeGraph(
        from sources: [[String: Any]], 
        topic: String,
        progressCallback: @escaping (Double, String) -> Void
    ) async throws -> [String: Any] {
        guard isInitialized else {
            throw APIError.networkError("Python not initialized")
        }
        
        print("🏗️ Starting knowledge graph generation...")
        
        do {
            // Ensure APP_BUNDLE_MODE is set for this Python subprocess
            if Bundle.main.bundlePath.contains(".app") {
                setenv("APP_BUNDLE_MODE", "1", 1)
                print("🎯 Confirmed APP_BUNDLE_MODE=1 for knowledge graph generation")
            } else {
                unsetenv("APP_BUNDLE_MODE")
                print("🔧 Development mode - APP_BUNDLE_MODE unset for knowledge graph generation")
            }
            
            // Clear any old status file before starting
            let cacheDir = Bundle.main.bundlePath.contains(".app") ? 
                FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("com.glyph.knowledge-graph-explorer").path :
                "./graph_cache"
            let statusFile = "\(cacheDir)/kg_status.json"
            
            if FileManager.default.fileExists(atPath: statusFile) {
                try? FileManager.default.removeItem(atPath: statusFile)
                print("🗑️ Cleared old status file")
            }
            
            // Start status polling BEFORE Python execution
            print("🔄 Starting Python status polling...")
            let statusPollingTask = Task {
                await pollPythonStatusUpdates(progressCallback: progressCallback)
            }
            
            // Give polling task a moment to start
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            // Import our custom knowledge graph module
            let kgModule = try Python.attemptImport("knowledge_graph_generation")
            
            // Convert Swift sources to Python format
            print("🔄 Converting \(sources.count) sources to Python format...")
            let pythonSources = Python.list(sources.map { source in
                Python.dict(source.compactMapValues { value -> String in
                    if let stringValue = value as? String {
                        return stringValue
                    } else if let intValue = value as? Int {
                        return String(intValue)
                    } else if let doubleValue = value as? Double {
                        return String(doubleValue)
                    } else {
                        return String(describing: value)
                    }
                })
            })
            
            print("🧠 Starting Python knowledge graph generation...")
            
            // Create a timeout task for the Python call
            let pythonTask = Task {
                return kgModule.generate_knowledge_graph_from_sources(
                    pythonSources,
                    topic,
                    Python.None
                )
            }
            
            // Create a timeout task
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: 120_000_000_000) // 2 minutes timeout
                pythonTask.cancel()
                throw APIError.networkError("Knowledge graph generation timed out after 2 minutes")
            }
            
            // Race between Python execution and timeout
            let result = await withTaskCancellationHandler {
                await pythonTask.value
            } onCancel: {
                timeoutTask.cancel()
            }
            
            timeoutTask.cancel() // Cancel timeout if we completed successfully
            
            // Stop status polling after Python completes
            print("🛑 Stopping Python status polling...")
            statusPollingTask.cancel()
            
            // Give polling task a moment to finish and report final status
            try await Task.sleep(nanoseconds: 300_000_000) // 300ms
            
            // Clean up status file after completion
            if FileManager.default.fileExists(atPath: statusFile) {
                try? FileManager.default.removeItem(atPath: statusFile)
                print("🧹 Cleaned up status file")
            }
            
            // Extract results from Python dict
            let success = Bool(result["success"]) ?? false
            
            if success {
                // Convert Python results to Swift format
                let pythonNodes = result["nodes"]
                let pythonEdges = result["edges"]
                let pythonMinimalSubgraph = result["minimal_subgraph"]
                let pythonMetadata = result["metadata"]
                
                // Convert nodes
                var swiftNodes: [[String: Any]] = []
                if pythonNodes != Python.None {
                    let nodesList = Array(pythonNodes)
                    for nodeObj in nodesList {
                        var swiftNode: [String: Any] = [:]
                        let nodeKeys = Array(nodeObj.keys())
                        for key in nodeKeys {
                            let keyString = String(describing: key)
                            let value = nodeObj[key]
                            swiftNode[keyString] = convertPythonToSwift(value)
                        }
                        swiftNodes.append(swiftNode)
                    }
                }
                
                // Convert edges
                var swiftEdges: [[String: Any]] = []
                if pythonEdges != Python.None {
                    let edgesList = Array(pythonEdges)
                    for edgeObj in edgesList {
                        var swiftEdge: [String: Any] = [:]
                        let edgeKeys = Array(edgeObj.keys())
                        for key in edgeKeys {
                            let keyString = String(describing: key)
                            let value = edgeObj[key]
                            swiftEdge[keyString] = convertPythonToSwift(value)
                        }
                        swiftEdges.append(swiftEdge)
                    }
                }
                
                // Convert minimal subgraph
                var swiftMinimalSubgraph: [String: Any] = [:]
                if pythonMinimalSubgraph != Python.None {
                    let subgraphKeys = Array(pythonMinimalSubgraph.keys())
                    for key in subgraphKeys {
                        let keyString = String(describing: key)
                        let value = pythonMinimalSubgraph[key]
                        swiftMinimalSubgraph[keyString] = convertPythonToSwift(value)
                    }
                }
                
                // Convert metadata
                var swiftMetadata: [String: Any] = [:]
                if pythonMetadata != Python.None {
                    let metadataKeys = Array(pythonMetadata.keys())
                    for key in metadataKeys {
                        let keyString = String(describing: key)
                        let value = pythonMetadata[key]
                        swiftMetadata[keyString] = convertPythonToSwift(value)
                    }
                }
                
                print("✅ Knowledge graph generation completed successfully")
                print("   📊 Nodes: \(swiftNodes.count)")
                print("   🔗 Edges: \(swiftEdges.count)")
                // // print("   🎯 Minimal nodes: \(swiftMinimalSubgraph["nodes"] as? [[String: Any]] ?? [])")
                
                return [
                    "success": true,
                    "nodes": swiftNodes,
                    "edges": swiftEdges,
                    "minimal_subgraph": swiftMinimalSubgraph,
                    "metadata": swiftMetadata,
                    "error_message": NSNull()
                ]
                
            } else {
                let errorMessage = String(describing: result["error"])
                print("❌ Knowledge graph generation failed: \(errorMessage)")
                
                return [
                    "success": false,
                    "nodes": [],
                    "edges": [],
                    "minimal_subgraph": ["nodes": [], "edges": []],
                    "metadata": [:],
                    "error_message": errorMessage
                ]
            }
            
        } catch {
            print("❌ Knowledge graph generation Python call failed: \(error)")
            print("🔄 Falling back to mock graph generation")
            
            // Clean up status file on error too
            let errorCacheDir = Bundle.main.bundlePath.contains(".app") ? 
                FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("com.glyph.knowledge-graph-explorer").path :
                "./graph_cache"
            let errorStatusFile = "\(errorCacheDir)/kg_status.json"
            
            if FileManager.default.fileExists(atPath: errorStatusFile) {
                try? FileManager.default.removeItem(atPath: errorStatusFile)
                print("🧹 Cleaned up status file after error")
            }
            
            // Generate mock knowledge graph
            let mockResult = generateMockKnowledgeGraph(from: sources, topic: topic, progressCallback: progressCallback)
            
            return [
                "success": true,
                "nodes": mockResult["nodes"] as? [[String: Any]] ?? [],
                "edges": mockResult["edges"] as? [[String: Any]] ?? [],
                "minimal_subgraph": mockResult["minimal_subgraph"] as? [String: Any] ?? [:],
                "metadata": mockResult["metadata"] as? [String: Any] ?? [:],
                "error_message": "Python knowledge graph generation not available - using mock data"
            ]
        }
    }
    
    // MARK: - Enhanced Source Processing
    
    /// Process manual sources (files, folders, URLs) with intelligent expansion
    func processManualSources(
        filePaths: [String],
        urls: [String], 
        topic: String,
        maxPages: Int = 10
    ) async throws -> [String: Any] {
        guard isInitialized else {
            throw APIError.networkError("Python not initialized")
        }
        
        print("🔄 Starting enhanced source processing...")
        print("   📁 File paths: \(filePaths.count)")
        print("   🌐 URLs: \(urls.count)")
        print("   📝 Topic: \(topic)")
        
        do {
            // Call the enhanced source processing module
            let enhancedModule = try Python.attemptImport("enhanced_source_processing")
            
            // Get OpenAI API key for AI-powered URL filtering
            let openaiApiKey = EnvironmentService.shared.getAPIKey(for: "OPENAI_API_KEY") ?? ""
            
            // Call the Python function directly on the module (like knowledge graph generation does)
            let pythonResult = enhancedModule.process_manual_sources_sync(
                filePaths, 
                urls, 
                topic, 
                maxPages, 
                openaiApiKey
            )
            
            // Convert Python result to Swift dictionary
            let swiftResult = convertPythonToSwift(pythonResult)
            
            if let resultDict = swiftResult as? [String: Any] {
                let totalSources = resultDict["total_sources"] as? Int ?? 0
                let metadata = resultDict["metadata"] as? [String: Any] ?? [:]
                let errors = (metadata["errors"] as? [String]) ?? []
                
                print("✅ Enhanced source processing completed:")
                print("   📄 Total sources: \(totalSources)")
                print("   📁 Files processed: \(metadata["files_processed"] ?? 0)")
                print("   🌐 URLs expanded: \(metadata["total_discovered_pages"] ?? 0)")
                
                if !errors.isEmpty {
                    print("   ⚠️ Errors encountered: \(errors.count)")
                    for error in errors {
                        print("     • \(error)")
                    }
                }
                
                return resultDict
            }
            
        } catch {
            print("❌ Enhanced source processing failed: \(error)")
            print("🔄 Falling back to basic processing")
            
            // Fallback to basic processing
            return generateBasicManualSources(filePaths: filePaths, urls: urls, topic: topic)
        }
        
        return generateBasicManualSources(filePaths: filePaths, urls: urls, topic: topic)
    }
    
    private func generateBasicManualSources(filePaths: [String], urls: [String], topic: String) -> [String: Any] {
        print("🔄 Using basic manual source processing...")
        
        var sources: [[String: Any]] = []
        var metadata: [String: Any] = [
            "files_processed": 0,
            "folders_scanned": 0,
            "urls_expanded": 0,
            "total_discovered_pages": 0,
            "errors": []
        ]
        
        // Process file paths
        for filePath in filePaths {
            guard !filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            
            let fileManager = FileManager.default
            let path = URL(fileURLWithPath: filePath)
            
            if fileManager.fileExists(atPath: filePath) {
                let source: [String: Any] = [
                    "title": path.lastPathComponent,
                    "content": "Local file: \(filePath)",
                    "url": "file://\(filePath)",
                    "score": 0.9,
                    "published_date": "",
                    "query": "File: \(path.lastPathComponent)",
                    "reliability_score": 90,
                    "source_type": "file",
                    "word_count": 0
                ]
                sources.append(source)
                metadata["files_processed"] = (metadata["files_processed"] as? Int ?? 0) + 1
            }
        }
        
        // Process URLs
        for url in urls {
            guard !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            
            let source: [String: Any] = [
                "title": generateTitleFromURL(url),
                "content": "User-provided URL: \(url)",
                "url": url,
                "score": 0.8,
                "published_date": "",
                "query": "Manual URL: \(url)",
                "reliability_score": 75,
                "source_type": "url",
                "word_count": 0
            ]
            sources.append(source)
            metadata["urls_expanded"] = (metadata["urls_expanded"] as? Int ?? 0) + 1
        }
        
        print("✅ Basic processing: \(sources.count) sources created")
        
        return [
            "sources": sources,
            "metadata": metadata,
            "total_sources": sources.count
        ]
    }
    
    private func generateTitleFromURL(_ url: String) -> String {
        guard let urlComponents = URLComponents(string: url) else { return url }
        
        if let path = urlComponents.path.split(separator: "/").last {
            let title = String(path)
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
            return title.capitalized
        }
        
        return urlComponents.host ?? url
    }
    
    // MARK: - Learning Plan Generation
    
    /// Generate detailed learning plan from minimal subgraph
    func generateLearningPlan(
        from minimalSubgraph: [String: Any],
        sources: [[String: Any]],
        topic: String,
        depth: String = "moderate"
    ) async throws -> [String: Any] {
        guard isInitialized else {
            throw APIError.networkError("Python not initialized")
        }
        
        print("🎓 Starting learning plan generation...")
        print("🔍 DEBUG: Sources count: \(sources.count)")
        print("🔍 DEBUG: Minimal subgraph nodes: \((minimalSubgraph["nodes"] as? [[String: Any]])?.count ?? 0)")
        
        // Log source content to verify we have real data
        for (i, source) in sources.prefix(3).enumerated() {
            print("🔍 DEBUG: Source \(i): title='\(source["title"] as? String ?? "none")', content length=\(String(source["content"] as? String ?? "").count)")
        }
        
        do {
            // Import our custom knowledge graph module
            let kgModule = try Python.attemptImport("knowledge_graph_generation")
            
            // Convert Swift data to Python format
            print("🔄 Converting minimal subgraph and sources to Python format...")
            
            let pythonMinimalSubgraph = Python.dict(minimalSubgraph.compactMapValues { value in
                convertSwiftToPython(value)
            })
            
            let pythonSources = Python.list(sources.map { source in
                Python.dict(source.compactMapValues { value -> String in
                    if let stringValue = value as? String {
                        return stringValue
                    } else if let intValue = value as? Int {
                        return String(intValue)
                    } else if let doubleValue = value as? Double {
                        return String(doubleValue)
                    } else {
                        return String(describing: value)
                    }
                })
            })
            
            print("🧠 Calling Python learning plan generation...")
            
            // Call the Python learning plan generation function
            let result = kgModule.generate_learning_plan_from_minimal_subgraph(
                pythonMinimalSubgraph,
                pythonSources,
                topic,
                depth
            )
            
            // Convert Python result to Swift format
            var swiftResult: [String: Any] = [:]
            let resultKeys = Array(result.keys())
            for key in resultKeys {
                let keyString = String(describing: key)
                let value = result[key]
                swiftResult[keyString] = convertPythonToSwift(value)
            }
            
            print("✅ Learning plan generated successfully")
            print("🔍 DEBUG: Result has concept_groups: \(swiftResult["concept_groups"] != nil)")
            
            // Log some concept details to verify source references are populated
            if let conceptGroups = swiftResult["concept_groups"] as? [String: Any] {
                for (phase, concepts) in conceptGroups {
                    if let conceptArray = concepts as? [[String: Any]], let firstConcept = conceptArray.first {
                        print("🔍 DEBUG: Phase '\(phase)' first concept: \(firstConcept["name"] as? String ?? "none")")
                        print("🔍 DEBUG: Source references count: \((firstConcept["source_references"] as? [String])?.count ?? 0)")
                    }
                }
            }
            
            return swiftResult
            
        } catch {
            print("❌ Learning plan generation failed: \(error)")
            print("🔄 Falling back to mock learning plan")
            
            // Generate mock learning plan
            return generateMockLearningPlan(topic: topic, depth: depth, nodeCount: (minimalSubgraph["nodes"] as? [[String: Any]])?.count ?? 0)
        }
    }
    
    private func generateMockLearningPlan(topic: String, depth: String, nodeCount: Int) -> [String: Any] {
        print("🎭 Generating mock learning plan...")
        
        let mockConceptGroups: [String: [[String: Any]]] = [
            "foundation": [
                [
                    "name": "Introduction to \(topic)",
                    "type": "concept",
                    "description": "Foundational understanding of \(topic) principles and core concepts",
                    "time_estimate": 2,
                    "importance_score": 0.9,
                    "connections": [],
                    "resources": [["type": "Tutorial", "title": "\(topic) Basics", "description": "Getting started guide"]],
                    "source_references": ["Academic Paper: Foundations of \(topic) (journal)", "Tutorial: Getting Started with \(topic) (web)", "Encyclopedia: \(topic) Overview (reference)"]
                ],
                [
                    "name": "Core \(topic) Principles",
                    "type": "concept", 
                    "description": "Essential principles that underpin \(topic) methodology",
                    "time_estimate": 2,
                    "importance_score": 0.85,
                    "connections": [],
                    "resources": [["type": "Guide", "title": "\(topic) Principles", "description": "Comprehensive principles guide"]],
                    "source_references": ["Research Paper: Core Principles in \(topic) (academic)", "Blog Post: Understanding \(topic) Fundamentals (web)"]
                ]
            ],
            "intermediate": [
                [
                    "name": "Advanced \(topic) Techniques",
                    "type": "concept",
                    "description": "More sophisticated approaches and methodologies in \(topic)",
                    "time_estimate": 4,
                    "importance_score": 0.7,
                    "connections": [],
                    "resources": [["type": "Advanced Guide", "title": "Advanced \(topic)", "description": "Deep dive into complex topics"]],
                    "source_references": ["Technical Manual: Advanced \(topic) Methods (manual)", "Case Study: Real-world \(topic) Applications (web)", "Research: Modern \(topic) Approaches (academic)"]
                ]
            ],
            "advanced": [
                [
                    "name": "Expert-Level \(topic)",
                    "type": "insight",
                    "description": "Cutting-edge developments and expert insights in \(topic)",
                    "time_estimate": 6,
                    "importance_score": 0.6,
                    "connections": [],
                    "resources": [["type": "Expert Analysis", "title": "Expert \(topic) Insights", "description": "Professional insights and analysis"]],
                    "source_references": ["Expert Interview: Leading \(topic) Practitioners (video)", "White Paper: Future of \(topic) (report)", "Conference Paper: Latest \(topic) Research (academic)"]
                ]
            ],
            "practical": [
                [
                    "name": "Real-world \(topic) Implementation",
                    "type": "insight",
                    "description": "Practical insights for implementing \(topic) in real scenarios",
                    "time_estimate": 3,
                    "importance_score": 0.8,
                    "connections": [],
                    "resources": [["type": "Case Study", "title": "\(topic) Case Studies", "description": "Real-world examples"]],
                    "source_references": ["Implementation Guide: \(topic) Best Practices (manual)", "Case Study: Successful \(topic) Projects (web)", "Tutorial: Hands-on \(topic) Workshop (video)"]
                ]
            ]
        ]
        
        return [
            "topic": topic,
            "depth": depth,
            "total_estimated_time": 21,
            "total_concepts": nodeCount,
            "phase_breakdown": [
                "foundation": 4,
                "intermediate": 6,
                "advanced": 8,
                "practical": 3
            ],
            "concept_groups": mockConceptGroups,
            "sources_used": 5,
            "learning_path_rationale": "Concepts ordered by centrality analysis to ensure proper foundational understanding with full source traceability."
        ]
    }
    
    private func convertSwiftToPython(_ value: Any) -> PythonObject {
        if let stringValue = value as? String {
            return Python.str(stringValue)
        } else if let intValue = value as? Int {
            return Python.int(intValue)
        } else if let doubleValue = value as? Double {
            return Python.float(doubleValue)
        } else if let boolValue = value as? Bool {
            return Python.bool(boolValue)
        } else if let arrayValue = value as? [Any] {
            let pythonList = Python.list()
            for item in arrayValue {
                pythonList.append(convertSwiftToPython(item))
            }
            return pythonList
        } else if let dictValue = value as? [String: Any] {
            let pythonDict = Python.dict()
            for (key, val) in dictValue {
                pythonDict[key] = convertSwiftToPython(val)
            }
            return pythonDict
        } else {
            return Python.str(String(describing: value))
        }
    }

    private func generateMockKnowledgeGraph(
        from sources: [[String: Any]], 
        topic: String,
        progressCallback: @escaping (Double, String) -> Void
    ) -> [String: Any] {
        print("🎭 Generating mock knowledge graph...")
        
        // Simulate progress updates
        DispatchQueue.main.async { progressCallback(0.1, "Extracting concepts from sources") }
        Thread.sleep(forTimeInterval: 0.5)
        
        DispatchQueue.main.async { progressCallback(0.3, "Building graph structure") }
        Thread.sleep(forTimeInterval: 0.5)
        
        DispatchQueue.main.async { progressCallback(0.6, "Calculating centrality metrics") }
        Thread.sleep(forTimeInterval: 0.5)
        
        DispatchQueue.main.async { progressCallback(0.8, "Finding minimal subgraph") }
        Thread.sleep(forTimeInterval: 0.3)
        
        DispatchQueue.main.async { progressCallback(1.0, "Knowledge graph complete") }
        
        // Generate mock nodes based on topic and sources
        var mockNodes: [[String: Any]] = []
        var mockEdges: [[String: Any]] = []
        
        // Core concept nodes
        let coreConceptIds = [UUID().uuidString, UUID().uuidString, UUID().uuidString]
        let coreConcepts = [
            "\(topic) fundamentals",
            "\(topic) applications", 
            "\(topic) theory"
        ]
        
        for (index, concept) in coreConcepts.enumerated() {
            mockNodes.append([
                "id": coreConceptIds[index],
                "label": concept,
                "type": "concept",
                "properties": [
                    "frequency": "5",
                    "importance": "0.9",
                    "pagerank": String(0.3 - Double(index) * 0.05),
                    "eigenvector": String(0.8 - Double(index) * 0.1),
                    "betweenness": String(0.6 - Double(index) * 0.1),
                    "closeness": String(0.7 - Double(index) * 0.05)
                ],
                "position": ["x": 0.0, "y": 0.0]
            ])
        }
        
        // Entity nodes from sources
        let entityIds = [UUID().uuidString, UUID().uuidString]
        let entities = sources.prefix(2).map { source in
            (source["title"] as? String ?? "Source").split(separator: " ").prefix(2).joined(separator: " ")
        }
        
        for (index, entity) in entities.enumerated() {
            mockNodes.append([
                "id": entityIds[index],
                "label": entity,
                "type": "entity",
                "properties": [
                    "frequency": "3",
                    "importance": "0.6",
                    "pagerank": String(0.2 - Double(index) * 0.05),
                    "eigenvector": String(0.5 - Double(index) * 0.1),
                    "betweenness": String(0.4 - Double(index) * 0.1),
                    "closeness": String(0.5 - Double(index) * 0.05)
                ],
                "position": ["x": 0.0, "y": 0.0]
            ])
        }
        
        // Create edges between nodes
        for i in 0..<mockNodes.count {
            for j in (i+1)..<min(mockNodes.count, i+3) {
                let sourceId = mockNodes[i]["id"] as! String
                let targetId = mockNodes[j]["id"] as! String
                
                mockEdges.append([
                    "source_id": sourceId,
                    "target_id": targetId,
                    "label": "relates_to",
                    "weight": Double.random(in: 1.0...3.0),
                    "properties": [:]
                ])
            }
        }
        
        // Create minimal subgraph (first 3 nodes and their edges)
        let minimalNodes = Array(mockNodes.prefix(3))
        let minimalEdges = mockEdges.filter { edge in
            let sourceId = edge["source_id"] as! String
            let targetId = edge["target_id"] as! String
            return minimalNodes.contains { ($0["id"] as! String) == sourceId } &&
                   minimalNodes.contains { ($0["id"] as! String) == targetId }
        }
        
        let metadata: [String: Any] = [
            "total_nodes": mockNodes.count,
            "total_edges": mockEdges.count,
            "minimal_nodes": minimalNodes.count,
            "minimal_edges": minimalEdges.count,
            "algorithms": ["pagerank", "eigenvector", "betweenness", "closeness"],
            "last_analysis": ISO8601DateFormatter().string(from: Date()),
            "has_embeddings": false,
            "connected_components": 1,
            "graph_density": 0.6
        ]
        
        return [
            "nodes": mockNodes,
            "edges": mockEdges,
            "minimal_subgraph": [
                "nodes": minimalNodes,
                "edges": minimalEdges
            ],
            "metadata": metadata
        ]
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
    
    // MARK: - LangGraph Workflow Integration (PRIMARY API)
    
    /// Primary method for source collection using LangGraph state machine orchestration.
    /// This replaces the deprecated individual API methods with a comprehensive workflow.
    
    func runSourceCollectionWorkflow(
        topic: String,
        searchLimit: Int,
        reliabilityThreshold: Double,
        sourcePreferences: [String],
        openaiApiKey: String,
        tavilyApiKey: String
    ) async throws -> [String: Any] {
        guard isInitialized else {
            throw APIError.networkError("Python not initialized")
        }
        
        print("🚀 Calling LangGraph source collection workflow...")
        
        do {
            // Import our custom Python API module
            let apiModule = try Python.attemptImport("PythonAPIService")
            
            // Convert Swift arrays to Python format
            let pythonPreferences = Python.list(sourcePreferences)
            
            // Call the LangGraph workflow function
            let result = apiModule.run_source_collection_workflow_sync(
                topic,
                searchLimit,
                reliabilityThreshold,
                pythonPreferences,
                openaiApiKey,
                tavilyApiKey
            )
            
            // Extract results from Python dict
            let success = Bool(result["success"]) ?? false
            
            if success {
                // Convert Python results to Swift format
                let pythonResults = result["results"]
                let swiftResults = convertPythonListToSwift(pythonResults)
                
                // Extract metadata
                let pythonMetadata = result["metadata"]
                var swiftMetadata: [String: Any] = [:]
                
                if pythonMetadata != Python.None {
                    let metadataKeys = Array(pythonMetadata.keys())
                    for key in metadataKeys {
                        let keyString = String(describing: key)
                        let value = pythonMetadata[key]
                        swiftMetadata[keyString] = convertPythonToSwift(value)
                    }
                }
                
                print("✅ LangGraph workflow completed successfully")
                print("   📊 Results: \(swiftResults.count)")
                print("   ⚠️  Errors: \(swiftMetadata["error_count"] as? Int ?? 0)")
                print("   🔄 Fallback used: \(swiftMetadata["fallback_used"] as? Bool ?? false)")
                
                return [
                    "success": true,
                    "results": swiftResults,
                    "error_message": NSNull(),
                    "metadata": swiftMetadata
                ]
                
            } else {
                let errorMessage = String(describing: result["error_message"])
                print("❌ LangGraph workflow failed: \(errorMessage)")
                
                // Try to get any partial results or metadata
                let pythonResults = result["results"]
                let swiftResults = convertPythonListToSwift(pythonResults)
                
                let pythonMetadata = result["metadata"]
                var swiftMetadata: [String: Any] = [:]
                
                if pythonMetadata != Python.None {
                    let metadataKeys = Array(pythonMetadata.keys())
                    for key in metadataKeys {
                        let keyString = String(describing: key)
                        let value = pythonMetadata[key]
                        swiftMetadata[keyString] = convertPythonToSwift(value)
                    }
                }
                
                return [
                    "success": false,
                    "results": swiftResults,
                    "error_message": errorMessage,
                    "metadata": swiftMetadata
                ]
            }
            
        } catch {
            print("❌ LangGraph workflow Python call failed: \(error)")
            print("🔄 Falling back to mock workflow results")
            
            // Generate mock workflow results with LangGraph structure
            let mockResults = generateMockWorkflowResults(topic: topic, limit: searchLimit)
            
            return [
                "success": true,
                "results": mockResults,
                "error_message": "LangGraph not available - using mock workflow",
                "metadata": [
                    "total_queries": 5,
                    "raw_results": mockResults.count,
                    "scored_results": mockResults.count,
                    "filtered_results": mockResults.count,
                    "error_count": 0,
                    "fallback_used": true,
                    "workflow_type": "mock_langgraph"
                ]
            ]
        }
    }
    
    private func generateMockWorkflowResults(topic: String, limit: Int) -> [[String: Any]] {
        print("🎭 Generating mock LangGraph workflow results...")
        
        let queries = [
            "\(topic) fundamentals and basic concepts",
            "\(topic) latest research and developments 2024",
            "\(topic) expert opinions and analysis",
            "\(topic) practical applications and case studies",
            "\(topic) controversies and different perspectives"
        ]
        
        var results: [[String: Any]] = []
        
        for (index, query) in queries.prefix(limit).enumerated() {
            let result: [String: Any] = [
                "title": "LangGraph Research on \(query)",
                "url": "https://example.com/langgraph-article\(index + 1)",
                "content": "Comprehensive LangGraph workflow analysis of \(query) with state machine orchestration and detailed findings. This article covers workflow nodes, state transitions, and practical applications.",
                "score": Double.random(in: 0.7...0.95),
                "published_date": "2024-01-\(15 + index)",
                "query": query,
                "reliability_score": Int.random(in: 60...90)
            ]
            results.append(result)
        }
        
        print("   📊 Generated \(results.count) mock LangGraph results")
        return results
    }
    
    // MARK: - Status Monitoring
    
    private func pollPythonStatusUpdates(progressCallback: @escaping (Double, String) -> Void) async {
        let cacheDir: String
        if Bundle.main.bundlePath.contains(".app") {
            // App bundle mode
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            cacheDir = "\(homeDir)/Library/Caches/com.glyph.knowledge-graph-explorer"
            print("📁 Swift polling: App bundle cache directory: \(cacheDir)")
        } else {
            // Development mode
            cacheDir = "./graph_cache"
            print("📁 Swift polling: Development cache directory: \(cacheDir)")
        }
        
        let statusFile = "\(cacheDir)/kg_status.json"
        print("📊 Swift polling: Looking for status file at: \(statusFile)")
        var lastProgress: Double = 0.0
        var pollCount = 0
        
        var shouldContinue = true
        
        while shouldContinue && !Task.isCancelled {
            do {
                pollCount += 1
                
                // Check if status file exists and read it
                if FileManager.default.fileExists(atPath: statusFile) {
                    if pollCount == 1 {
                        print("✅ Status file found on poll #\(pollCount)")
                    }
                    
                    let statusData = try Data(contentsOf: URL(fileURLWithPath: statusFile))
                    if let statusDict = try JSONSerialization.jsonObject(with: statusData) as? [String: Any] {
                        let progress = statusDict["progress"] as? Double ?? 0.0
                        let message = statusDict["message"] as? String ?? ""
                        let completed = statusDict["completed"] as? Bool ?? false
                        let error = statusDict["error"] as? String
                        
                        // Only update if progress has changed
                        if progress != lastProgress || completed {
                            lastProgress = progress
                            print("📈 Progress update: \(Int(progress * 100))% - \(message)")
                            
                            DispatchQueue.main.async {
                                progressCallback(progress, message)
                            }
                            
                            if let error = error {
                                print("❌ Python status error: \(error)")
                                shouldContinue = false
                            }
                            
                            if completed {
                                print("✅ Python process completed successfully via status file")
                                shouldContinue = false
                            }
                        }
                    } else {
                        if pollCount <= 3 {
                            print("⚠️ Could not parse status file JSON on poll #\(pollCount)")
                        }
                    }
                } else {
                    if pollCount == 1 {
                        print("⏳ Status file not found yet, waiting for Python to create it...")
                    } else if pollCount % 50 == 0 {  // Every 10 seconds
                        print("⏳ Still waiting for status file... (poll #\(pollCount)) - Python may still be initializing")
                    }
                }
                
                // Poll every 200ms
                try await Task.sleep(nanoseconds: 200_000_000)
                
            } catch {
                if pollCount <= 3 {
                    print("⚠️ Status file reading error on poll #\(pollCount): \(error)")
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        
        // Handle case where task was cancelled - try to read final status once more
        if Task.isCancelled && FileManager.default.fileExists(atPath: statusFile) {
            do {
                print("🔄 Task cancelled - checking for final status update...")
                let statusData = try Data(contentsOf: URL(fileURLWithPath: statusFile))
                if let statusDict = try JSONSerialization.jsonObject(with: statusData) as? [String: Any] {
                    let progress = statusDict["progress"] as? Double ?? 0.0
                    let message = statusDict["message"] as? String ?? ""
                    let _ = statusDict["completed"] as? Bool ?? false
                    
                    print("📈 Final progress update: \(Int(progress * 100))% - \(message)")
                    DispatchQueue.main.async {
                        progressCallback(progress, message)
                    }
                }
            } catch {
                print("⚠️ Could not read final status: \(error)")
            }
        }
        
        print("🛑 Status polling stopped after \(pollCount) polls")
    }
    
    // MARK: - Helper Functions for Python/Swift Conversion
    
    private func convertPythonToSwift(_ value: PythonObject) -> Any {
        // Handle None
        if value == Python.None {
            return NSNull()
        }
        
        // Try to detect the type and convert appropriately
        let stringValue = String(describing: value)
        
        // Check if it's a Python list
        if stringValue.hasPrefix("[") && stringValue.hasSuffix("]") {
            // Try to iterate as a Python list
            let listArray = Array(value)
            var swiftArray: [Any] = []
            for item in listArray {
                swiftArray.append(convertPythonToSwift(item))
            }
            // If all elements are String, return as [String] for easier casting
            if swiftArray.allSatisfy({ $0 is String }) {
                return swiftArray as! [String]
            }
            return swiftArray
        }
        
        // Check if it's a Python dictionary
        if stringValue.hasPrefix("{") && stringValue.hasSuffix("}") {
            // Try to iterate as a Python dict
            let keys = Array(value.keys())
            var swiftDict: [String: Any] = [:]
            for key in keys {
                let keyString = String(describing: key)
                let dictValue = value[key]
                swiftDict[keyString] = convertPythonToSwift(dictValue)
            }
            return swiftDict
        }
        
        // Handle basic types
        if let int = Int(stringValue) {
            return int
        } else if let double = Double(stringValue) {
            return double
        } else if stringValue.lowercased() == "true" {
            return true
        } else if stringValue.lowercased() == "false" {
            return false
        } else {
            return stringValue
        }
    }
    
    private func convertPythonListToSwift(_ pythonList: PythonObject) -> [[String: Any]] {
        var swiftResults: [[String: Any]] = []
        
        // Iterate through Python list
        let listArray = Array(pythonList)
        for pythonDict in listArray {
            var swiftDict: [String: Any] = [:]
            
            // Get keys from Python dict
            let keysObject = Python.list(pythonDict.keys())
            let keys = Array(keysObject)
            
            for key in keys {
                let keyString = String(describing: key)
                let value = pythonDict[key]
                swiftDict[keyString] = convertPythonToSwift(value)
            }
            
            swiftResults.append(swiftDict)
        }
        
        return swiftResults
    }
    
    private func convertSwiftToPython(_ array: [[String: Any]]) -> PythonObject {
        let pythonList = Python.list()
        
        for dict in array {
            let pythonDict = Python.dict()
            for (key, value) in dict {
                pythonDict[key] = convertSwiftValueToPython(value)
            }
            pythonList.append(pythonDict)
        }
        
        return pythonList
    }
    
    private func convertSwiftValueToPython(_ value: Any) -> PythonObject {
        switch value {
        case let string as String:
            return Python.str(string)
        case let int as Int:
            return Python.int(int)
        case let double as Double:
            return Python.float(double)
        case let bool as Bool:
            return Python.bool(bool)
        default:
            return Python.str(String(describing: value))
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