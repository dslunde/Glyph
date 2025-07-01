import Foundation
import PythonKit

/// Service for Python-based graph analysis and AI operations
class PythonGraphService: ObservableObject {
    @Published var isInitialized = false
    @Published var isOnlineMode = true
    @Published var lastError: String?
    
    private var python: PythonObject
    private var sys: PythonObject
    
    init() {
        // Initialize Python
        python = Python.library
        sys = Python.import("sys")
        
        // Initialize the service
        Task {
            await initializePython()
        }
    }
    
    @MainActor
    private func initializePython() async {
        do {
            // Import required modules
            let numpy = try python.import("numpy")
            let networkx = try python.import("networkx")
            let json = try python.import("json")
            
            print("Python modules loaded successfully")
            print("NumPy version: \(numpy.__version__)")
            print("NetworkX version: \(networkx.__version__)")
            
            isInitialized = true
        } catch {
            lastError = "Failed to initialize Python: \(error)"
            print(lastError!)
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
    
    // MARK: - Tavily Search Integration
    
    func searchWithTavily(queries: [String], limit: Int = 5, apiKey: String) async throws -> [[String: Any]] {
        guard isInitialized else {
            throw NSError(domain: "PythonGraphService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Python not initialized"])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    // Import Tavily
                    let tavily = try python.import("tavily")
                    
                    // Create Tavily client
                    let client = tavily.TavilyClient(api_key: apiKey)
                    
                    var allResults: [[String: Any]] = []
                    
                    // Perform search for each query
                    for query in queries.prefix(limit) {
                        let searchResult = try client.search(query: query, max_results: 1)
                        
                        // Extract results
                        let results = searchResult["results"]
                        
                        for result in results {
                            let resultDict: [String: Any] = [
                                "title": String(result["title"]) ?? "",
                                "url": String(result["url"]) ?? "",
                                "content": String(result["content"]) ?? "",
                                "score": Double(result["score"]) ?? 0.0,
                                "published_date": String(result.get("published_date", default: "")) ?? ""
                            ]
                            allResults.append(resultDict)
                        }
                    }
                    
                    continuation.resume(returning: allResults)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - LLM Query Generation
    
    func generateSearchQueries(topic: String, apiKey: String) async throws -> [String] {
        guard isInitialized else {
            throw NSError(domain: "PythonGraphService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Python not initialized"])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    // Import OpenAI
                    let openai = try python.import("openai")
                    
                    // Create OpenAI client
                    let client = openai.OpenAI(api_key: apiKey)
                    
                    let prompt = """
                    Generate 5 diverse search queries to comprehensively research the topic: "\(topic)"
                    
                    The queries should cover:
                    1. Fundamentals and basic concepts
                    2. Latest research and developments
                    3. Expert opinions and analysis
                    4. Practical applications and case studies
                    5. Controversies or different perspectives
                    
                    Return only the search queries, one per line, without numbering or additional text.
                    """
                    
                    let response = try client.chat.completions.create(
                        model: "gpt-4o-mini",
                        messages: [
                            ["role": "user", "content": prompt]
                        ],
                        max_tokens: 200,
                        temperature: 0.7
                    )
                    
                    let content = String(response.choices[0].message.content) ?? ""
                    let queries = content.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    
                    continuation.resume(returning: Array(queries.prefix(5)))
                } catch {
                    // Fallback to simple queries if OpenAI fails
                    let fallbackQueries = [
                        "\(topic) fundamentals basics",
                        "\(topic) latest research 2024",
                        "\(topic) expert analysis",
                        "\(topic) applications examples",
                        "\(topic) controversy debate"
                    ]
                    continuation.resume(returning: fallbackQueries)
                }
            }
        }
    }
    
    // MARK: - Reliability Scoring
    
    func scoreReliability(results: [[String: Any]], sourcePreferences: [String], apiKey: String) async throws -> [[String: Any]] {
        guard isInitialized else {
            throw NSError(domain: "PythonGraphService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Python not initialized"])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    // Import OpenAI
                    let openai = try python.import("openai")
                    
                    // Create OpenAI client
                    let client = openai.OpenAI(api_key: apiKey)
                    
                    var scoredResults: [[String: Any]] = []
                    
                    for result in results {
                        let title = result["title"] as? String ?? ""
                        let content = result["content"] as? String ?? ""
                        let url = result["url"] as? String ?? ""
                        
                        let prompt = """
                        Rate the reliability of this source on a scale of 0-100:
                        
                        Title: \(title)
                        URL: \(url)
                        Content Preview: \(String(content.prefix(200)))
                        
                        Consider:
                        - Domain authority and reputation
                        - Content quality and objectivity
                        - Presence of citations and sources
                        - Recency and relevance
                        - Author credentials (if available)
                        
                        Return only a number between 0-100.
                        """
                        
                        do {
                            let response = try client.chat.completions.create(
                                model: "gpt-4o-mini",
                                messages: [
                                    ["role": "user", "content": prompt]
                                ],
                                max_tokens: 10,
                                temperature: 0.1
                            )
                            
                            let scoreText = String(response.choices[0].message.content) ?? "50"
                            let score = Int(scoreText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 50
                            
                            var scoredResult = result
                            scoredResult["reliabilityScore"] = score
                            scoredResults.append(scoredResult)
                        } catch {
                            // Fallback scoring based on domain
                            var fallbackScore = 50
                            let urlLower = url.lowercased()
                            
                            if urlLower.contains("edu") || urlLower.contains("gov") {
                                fallbackScore = 85
                            } else if urlLower.contains("org") {
                                fallbackScore = 70
                            } else if urlLower.contains("com") || urlLower.contains("net") {
                                fallbackScore = 60
                            }
                            
                            var scoredResult = result
                            scoredResult["reliabilityScore"] = fallbackScore
                            scoredResults.append(scoredResult)
                        }
                    }
                    
                    continuation.resume(returning: scoredResults)
                } catch {
                    // Return results with default scores
                    let defaultScoredResults = results.map { result in
                        var scored = result
                        scored["reliabilityScore"] = 50
                        return scored
                    }
                    continuation.resume(returning: defaultScoredResults)
                }
            }
        }
    }
    
    // MARK: - Online/Offline Mode
    
    func toggleOnlineMode() {
        isOnlineMode.toggle()
    }
    
    // MARK: - Dependency Check
    
    func checkPythonDependencies() -> [String: Bool] {
        var status: [String: Bool] = [:]
        
        let modules = ["numpy", "networkx", "tavily", "openai", "json"]
        
        for module in modules {
            do {
                _ = try python.import(module)
                status[module] = true
            } catch {
                status[module] = false
            }
        }
        
        return status
    }
} 