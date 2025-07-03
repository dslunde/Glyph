import SwiftUI

struct AIInsightsView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @StateObject private var pythonService = PythonGraphService()
    @State private var selectedInsightTab: InsightTab = .analysis
    @State private var isGeneratingAnalysis = false
    @State private var analysisReport: AnalysisReport?
    @State private var showingAnalysisError = false
    @State private var analysisErrorMessage = ""
    @State private var currentProjectId: UUID?
    
    private var project: Project? {
        projectManager.selectedProject
    }
    
    enum InsightTab: String, CaseIterable {
        case analysis = "Analysis"
        case learningPlan = "Learning Plan"
        case knowledgeGraph = "Knowledge Graph"
        case chat = "Chat"
        
        var iconName: String {
            switch self {
            case .analysis: return "sparkles"
            case .learningPlan: return "doc.text"
            case .knowledgeGraph: return "network"
            case .chat: return "message"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with tab navigation
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Insights")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if let project = project {
                        Text(project.topic.isEmpty ? project.name : project.topic)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Tab selector
                HStack(spacing: 4) {
                    ForEach(InsightTab.allCases, id: \.self) { tab in
                        Button(action: { selectedInsightTab = tab }) {
                            HStack(spacing: 6) {
                                Image(systemName: tab.iconName)
                                    .font(.caption)
                                Text(tab.rawValue)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedInsightTab == tab ? Color.blue : Color.clear)
                            .foregroundColor(selectedInsightTab == tab ? .white : .primary)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Tab content with fixed frame to prevent window resizing
            Group {
                switch selectedInsightTab {
                case .analysis:
                    AnalysisView(
                        isGenerating: $isGeneratingAnalysis,
                        analysisReport: $analysisReport,
                        onGenerateAnalysis: generateAnalysis,
                        onRegenerateAnalysis: regenerateAnalysis
                    )
                    
                case .learningPlan:
                    LearningPlanView()
                    
                case .knowledgeGraph:
                    KnowledgeGraphCanvasView()
                    
                case .chat:
                    ChatView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 800, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        .alert("Analysis Error", isPresented: $showingAnalysisError) {
            Button("OK") { }
        } message: {
            Text(analysisErrorMessage)
        }
        .onAppear {
            checkProjectChange()
        }
        .onChange(of: project?.id) { _ in
            checkProjectChange()
        }
    }
    
    private func checkProjectChange() {
        if currentProjectId != project?.id {
            // Reset analysis state for new project
            analysisReport = nil
            isGeneratingAnalysis = false
            showingAnalysisError = false
            analysisErrorMessage = ""
            currentProjectId = project?.id
            
            // Load existing analysis if available
            loadExistingAnalysis()
        }
    }
    
    private func loadExistingAnalysis() {
        guard let project = project else { return }
        
        // Check if project has saved analysis report
        if let savedReport = project.analysisReport {
            analysisReport = savedReport
        }
    }
    
    private func generateAnalysis() {
        guard let project = project else {
            showAnalysisError("No project selected.")
            return
        }
        
        guard let graphData = project.graphData,
              let minimalSubgraph = graphData.minimalSubgraph,
              !minimalSubgraph.nodes.isEmpty else {
            showAnalysisError("Knowledge graph is required for analysis. Please generate a knowledge graph first.")
            return
        }
        
        isGeneratingAnalysis = true
        
        Task {
            do {
                let report = try await performAdvancedAnalysis(
                    project: project,
                    graphData: graphData,
                    minimalSubgraph: minimalSubgraph
                )
                
                await MainActor.run {
                    analysisReport = report
                    isGeneratingAnalysis = false
                    
                    // Save analysis to project
                    projectManager.saveAnalysisReport(report, for: project)
                }
                
            } catch {
                await MainActor.run {
                    isGeneratingAnalysis = false
                    showAnalysisError("Failed to generate analysis: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func regenerateAnalysis() {
        analysisReport = nil
        generateAnalysis()
    }
    
    private func performAdvancedAnalysis(
        project: Project,
        graphData: GraphData,
        minimalSubgraph: MinimalSubgraph
    ) async throws -> AnalysisReport {
        
        // Convert data to Python-compatible format
        let graphDict = convertGraphDataToDict(graphData)
        let minimalSubgraphDict = convertMinimalSubgraphToDict(minimalSubgraph)
        let sources = project.sources?.map { $0.toDictionary() } ?? []
        
        // Perform analysis using Python service
        let analysisResults = try await pythonService.performAdvancedAnalysis(
            fullGraph: graphDict,
            minimalSubgraph: minimalSubgraphDict,
            sources: sources,
            topic: project.topic.isEmpty ? project.name : project.topic,
            hypotheses: project.hypotheses,
            controversialAspects: project.controversialAspects
        )
        
        // Parse results and create report
        return AnalysisReport(
            id: UUID(),
            projectId: project.id,
            generatedAt: Date(),
            topic: project.topic.isEmpty ? project.name : project.topic,
            knowledgeGaps: parseKnowledgeGaps(analysisResults["knowledge_gaps"]),
            counterintuitiveInsights: parseCounterinsights(analysisResults["counterintuitive_insights"]),
            uncommonInsights: parseUncommonInsights(analysisResults["uncommon_insights"]),
            summary: analysisResults["summary"] as? String ?? "",
            recommendations: parseRecommendations(analysisResults["recommendations"]),
            methodology: analysisResults["methodology"] as? String ?? "",
            confidence: analysisResults["confidence"] as? Double ?? 0.8
        )
    }
    
    private func convertGraphDataToDict(_ graphData: GraphData) -> [String: Any] {
        let nodesArray = graphData.nodes.map { node in
            return [
                "id": node.id.uuidString,
                "label": node.label,
                "type": node.type.rawValue,
                "properties": node.properties,
                "position": ["x": node.position.x, "y": node.position.y]
            ]
        }
        
        let edgesArray = graphData.edges.map { edge in
            return [
                "source_id": edge.sourceId.uuidString,
                "target_id": edge.targetId.uuidString,
                "label": edge.label,
                "weight": edge.weight,
                "properties": edge.properties
            ]
        }
        
        return [
            "nodes": nodesArray,
            "edges": edgesArray
        ]
    }
    
    private func convertMinimalSubgraphToDict(_ minimalSubgraph: MinimalSubgraph) -> [String: Any] {
        let nodesArray = minimalSubgraph.nodes.map { node in
            return [
                "id": node.id.uuidString,
                "label": node.label,
                "type": node.type.rawValue,
                "properties": node.properties,
                "position": ["x": node.position.x, "y": node.position.y]
            ]
        }
        
        let edgesArray = minimalSubgraph.edges.map { edge in
            return [
                "source_id": edge.sourceId.uuidString,
                "target_id": edge.targetId.uuidString,
                "label": edge.label,
                "weight": edge.weight,
                "properties": edge.properties
            ]
        }
        
        return [
            "nodes": nodesArray,
            "edges": edgesArray,
            "selection_criteria": minimalSubgraph.selectionCriteria,
            "topological_order": minimalSubgraph.topologicalOrder.map { $0.uuidString }
        ]
    }
    
    private func parseKnowledgeGaps(_ data: Any?) -> [KnowledgeGap] {
        guard let gapsArray = data as? [[String: Any]] else { return [] }
        
        return gapsArray.compactMap { gapDict in
            guard let gapType = gapDict["type"] as? String,
                  let description = gapDict["description"] as? String else { return nil }
            
            return KnowledgeGap(
                type: gapType,
                description: description,
                severity: gapDict["severity"] as? String ?? "medium",
                suggestedSources: gapDict["suggested_sources"] as? [String] ?? [],
                relatedConcepts: gapDict["related_concepts"] as? [String] ?? []
            )
        }
    }
    
    private func parseCounterinsights(_ data: Any?) -> [CounterintuitiveInsight] {
        guard let insightsArray = data as? [[String: Any]] else { return [] }
        
        return insightsArray.compactMap { insightDict in
            guard let insight = insightDict["insight"] as? String,
                  let explanation = insightDict["explanation"] as? String else { return nil }
            
            return CounterintuitiveInsight(
                insight: insight,
                explanation: explanation,
                confidence: insightDict["confidence"] as? Double ?? 0.7,
                supportingEvidence: insightDict["supporting_evidence"] as? [String] ?? [],
                contradictedBeliefs: insightDict["contradicted_beliefs"] as? [String] ?? []
            )
        }
    }
    
    private func parseUncommonInsights(_ data: Any?) -> [UncommonInsight] {
        guard let insightsArray = data as? [[String: Any]] else { return [] }
        
        return insightsArray.compactMap { insightDict in
            guard let conceptA = insightDict["concept_a"] as? String,
                  let conceptB = insightDict["concept_b"] as? String,
                  let relationship = insightDict["relationship"] as? String else { return nil }
            
            return UncommonInsight(
                conceptA: conceptA,
                conceptB: conceptB,
                relationship: relationship,
                strength: insightDict["strength"] as? Double ?? 0.5,
                novelty: insightDict["novelty"] as? Double ?? 0.5,
                explanation: insightDict["explanation"] as? String ?? ""
            )
        }
    }
    
    private func parseRecommendations(_ data: Any?) -> [String] {
        guard let recommendations = data as? [String] else { return [] }
        return recommendations
    }
    
    private func showAnalysisError(_ message: String) {
        analysisErrorMessage = message
        showingAnalysisError = true
    }
}

// MARK: - Analysis View

struct AnalysisView: View {
    @Binding var isGenerating: Bool
    @Binding var analysisReport: AnalysisReport?
    let onGenerateAnalysis: () -> Void
    let onRegenerateAnalysis: () -> Void
    
    var body: some View {
        if let report = analysisReport {
            // Show analysis report
            AnalysisReportView(
                report: report,
                onRegenerate: onRegenerateAnalysis
            )
        } else if isGenerating {
            // Show generation progress
            AnalysisProgressView()
        } else {
            // Show generate button
            AnalysisWelcomeView(onGenerate: onGenerateAnalysis)
        }
    }
}

// MARK: - Analysis Welcome View

struct AnalysisWelcomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    let onGenerate: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                                        Image(colorScheme == .dark ? "icon_dark" : "icon_light", bundle: .module)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                
                Text("Advanced Knowledge Analysis")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Generate deep insights from your knowledge graph")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                Text("This analysis will identify:")
                    .font(.headline)
                
                AnalysisFeatureRow(
                    icon: "exclamationmark.triangle",
                    color: .orange,
                    title: "Knowledge Gaps",
                    description: "Missing nodes and edges in your knowledge graph that could strengthen understanding"
                )
                
                AnalysisFeatureRow(
                    icon: "lightbulb",
                    color: .yellow,
                    title: "Counterintuitive Truths",
                    description: "Unexpected connections and conclusions that challenge conventional thinking"
                )
                
                AnalysisFeatureRow(
                    icon: "link",
                    color: .purple,
                    title: "Uncommon Insights",
                    description: "Hidden relationships between concepts that aren't typically considered together"
                )
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            
            Button("Generate Analysis") {
                onGenerate()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AnalysisFeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
    }
}

// MARK: - Analysis Progress View

struct AnalysisProgressView: View {
    @State private var currentStep = "Initializing analysis..."
    @State private var progress: Double = 0.0
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .scaleEffect(x: 1, y: 2, anchor: .center)
                
                Text("\(Int(progress * 100))%")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            
            VStack(spacing: 12) {
                Text("Generating Analysis")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(currentStep)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                AnalysisStepView(
                    title: "Graph Analysis",
                    description: "Analyzing knowledge graph structure and relationships",
                    isCompleted: progress > 0.2,
                    isActive: progress <= 0.2
                )
                
                AnalysisStepView(
                    title: "Knowledge Gap Detection",
                    description: "Identifying missing concepts and connections",
                    isCompleted: progress > 0.4,
                    isActive: progress > 0.2 && progress <= 0.4
                )
                
                AnalysisStepView(
                    title: "Counterintuitive Analysis",
                    description: "Finding unexpected relationships and insights",
                    isCompleted: progress > 0.6,
                    isActive: progress > 0.4 && progress <= 0.6
                )
                
                AnalysisStepView(
                    title: "Clustering Analysis",
                    description: "Discovering uncommon conceptual proximities",
                    isCompleted: progress > 0.8,
                    isActive: progress > 0.6 && progress <= 0.8
                )
                
                AnalysisStepView(
                    title: "Report Generation",
                    description: "Formatting insights and recommendations",
                    isCompleted: progress >= 1.0,
                    isActive: progress > 0.8 && progress < 1.0
                )
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            simulateProgress()
        }
    }
    
    private func simulateProgress() {
        let steps = [
            (0.2, "Analyzing graph structure..."),
            (0.4, "Detecting knowledge gaps..."),
            (0.6, "Finding counterintuitive insights..."),
            (0.8, "Performing clustering analysis..."),
            (1.0, "Generating final report...")
        ]
        
        Task { @MainActor in
            for (_, (targetProgress, step)) in steps.enumerated() {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                
                withAnimation(.easeInOut(duration: 1.5)) {
                    progress = targetProgress
                    currentStep = step
                }
            }
        }
    }
}

struct AnalysisStepView: View {
    let title: String
    let description: String
    let isCompleted: Bool
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 12) {
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