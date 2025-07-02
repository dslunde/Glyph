import SwiftUI

struct ChatView: View {
    let project: Project
    @StateObject private var pythonService = PythonGraphService()
    @State private var messages: [ChatMessage] = []
    @State private var currentMessage = ""
    @State private var isProcessing = false
    @State private var showingSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Knowledge Graph Assistant")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Ask questions about your \(project.topic.isEmpty ? project.name : project.topic) knowledge graph")
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
                                    content: "Hello! I'm your knowledge graph assistant. I can help you understand the concepts, relationships, and insights from your research. What would you like to explore?",
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
            let response = await processUserQuery(userMessage.content)
            
            await MainActor.run {
                let assistantMessage = ChatMessage(
                    content: response,
                    isUser: false,
                    timestamp: Date()
                )
                messages.append(assistantMessage)
                isProcessing = false
            }
        }
    }
    
    private func processUserQuery(_ query: String) async -> String {
        // Mock LLM response based on knowledge graph context
        try? await Task.sleep(nanoseconds: 1_000_000_000) // Simulate processing time
        
        return generateMockResponse(for: query)
    }
    
    private func generateMockResponse(for query: String) -> String {
        let lowercaseQuery = query.lowercased()
        
        // Context from the project
        let graphData = project.graphData
        let nodeCount = graphData?.nodes.count ?? 0
        let edgeCount = graphData?.edges.count ?? 0
        let minimalNodeCount = graphData?.minimalSubgraph?.nodes.count ?? 0
        
        // Pattern-based responses
        if lowercaseQuery.contains("how many") || lowercaseQuery.contains("count") {
            return "Your knowledge graph contains \(nodeCount) total concepts and \(edgeCount) relationships. The minimal subgraph focuses on the \(minimalNodeCount) most important concepts for learning."
        }
        
        if lowercaseQuery.contains("concept") || lowercaseQuery.contains("node") {
            let conceptNodes = graphData?.nodes.filter { $0.type == .concept }.count ?? 0
            return "I found \(conceptNodes) core concepts in your knowledge graph. These represent the fundamental ideas and principles in \(project.topic.isEmpty ? project.name : project.topic). Would you like me to explain any specific concept?"
        }
        
        if lowercaseQuery.contains("relationship") || lowercaseQuery.contains("connection") {
            return "The knowledge graph shows \(edgeCount) relationships between concepts. These connections help reveal how different ideas build upon each other and form the learning pathway in your topic."
        }
        
        if lowercaseQuery.contains("learning") || lowercaseQuery.contains("study") {
            return "Based on your knowledge graph, I recommend starting with the foundation concepts in the minimal subgraph. These \(minimalNodeCount) concepts were selected using centrality analysis to ensure you build proper understanding progressively."
        }
        
        if lowercaseQuery.contains("important") || lowercaseQuery.contains("key") {
            return "The most important concepts in your knowledge graph are those with high centrality scores - they appear in the minimal subgraph because they connect to many other concepts and serve as foundational building blocks."
        }
        
        if lowercaseQuery.contains("start") || lowercaseQuery.contains("begin") {
            return "I'd recommend starting with the Foundation phase in your learning plan. These concepts have the highest centrality scores and will give you the strongest base for understanding more advanced topics."
        }
        
        // Default response
        return "That's an interesting question about \(project.topic.isEmpty ? project.name : project.topic). Based on your knowledge graph with \(nodeCount) concepts, I can help you explore the relationships and learning pathways. Could you be more specific about what aspect you'd like to understand?"
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