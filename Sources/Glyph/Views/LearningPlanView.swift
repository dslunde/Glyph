import SwiftUI

struct LearningPlanView: View {
    let project: Project
    @StateObject private var pythonService = PythonGraphService()
    @State private var learningPlanData: [String: Any]?
    @State private var isGenerating = false
    @State private var selectedPhase: String?
    @State private var expandedConcepts: Set<String> = []
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with generation button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Learning Plan")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if let data = learningPlanData {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.blue)
                            Text("\(data["total_estimated_time"] as? Int ?? 0) hours • \(data["total_concepts"] as? Int ?? 0) concepts")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                if isGenerating {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Generating...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Button("Generate from Graph") {
                        Task {
                            await generateLearningPlan()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(project.graphData?.minimalSubgraph == nil)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Content
            if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    
                    Text("Generation Error")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(error)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Try Again") {
                        errorMessage = nil
                        Task {
                            await generateLearningPlan()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
            } else if let data = learningPlanData {
                ScrollView {
                    VStack(spacing: 24) {
                        // Overview section
                        LearningPlanOverviewView(data: data)
                        
                        // Phase breakdown
                        LearningPhaseBreakdownView(data: data, selectedPhase: $selectedPhase)
                        
                        // Detailed concepts by phase
                        if let selectedPhase = selectedPhase {
                            LearningPhaseDetailView(
                                phase: selectedPhase,
                                data: data,
                                expandedConcepts: $expandedConcepts
                            )
                        }
                    }
                    .padding()
                }
                
            } else {
                // Empty state - show default or prompt to generate
                VStack(spacing: 20) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("Learning Plan")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    VStack(spacing: 8) {
                        if project.graphData?.minimalSubgraph != nil {
                            Text("Generate a structured learning plan from your knowledge graph")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Button("Generate Learning Plan") {
                                Task {
                                    await generateLearningPlan()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Text("Generate a knowledge graph first to create your learning plan")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            // Auto-generate if we have a minimal subgraph but no plan data
            if learningPlanData == nil && project.graphData?.minimalSubgraph != nil {
                Task {
                    await generateLearningPlan()
                }
            }
        }
    }
    
    private func generateLearningPlan() async {
        guard let minimalSubgraph = project.graphData?.minimalSubgraph else {
            errorMessage = "No minimal subgraph available. Please generate a knowledge graph first."
            return
        }
        
        isGenerating = true
        errorMessage = nil
        
        do {
            // Convert minimal subgraph to dictionary format
            let minimalSubgraphDict = convertMinimalSubgraphToDict(minimalSubgraph)
            
            // Use empty sources array for now - could be enhanced to use actual sources
            let sources: [[String: Any]] = []
            
            let result = try await pythonService.generateLearningPlan(
                from: minimalSubgraphDict,
                sources: sources,
                topic: project.topic.isEmpty ? project.name : project.topic,
                depth: project.depth.rawValue
            )
            
            await MainActor.run {
                learningPlanData = result
                // Auto-select first phase
                if let conceptGroups = result["concept_groups"] as? [String: Any] {
                    selectedPhase = conceptGroups.keys.first
                }
            }
            
        } catch {
            await MainActor.run {
                errorMessage = "Failed to generate learning plan: \(error.localizedDescription)"
            }
        }
        
        await MainActor.run {
            isGenerating = false
        }
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
}

// MARK: - Supporting Views

struct LearningPlanOverviewView: View {
    let data: [String: Any]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Overview")
                .font(.title3)
                .fontWeight(.semibold)
            
            HStack(spacing: 20) {
                StatCard(
                    title: "Total Time",
                    value: "\(data["total_estimated_time"] as? Int ?? 0)h",
                    icon: "clock",
                    color: .blue
                )
                
                StatCard(
                    title: "Concepts",
                    value: "\(data["total_concepts"] as? Int ?? 0)",
                    icon: "lightbulb",
                    color: .orange
                )
                
                StatCard(
                    title: "Sources",
                    value: "\(data["sources_used"] as? Int ?? 0)",
                    icon: "doc.text",
                    color: .green
                )
            }
            
            if let rationale = data["learning_path_rationale"] as? String {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Learning Strategy")
                        .font(.headline)
                    
                    Text(rationale)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct LearningPhaseBreakdownView: View {
    let data: [String: Any]
    @Binding var selectedPhase: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Learning Phases")
                .font(.title3)
                .fontWeight(.semibold)
            
            if let phaseBreakdown = data["phase_breakdown"] as? [String: Int],
               let conceptGroups = data["concept_groups"] as? [String: [[String: Any]]] {
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                    ForEach(Array(phaseBreakdown.keys).sorted(), id: \.self) { phase in
                        PhaseCard(
                            phase: phase,
                            timeEstimate: phaseBreakdown[phase] ?? 0,
                            conceptCount: (conceptGroups[phase] as? [[String: Any]])?.count ?? 0,
                            isSelected: selectedPhase == phase
                        ) {
                            selectedPhase = selectedPhase == phase ? nil : phase
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct PhaseCard: View {
    let phase: String
    let timeEstimate: Int
    let conceptCount: Int
    let isSelected: Bool
    let onTap: () -> Void
    
    var phaseInfo: (title: String, color: Color, icon: String) {
        switch phase {
        case "foundation":
            return ("Foundation", .blue, "building.2")
        case "intermediate":
            return ("Intermediate", .orange, "arrow.up.right")
        case "advanced":
            return ("Advanced", .purple, "graduationcap")
        case "practical":
            return ("Practical", .green, "wrench.and.screwdriver")
        default:
            return (phase.capitalized, .gray, "circle")
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                Image(systemName: phaseInfo.icon)
                    .font(.title2)
                    .foregroundColor(phaseInfo.color)
                
                Text(phaseInfo.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                VStack(spacing: 4) {
                    Text("\(timeEstimate)h")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(phaseInfo.color)
                    
                    Text("\(conceptCount) concepts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isSelected ? phaseInfo.color.opacity(0.2) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? phaseInfo.color : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct LearningPhaseDetailView: View {
    let phase: String
    let data: [String: Any]
    @Binding var expandedConcepts: Set<String>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(phase.capitalized) Phase Details")
                .font(.title3)
                .fontWeight(.semibold)
            
            if let conceptGroups = data["concept_groups"] as? [String: [[String: Any]]],
               let concepts = conceptGroups[phase] as? [[String: Any]] {
                
                LazyVStack(spacing: 12) {
                    ForEach(Array(concepts.enumerated()), id: \.offset) { index, concept in
                        ConceptDetailCard(
                            concept: concept,
                            isExpanded: expandedConcepts.contains("\(phase)_\(index)")
                        ) {
                            if expandedConcepts.contains("\(phase)_\(index)") {
                                expandedConcepts.remove("\(phase)_\(index)")
                            } else {
                                expandedConcepts.insert("\(phase)_\(index)")
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct ConceptDetailCard: View {
    let concept: [String: Any]
    let isExpanded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Button(action: onToggle) {
                HStack {
                    Image(systemName: conceptTypeIcon)
                        .foregroundColor(conceptTypeColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(concept["name"] as? String ?? "Unknown Concept")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        HStack {
                            Text("\(concept["time_estimate"] as? Int ?? 0)h")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(conceptTypeColor.opacity(0.2))
                                .cornerRadius(4)
                            
                            Text((concept["type"] as? String ?? "concept").capitalized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            // Expanded content
            if isExpanded {
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    if let description = concept["description"] as? String {
                        Text(description)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    // Connections
                    if let connections = concept["connections"] as? [[String: Any]], !connections.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Related Concepts")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            ForEach(Array(connections.enumerated()), id: \.offset) { _, connection in
                                HStack {
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    
                                    Text(connection["name"] as? String ?? "Unknown")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    
                    // Resources
                    if let resources = concept["resources"] as? [[String: Any]], !resources.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Learning Resources")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            ForEach(Array(resources.enumerated()), id: \.offset) { _, resource in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(resource["title"] as? String ?? "Unknown Resource")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    
                                    Text(resource["description"] as? String ?? "")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.leading, 8)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(conceptTypeColor.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var conceptTypeIcon: String {
        switch concept["type"] as? String {
        case "concept": return "lightbulb"
        case "entity": return "cube"
        case "insight": return "sparkles"
        case "document": return "doc.text"
        default: return "circle"
        }
    }
    
    private var conceptTypeColor: Color {
        switch concept["type"] as? String {
        case "concept": return .blue
        case "entity": return .green
        case "insight": return .purple
        case "document": return .orange
        default: return .gray
        }
    }
} 