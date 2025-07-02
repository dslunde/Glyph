import SwiftUI

/// Progress view for knowledge graph generation
struct KnowledgeGraphProgressView: View {
    @StateObject private var pythonService = PythonGraphService()
    @State private var progress: Double = 0.0
    @State private var currentMessage: String = "Initializing..."
    @State private var isCompleted: Bool = false
    @State private var hasError: Bool = false
    @State private var errorMessage: String = ""
    @State private var generatedGraphData: GraphData?
    
    let sources: [[String: Any]]
    let topic: String
    let onCompletion: (GraphData) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                    .symbolEffect(.pulse, options: .repeat(.continuous))
                
                Text("Building Knowledge Graph")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Analyzing \(sources.count) sources for insights")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Progress Section
            VStack(spacing: 16) {
                // Progress Bar
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Progress")
                            .font(.headline)
                        
                        Spacer()
                        
                        Text("\(Int(progress * 100))%")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                    
                    ProgressView(value: progress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .scaleEffect(x: 1, y: 2, anchor: .center)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
                
                // Current Status
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Status")
                        .font(.headline)
                    
                    HStack {
                        if !isCompleted && !hasError {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if isCompleted {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else if hasError {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        }
                        
                        Text(currentMessage)
                            .font(.body)
                            .animation(.easeInOut, value: currentMessage)
                    }
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            
            // Processing Steps
            VStack(alignment: .leading, spacing: 12) {
                Text("Processing Steps")
                    .font(.headline)
                
                ProcessingStepView(
                    title: "Extract Concepts & Entities",
                    description: "NLP analysis of source content",
                    isCompleted: progress > 0.3,
                    isActive: progress > 0.1 && progress <= 0.3
                )
                
                ProcessingStepView(
                    title: "Build Graph Structure",
                    description: "Create nodes and relationships",
                    isCompleted: progress > 0.5,
                    isActive: progress > 0.3 && progress <= 0.5
                )
                
                ProcessingStepView(
                    title: "Calculate Centrality Metrics",
                    description: "PageRank, Eigenvector, Betweenness analysis",
                    isCompleted: progress > 0.7,
                    isActive: progress > 0.5 && progress <= 0.7
                )
                
                ProcessingStepView(
                    title: "Find Minimal Subgraph",
                    description: "Identify core concepts and foundations",
                    isCompleted: progress > 0.85,
                    isActive: progress > 0.7 && progress <= 0.85
                )
                
                ProcessingStepView(
                    title: "Generate Node Embeddings",
                    description: "Create semantic representations",
                    isCompleted: progress >= 1.0,
                    isActive: progress > 0.85 && progress < 1.0
                )
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            
            Spacer()
            
            // Action Buttons
            HStack(spacing: 16) {
                if !isCompleted {
                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                }
                
                if isCompleted && generatedGraphData != nil {
                    Button("Continue") {
                        onCompletion(generatedGraphData!)
                    }
                    .buttonStyle(.borderedProminent)
                } else if hasError {
                    Button("Retry") {
                        startKnowledgeGraphGeneration()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .frame(maxWidth: 600, maxHeight: 700)
        .onAppear {
            startKnowledgeGraphGeneration()
        }
    }
    
    private func startKnowledgeGraphGeneration() {
        progress = 0.0
        currentMessage = "Initializing knowledge graph generation..."
        isCompleted = false
        hasError = false
        errorMessage = ""
        generatedGraphData = nil
        
        Task {
            do {
                let result = try await pythonService.buildKnowledgeGraph(
                    from: sources,
                    topic: topic
                ) { progressValue, message in
                    DispatchQueue.main.async {
                        progress = progressValue
                        currentMessage = message
                    }
                }
                
                await MainActor.run {
                    if let success = result["success"] as? Bool, success {
                        // Convert result to GraphData
                        generatedGraphData = convertResultToGraphData(result)
                        isCompleted = true
                        currentMessage = "Knowledge graph generation completed successfully!"
                    } else {
                        hasError = true
                        errorMessage = result["error_message"] as? String ?? "Unknown error occurred"
                        currentMessage = "Error: \(errorMessage)"
                    }
                }
                
            } catch {
                await MainActor.run {
                    hasError = true
                    errorMessage = error.localizedDescription
                    currentMessage = "Error: \(errorMessage)"
                }
            }
        }
    }
    
    private func convertResultToGraphData(_ result: [String: Any]) -> GraphData {
        var graphData = GraphData()
        
        // Convert nodes
        if let nodes = result["nodes"] as? [[String: Any]] {
            graphData.nodes = nodes.compactMap { nodeDict -> GraphNode? in
                guard let id = nodeDict["id"] as? String,
                      let label = nodeDict["label"] as? String,
                      let typeString = nodeDict["type"] as? String,
                      let nodeType = NodeType(rawValue: typeString) else {
                    return nil
                }
                
                let properties = nodeDict["properties"] as? [String: String] ?? [:]
                let position = nodeDict["position"] as? [String: Double] ?? ["x": 0.0, "y": 0.0]
                
                var node = GraphNode(
                    label: label,
                    type: nodeType,
                    properties: properties,
                    position: CGPoint(x: position["x"] ?? 0.0, y: position["y"] ?? 0.0)
                )
                
                // Set the ID from the stored value if possible
                if let uuid = UUID(uuidString: id) {
                    node.id = uuid
                }
                
                return node
            }
        }
        
        // Convert edges
        if let edges = result["edges"] as? [[String: Any]] {
            graphData.edges = edges.compactMap { edgeDict in
                guard let sourceId = edgeDict["source_id"] as? String,
                      let targetId = edgeDict["target_id"] as? String else {
                    return nil
                }
                
                let label = edgeDict["label"] as? String ?? ""
                let weight = edgeDict["weight"] as? Double ?? 1.0
                let properties = edgeDict["properties"] as? [String: String] ?? [:]
                
                return GraphEdge(
                    sourceId: UUID(uuidString: sourceId) ?? UUID(),
                    targetId: UUID(uuidString: targetId) ?? UUID(),
                    label: label,
                    weight: weight,
                    properties: properties
                )
            }
        }
        
        // Convert minimal subgraph
        if let minimalSubgraphDict = result["minimal_subgraph"] as? [String: Any] {
            var minimalSubgraph = MinimalSubgraph()
            
            if let minimalNodes = minimalSubgraphDict["nodes"] as? [[String: Any]] {
                minimalSubgraph.nodes = minimalNodes.compactMap { nodeDict -> GraphNode? in
                    guard let id = nodeDict["id"] as? String,
                          let label = nodeDict["label"] as? String,
                          let typeString = nodeDict["type"] as? String,
                          let nodeType = NodeType(rawValue: typeString) else {
                        return nil
                    }
                    
                    let properties = nodeDict["properties"] as? [String: String] ?? [:]
                    let position = nodeDict["position"] as? [String: Double] ?? ["x": 0.0, "y": 0.0]
                    
                    var node = GraphNode(
                        label: label,
                        type: nodeType,
                        properties: properties,
                        position: CGPoint(x: position["x"] ?? 0.0, y: position["y"] ?? 0.0)
                    )
                    
                    // Set the ID from the stored value if possible
                    if let uuid = UUID(uuidString: id) {
                        node.id = uuid
                    }
                    
                    return node
                }
            }
            
            if let minimalEdges = minimalSubgraphDict["edges"] as? [[String: Any]] {
                minimalSubgraph.edges = minimalEdges.compactMap { edgeDict in
                    guard let sourceId = edgeDict["source_id"] as? String,
                          let targetId = edgeDict["target_id"] as? String else {
                        return nil
                    }
                    
                    let label = edgeDict["label"] as? String ?? ""
                    let weight = edgeDict["weight"] as? Double ?? 1.0
                    let properties = edgeDict["properties"] as? [String: String] ?? [:]
                    
                    return GraphEdge(
                        sourceId: UUID(uuidString: sourceId) ?? UUID(),
                        targetId: UUID(uuidString: targetId) ?? UUID(),
                        label: label,
                        weight: weight,
                        properties: properties
                    )
                }
            }
            
            minimalSubgraph.selectionCriteria = "Combined centrality metrics (PageRank: 40%, Eigenvector: 30%, Betweenness: 20%, Closeness: 10%)"
            graphData.minimalSubgraph = minimalSubgraph
        }
        
        // Convert metadata
        if let metadata = result["metadata"] as? [String: Any] {
            graphData.metadata.totalNodes = metadata["total_nodes"] as? Int ?? graphData.nodes.count
            graphData.metadata.totalEdges = metadata["total_edges"] as? Int ?? graphData.edges.count
            graphData.metadata.algorithms = metadata["algorithms"] as? [String] ?? []
            
            if let lastAnalysisString = metadata["last_analysis"] as? String {
                let formatter = ISO8601DateFormatter()
                graphData.metadata.lastAnalysis = formatter.date(from: lastAnalysisString)
            }
        }
        
        return graphData
    }
}

/// Individual processing step view
struct ProcessingStepView: View {
    let title: String
    let description: String
    let isCompleted: Bool
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Status Icon
            Group {
                if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if isActive {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 20, height: 20)
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isCompleted ? .primary : (isActive ? .blue : .secondary))
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    KnowledgeGraphProgressView(
        sources: [
            [
                "title": "Sample Article 1",
                "content": "This is sample content for testing...",
                "url": "https://example.com/1"
            ],
            [
                "title": "Sample Article 2", 
                "content": "More sample content for the knowledge graph...",
                "url": "https://example.com/2"
            ]
        ],
        topic: "artificial intelligence",
        onCompletion: { _ in },
        onCancel: { }
    )
} 