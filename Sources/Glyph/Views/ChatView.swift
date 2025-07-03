import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @StateObject private var pythonService = PythonGraphService()
    @StateObject private var llmService = LLMService()
    @State private var messages: [ChatMessage] = []
    @State private var currentMessage = ""
    @State private var isProcessing = false
    @State private var showingSettings = false
    @State private var currentProjectId: UUID?
    
    private var project: Project? {
        projectManager.selectedProject
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Knowledge Graph Assistant")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Ask questions about your \(project?.topic.isEmpty == false ? project!.topic : (project?.name ?? "knowledge graph")) knowledge graph")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { showingSettings.toggle() }) {
                    Image(systemName: "gearshape")
                        .font(.title2)
                }
                .buttonStyle(.bordered)
                .help("Chat Settings")
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Messages area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty {
                            // Welcome message
                            ChatBubbleView(
                                message: ChatMessage(
                                    content: welcomeMessage(),
                                    isUser: false,
                                    timestamp: Date()
                                )
                            )
                        } else {
                            ForEach(messages) { message in
                                ChatBubbleView(message: message)
                                    .id(message.id)
                            }
                        }
                        
                        // Processing indicator
                        if isProcessing {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    if let lastMessage = messages.last {
                        withAnimation(.easeInOut) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // Input area
            HStack(spacing: 12) {
                TextField("Ask about concepts, relationships, or insights...", text: $currentMessage, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .onSubmit {
                        sendMessage()
                    }
                    .disabled(isProcessing)
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .font(.title2)
                        .foregroundColor(currentMessage.isEmpty ? .secondary : .blue)
                }
                .buttonStyle(.plain)
                .disabled(currentMessage.isEmpty || isProcessing)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .sheet(isPresented: $showingSettings) {
            ChatSettingsView()
        }
        .onAppear {
            checkProjectChange()
        }
        .onChange(of: project?.id) { _ in
            checkProjectChange()
        }
    }
    
    private func welcomeMessage() -> String {
        guard let project = project else {
            return """
            Hello! I'm your knowledge graph assistant.
            
            Please select a project to begin exploring your knowledge graph.
            """
        }
        
        let topic = project.topic.isEmpty ? project.name : project.topic
        let nodeCount = project.graphData?.nodes.count ?? 0
        
        return """
        Hello! I'm your knowledge graph assistant for \(topic). 
        
        I have access to your knowledge graph with \(nodeCount) concepts. I can help you:
        
        • Understand key concepts and their relationships
        • Find learning paths through your knowledge graph
        • Explore insights from your research materials
        • Answer questions about specific topics or connections
        
        What would you like to explore?
        """
    }
    
    private func checkProjectChange() {
        // Reset state if project has changed
        if currentProjectId != project?.id {
            print("🔄 Chat view project changed from \(currentProjectId?.uuidString ?? "none") to \(project?.id.uuidString ?? "none")")
            
            // Clear all chat state for the new project
            messages.removeAll()
            currentMessage = ""
            isProcessing = false
            
            // Update current project tracking
            currentProjectId = project?.id
        }
    }
    
    private func sendMessage() {
        guard !currentMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let userMessage = ChatMessage(
            content: currentMessage.trimmingCharacters(in: .whitespacesAndNewlines),
            isUser: true,
            timestamp: Date()
        )
        
        messages.append(userMessage)
        currentMessage = ""
        isProcessing = true
        
        Task {
            do {
                let response = try await processUserQuery(userMessage.content)
                
                await MainActor.run {
                    let assistantMessage = ChatMessage(
                        content: response,
                        isUser: false,
                        timestamp: Date()
                    )
                    messages.append(assistantMessage)
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    let errorMessage = ChatMessage(
                        content: "I apologize, but I encountered an error processing your question: \(error.localizedDescription). Please try again or rephrase your question.",
                        isUser: false,
                        timestamp: Date()
                    )
                    messages.append(errorMessage)
                    isProcessing = false
                }
            }
        }
    }
    
    private func processUserQuery(_ query: String) async throws -> String {
        guard let project = project else {
            return "No project is currently selected. Please select a project to continue."
        }
        
        // Build context from knowledge graph and sources
        let context = buildKnowledgeGraphContext()
        
        // Use the LLM service to generate a response
        return try await llmService.generateResponse(
            query: query,
            context: context,
            topic: project.topic.isEmpty ? project.name : project.topic
        )
    }
    
    private func buildKnowledgeGraphContext() -> KnowledgeGraphContext {
        var context = KnowledgeGraphContext()
        
        guard let project = project else {
            return context
        }
        
        // Add topic information
        context.topic = project.topic.isEmpty ? project.name : project.topic
        
        // Add graph statistics
        if let graphData = project.graphData {
            context.totalNodes = graphData.nodes.count
            context.totalEdges = graphData.edges.count
            context.minimalNodes = graphData.minimalSubgraph?.nodes.count ?? 0
            
            // Add key concepts (from minimal subgraph)
            context.keyConcepts = graphData.minimalSubgraph?.nodes.prefix(10).map { node in
                KeyConcept(
                    name: node.label,
                    type: node.type.displayName,
                    connections: graphData.edges.filter { $0.sourceId == node.id || $0.targetId == node.id }.count
                )
            } ?? []
            
            // Add concept relationships
            context.relationships = graphData.edges.prefix(20).compactMap { edge in
                guard let sourceNode = graphData.nodes.first(where: { $0.id == edge.sourceId }),
                      let targetNode = graphData.nodes.first(where: { $0.id == edge.targetId }) else {
                    return nil
                }
                return ConceptRelationship(
                    source: sourceNode.label,
                    target: targetNode.label,
                    relationship: edge.label.isEmpty ? "related to" : edge.label
                )
            }
        }
        
        // Add project configuration as context
        context.sourceCount = 0  // Sources would be loaded from graph generation process
        context.sourceOverview = []
        
        return context
    }
    
    private func determineSourceType(_ url: String) -> String {
        let urlLower = url.lowercased()
        if urlLower.contains("arxiv.org") { return "Academic Paper" }
        if urlLower.contains("wikipedia.org") { return "Encyclopedia" }
        if urlLower.contains("github.com") { return "Code Repository" }
        if urlLower.contains("blog") || urlLower.contains("medium.com") { return "Blog Post" }
        return "Web Article"
    }
}

// MARK: - LLM Service

@MainActor
class LLMService: ObservableObject {
    private var apiKey: String = ""
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    init() {
        // API key will be retrieved when needed
    }
    
    private func getAPIKey() -> String {
        if apiKey.isEmpty {
            apiKey = EnvironmentService.shared.getAPIKey(for: "OPENAI_API_KEY") ?? ""
        }
        return apiKey
    }
    
    func generateResponse(query: String, context: KnowledgeGraphContext, topic: String) async throws -> String {
        let currentAPIKey = getAPIKey()
        
        guard !currentAPIKey.isEmpty else {
            return """
            I need an OpenAI API key to provide intelligent responses. Please:
            1. Get an API key from OpenAI
            2. Add it to your .env file as OPENAI_API_KEY=your_key_here
            3. Restart the application
            
            For now, I can tell you that your knowledge graph contains \(context.totalNodes) concepts with \(context.totalEdges) relationships.
            """
        }
        
        let systemPrompt = buildSystemPrompt(context: context, topic: topic)
        let messages = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": query]
        ]
        
        let requestBody: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": messages,
            "max_tokens": 800,
            "temperature": 0.7
        ]
        
        guard let url = URL(string: baseURL) else {
            throw LLMError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(currentAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw LLMError.apiError(httpResponse.statusCode)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.parseError
        }
        
        return content
    }
    
    private func buildSystemPrompt(context: KnowledgeGraphContext, topic: String) -> String {
        var prompt = """
        You are a knowledge graph assistant specializing in \(topic). You have access to a comprehensive knowledge graph and source materials.
        
        KNOWLEDGE GRAPH OVERVIEW:
        - Topic: \(topic)
        - Total Concepts: \(context.totalNodes)
        - Total Relationships: \(context.totalEdges)
        - Key Concepts (Minimal Subgraph): \(context.minimalNodes)
        - Source Materials: \(context.sourceCount)
        
        """
        
        if !context.keyConcepts.isEmpty {
            prompt += "\nKEY CONCEPTS:\n"
            for concept in context.keyConcepts {
                prompt += "- \(concept.name) (\(concept.type), \(concept.connections) connections)\n"
            }
        }
        
        if !context.relationships.isEmpty {
            prompt += "\nCONCEPT RELATIONSHIPS:\n"
            for rel in context.relationships.prefix(10) {
                prompt += "- \(rel.source) \(rel.relationship) \(rel.target)\n"
            }
        }
        
        if !context.sourceOverview.isEmpty {
            prompt += "\nSOURCE MATERIALS:\n"
            for source in context.sourceOverview {
                prompt += "- \(source.title) (\(source.type))\n"
            }
        }
        
        prompt += """
        
        INSTRUCTIONS:
        1. Answer questions based on the knowledge graph structure and relationships
        2. Reference specific concepts and their connections when relevant
        3. Suggest learning paths using the concept hierarchy
        4. Be specific about which concepts are most important (high centrality)
        5. Explain how concepts relate to each other
        6. Keep responses conversational but informative
        7. If asked about learning order, recommend starting with foundation concepts
        8. Reference the source materials when discussing specific information
        
        Remember: You're helping someone understand a complex topic through the lens of their personalized knowledge graph.
        """
        
        return prompt
    }
}

// MARK: - Supporting Types

struct KnowledgeGraphContext {
    var topic: String = ""
    var totalNodes: Int = 0
    var totalEdges: Int = 0
    var minimalNodes: Int = 0
    var sourceCount: Int = 0
    var keyConcepts: [KeyConcept] = []
    var relationships: [ConceptRelationship] = []
    var sourceOverview: [SourceSummary] = []
}

struct KeyConcept {
    let name: String
    let type: String
    let connections: Int
}

struct ConceptRelationship {
    let source: String
    let target: String
    let relationship: String
}

struct SourceSummary {
    let title: String
    let type: String
    let relevance: Double
}

enum LLMError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(Int)
    case parseError
    case missingAPIKey
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from API"
        case .apiError(let statusCode):
            return "API error with status code: \(statusCode)"
        case .parseError:
            return "Failed to parse API response"
        case .missingAPIKey:
            return "OpenAI API key is missing"
        }
    }
}

// MARK: - Supporting Views

struct ChatMessage: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp: Date
}

struct ChatBubbleView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 50)
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .foregroundColor(message.isUser ? .white : .primary)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(message.isUser ? Color.blue : Color(nsColor: .controlBackgroundColor))
                    )
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if !message.isUser {
                Spacer(minLength: 50)
            }
        }
    }
}

struct ChatSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var enableNotifications = true
    @State private var responseDetail: ResponseDetail = .balanced
    @State private var includeGraphContext = true
    
    enum ResponseDetail: String, CaseIterable {
        case concise = "Concise"
        case balanced = "Balanced"
        case detailed = "Detailed"
        
        var description: String {
            switch self {
            case .concise:
                return "Short, direct answers"
            case .balanced:
                return "Moderate detail with examples"
            case .detailed:
                return "Comprehensive explanations"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Response Settings") {
                    Picker("Response Detail", selection: $responseDetail) {
                        ForEach(ResponseDetail.allCases, id: \.self) { detail in
                            VStack(alignment: .leading) {
                                Text(detail.rawValue)
                                    .font(.subheadline)
                                Text(detail.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(detail)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Toggle("Include Graph Context", isOn: $includeGraphContext)
                        .help("Include information about node connections and centrality in responses")
                }
                
                Section("Notifications") {
                    Toggle("Enable Response Notifications", isOn: $enableNotifications)
                }
                
                Section("About") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Knowledge Graph Assistant")
                            .font(.headline)
                        
                        Text("This assistant uses your knowledge graph structure and content to answer questions about concepts, relationships, and learning paths.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Chat Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
    }
} 