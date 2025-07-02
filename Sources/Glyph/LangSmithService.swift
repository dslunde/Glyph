import Foundation

/// Service for LangSmith tracing and logging integration
@MainActor
class LangSmithService: ObservableObject {
    static let shared = LangSmithService()
    
    @Published var isEnabled = false
    @Published var projectName = "Glyph"
    @Published var currentRunId: String?
    
    private let apiKey: String
    private let endpoint: String
    private let session = URLSession.shared
    
    private init() {
        self.apiKey = EnvironmentService.shared.getAPIKey(for: "LANGCHAIN_API_KEY") ?? ""
        self.endpoint = EnvironmentService.shared.getAPIKey(for: "LANGCHAIN_ENDPOINT") ?? "https://api.smith.langchain.com"
        
        // Check if LangSmith is properly configured
        self.isEnabled = !apiKey.isEmpty && 
                        (EnvironmentService.shared.getAPIKey(for: "LANGCHAIN_TRACING_V2") == "true")
        
        if let project = EnvironmentService.shared.getAPIKey(for: "LANGCHAIN_PROJECT") {
            self.projectName = project
        }
        
        if isEnabled {
            print("🔍 LangSmith tracing enabled for project: \(projectName)")
        } else {
            print("⚠️ LangSmith tracing disabled - check API key and configuration")
        }
    }
    
    // MARK: - Run Management
    
    func startSearchRun(topic: String, searchLimit: Int, reliabilityThreshold: Double) async -> String? {
        guard isEnabled else { return nil }
        
        let runId = UUID().uuidString
        let runData: [String: Any] = [
            "id": runId,
            "name": "Search Process",
            "run_type": "chain",
            "start_time": ISO8601DateFormatter().string(from: Date()),
            "inputs": [
                "topic": topic,
                "search_limit": searchLimit,
                "reliability_threshold": reliabilityThreshold
            ],
            "tags": ["search", "glyph", "knowledge-graph"],
            "session_name": "Glyph-Search-\(Date().timeIntervalSince1970)"
        ]
        
        await sendToLangSmith(endpoint: "/runs", data: runData, method: "POST")
        currentRunId = runId
        
        print("🔍 Started LangSmith run: \(runId)")
        return runId
    }
    
    func logStep(runId: String?, stepName: String, inputs: [String: Any], outputs: [String: Any]? = nil, error: String? = nil) async {
        guard isEnabled, let runId = runId else { return }
        
        let stepId = UUID().uuidString
        var stepData: [String: Any] = [
            "id": stepId,
            "parent_run_id": runId,
            "name": stepName,
            "run_type": "tool",
            "start_time": ISO8601DateFormatter().string(from: Date()),
            "inputs": inputs,
            "tags": ["step", stepName.lowercased().replacingOccurrences(of: " ", with: "-")]
        ]
        
        if let outputs = outputs {
            stepData["outputs"] = outputs
            stepData["end_time"] = ISO8601DateFormatter().string(from: Date())
        }
        
        if let error = error {
            stepData["error"] = error
            stepData["end_time"] = ISO8601DateFormatter().string(from: Date())
        }
        
        await sendToLangSmith(endpoint: "/runs", data: stepData, method: "POST")
        
        print("📝 Logged step '\(stepName)' to LangSmith")
    }
    
    func endSearchRun(runId: String?, outputs: [String: Any], error: String? = nil) async {
        guard isEnabled, let runId = runId else { return }
        
        var updateData: [String: Any] = [
            "outputs": outputs,
            "end_time": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let error = error {
            updateData["error"] = error
        }
        
        await sendToLangSmith(endpoint: "/runs/\(runId)", data: updateData, method: "PATCH")
        
        print("🏁 Ended LangSmith run: \(runId)")
        currentRunId = nil
    }
    
    // MARK: - Specialized Logging Methods
    
    func logAPIKeyValidation(runId: String?, keys: [String: Bool]) async {
        await logStep(
            runId: runId,
            stepName: "API Key Validation",
            inputs: ["required_keys": ["OPENAI_API_KEY", "TAVILY_API_KEY"]],
            outputs: [
                "validation_results": keys,
                "all_keys_valid": keys.values.allSatisfy { $0 }
            ]
        )
    }
    
    func logQueryGeneration(runId: String?, topic: String, queries: [String], duration: TimeInterval) async {
        await logStep(
            runId: runId,
            stepName: "Query Generation",
            inputs: [
                "topic": topic,
                "llm_model": "openai-gpt",
                "query_count": 5
            ],
            outputs: [
                "generated_queries": queries,
                "duration_seconds": duration,
                "query_count": queries.count
            ]
        )
    }
    
    func logTavilySearch(runId: String?, queries: [String], results: Int, duration: TimeInterval) async {
        await logStep(
            runId: runId,
            stepName: "Tavily Search",
            inputs: [
                "queries": queries,
                "search_engine": "tavily"
            ],
            outputs: [
                "result_count": results,
                "duration_seconds": duration,
                "queries_processed": queries.count
            ]
        )
    }
    
    func logReliabilityScoring(runId: String?, resultCount: Int, scoredCount: Int, threshold: Double, duration: TimeInterval) async {
        await logStep(
            runId: runId,
            stepName: "Reliability Scoring",
            inputs: [
                "input_results": resultCount,
                "reliability_threshold": threshold,
                "llm_model": "openai-gpt"
            ],
            outputs: [
                "scored_results": scoredCount,
                "passed_threshold": scoredCount,
                "duration_seconds": duration,
                "filtering_ratio": Double(scoredCount) / Double(max(1, resultCount))
            ]
        )
    }
    
    func logResultStreaming(runId: String?, results: Int, streamingDuration: TimeInterval) async {
        await logStep(
            runId: runId,
            stepName: "Result Streaming",
            inputs: [
                "total_results": results,
                "streaming_delay": 0.3
            ],
            outputs: [
                "streamed_results": results,
                "total_duration": streamingDuration,
                "average_delay": streamingDuration / Double(max(1, results))
            ]
        )
    }
    
    func logUserActions(runId: String?, approved: Int, dropped: Int) async {
        await logStep(
            runId: runId,
            stepName: "User Review",
            inputs: [
                "total_results": approved + dropped
            ],
            outputs: [
                "approved_results": approved,
                "dropped_results": dropped,
                "approval_rate": Double(approved) / Double(max(1, approved + dropped))
            ]
        )
    }
    
    func logError(runId: String?, stepName: String, error: Error, context: [String: Any] = [:]) async {
        var inputs = context
        inputs["step"] = stepName
        
        await logStep(
            runId: runId,
            stepName: "Error - \(stepName)",
            inputs: inputs,
            error: error.localizedDescription
        )
    }
    
    // MARK: - Network Communication
    
    private func sendToLangSmith(endpoint: String, data: [String: Any], method: String) async {
        guard isEnabled else { return }
        
        let url = URL(string: "\(self.endpoint)\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: data)
            let (_, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                    // Success
                } else {
                    // Provide specific error context based on status code
                    let errorMessage: String
                    switch httpResponse.statusCode {
                    case 401:
                        errorMessage = "⚠️ LangSmith authentication failed (401) - API key may be invalid or expired. Tracing will continue locally."
                    case 403:
                        errorMessage = "⚠️ LangSmith access forbidden (403) - check API key permissions. Tracing will continue locally."
                    case 429:
                        errorMessage = "⚠️ LangSmith rate limit exceeded (429) - too many requests. Tracing will continue locally."
                    case 500...599:
                        errorMessage = "⚠️ LangSmith server error (\(httpResponse.statusCode)) - service may be temporarily unavailable. Tracing will continue locally."
                    default:
                        errorMessage = "⚠️ LangSmith API error (\(httpResponse.statusCode)) - unexpected response. Tracing will continue locally."
                    }
                    print(errorMessage)
                }
            }
        } catch {
            print("⚠️ LangSmith network error: \(error)")
        }
    }
    
    // MARK: - Configuration
    
    func checkConfiguration() -> [String: Any] {
        return [
            "enabled": isEnabled,
            "api_key_configured": !apiKey.isEmpty,
            "endpoint": endpoint,
            "project": projectName,
            "tracing_enabled": EnvironmentService.shared.getAPIKey(for: "LANGCHAIN_TRACING_V2") == "true"
        ]
    }
} 