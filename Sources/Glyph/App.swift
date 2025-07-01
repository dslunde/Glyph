import SwiftUI

@main
struct GlyphApp: App {
    @StateObject private var projectManager = ProjectManager()
    
    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                // Sidebar with project list
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundColor(.purple)
                        Text("Glyph")
                            .font(.title2)
                            .fontWeight(.bold)
                        Spacer()
                        
                        // Online/Offline indicator
                        HStack(spacing: 4) {
                            Circle()
                                .fill(projectManager.isOnlineMode ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(projectManager.isOnlineMode ? "Online" : "Offline")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    
                    Divider()
                    
                    // Project List
                    List(selection: $projectManager.selectedProject) {
                        ForEach(projectManager.projects) { project in
                            ProjectRowView(project: project)
                                .tag(project)
                        }
                        .onDelete(perform: deleteProjects)
                    }
                    .listStyle(SidebarListStyle())
                    .navigationTitle("")
                    
                    Divider()
                    
                    // Controls
                    VStack(spacing: 8) {
                        Button(action: {
                            projectManager.showingCreateProject = true
                        }) {
                            HStack {
                                Image(systemName: "plus")
                                Text("New Project")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button(action: {
                            projectManager.toggleOnlineMode()
                        }) {
                            HStack {
                                Image(systemName: projectManager.isOnlineMode ? "wifi" : "wifi.slash")
                                Text(projectManager.isOnlineMode ? "Go Offline" : "Go Online")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                }
                .frame(minWidth: 250)
                
            } detail: {
                // Main content area
                if let selectedProject = projectManager.selectedProject {
                    ProjectDetailView(project: selectedProject)
                        .environmentObject(projectManager)
                } else {
                    // Welcome screen
                    VStack(spacing: 20) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 60))
                            .foregroundColor(.purple)
                        
                        VStack(spacing: 8) {
                            Text("Welcome to Glyph")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            
                            Text("Knowledge Graph Explorer")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(spacing: 12) {
                            Text("Create your first project to start exploring connections")
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                            
                            Button("Create Project") {
                                projectManager.showingCreateProject = true
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                        
                        if projectManager.isPythonInitialized {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Python integration ready")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Python integration initializing...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
                }
            }
            .sheet(isPresented: $projectManager.showingCreateProject) {
                CreateProjectView()
                    .environmentObject(projectManager)
            }
            .alert("Error", isPresented: $projectManager.showingError) {
                Button("OK") { }
            } message: {
                Text(projectManager.errorMessage ?? "Unknown error")
            }
        }
    }
    
    private func deleteProjects(offsets: IndexSet) {
        for index in offsets {
            let project = projectManager.projects[index]
            projectManager.deleteProject(project)
        }
    }
}

// MARK: - Supporting Views

struct ProjectRowView: View {
    let project: Project
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name)
                .font(.headline)
                .lineLimit(1)
            
            if !project.topic.isEmpty {
                Text(project.topic)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .lineLimit(1)
            } else if !project.description.isEmpty {
                Text(project.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            // Project configuration badges
            HStack(spacing: 4) {
                // Depth badge
                Text(project.depth.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.2))
                    .foregroundColor(.purple)
                    .cornerRadius(4)
                
                // Sensitivity badge (only show if high)
                if project.sensitivityLevel == .high {
                    Text("High Sensitivity")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                }
                
                Spacer()
            }
            
            HStack {
                Label("\(project.graphData?.nodes.count ?? 0)", systemImage: "circle")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Label("\(project.graphData?.edges.count ?? 0)", systemImage: "arrow.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                // Source preferences indicator
                if !project.sourcePreferences.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(project.sourcePreferences.prefix(3), id: \.self) { preference in
                            Circle()
                                .fill(preference.color)
                                .frame(width: 6, height: 6)
                        }
                        if project.sourcePreferences.count > 3 {
                            Text("+\(project.sourcePreferences.count - 3)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                if project.isOnline {
                    Image(systemName: "cloud")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct CreateProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var projectManager: ProjectManager
    
    @State private var name = ""
    @State private var description = ""
    @State private var topic = ""
    @State private var depth: ProjectDepth = .moderate
    @State private var sourcePreferences: Set<SourcePreference> = [.reliable]
    @State private var hypotheses = ""
    @State private var controversialAspects = ""
    @State private var sensitivityLevel: SensitivityLevel = .low
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Basic Information
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Basic Information")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Project Name")
                                .font(.headline)
                            TextField("Enter project name", text: $name)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.headline)
                            TextField("Enter project description (optional)", text: $description, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...4)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Topic")
                                .font(.headline)
                            TextField("Main research topic or question", text: $topic)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    
                    Divider()
                    
                    // Analysis Configuration
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Analysis Configuration")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Depth Level")
                                .font(.headline)
                            
                            Picker("Depth", selection: $depth) {
                                ForEach(ProjectDepth.allCases, id: \.self) { depth in
                                    VStack(alignment: .leading) {
                                        Text(depth.displayName)
                                            .font(.subheadline)
                                        Text(depth.description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .tag(depth)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Source Preferences")
                                .font(.headline)
                            Text("Select types of sources to include")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                                ForEach(SourcePreference.allCases, id: \.self) { preference in
                                    Button(action: {
                                        if sourcePreferences.contains(preference) {
                                            sourcePreferences.remove(preference)
                                        } else {
                                            sourcePreferences.insert(preference)
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: sourcePreferences.contains(preference) ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(preference.color)
                                            VStack(alignment: .leading) {
                                                Text(preference.displayName)
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                                Text(preference.description)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            Spacer()
                                        }
                                        .padding(8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(sourcePreferences.contains(preference) ? preference.color.opacity(0.1) : Color.clear)
                                                .stroke(preference.color.opacity(0.3), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sensitivity Level")
                                .font(.headline)
                            
                            Picker("Sensitivity Level", selection: $sensitivityLevel) {
                                ForEach(SensitivityLevel.allCases, id: \.self) { level in
                                    VStack(alignment: .leading) {
                                        Text(level.displayName)
                                            .font(.subheadline)
                                        Text(level.description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .tag(level)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    
                    Divider()
                    
                    // Advanced Options
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Advanced Options")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Hypotheses")
                                .font(.headline)
                            TextField("Initial hypotheses or assumptions (optional)", text: $hypotheses, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...4)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Controversial Aspects")
                                .font(.headline)
                            TextField("Areas of potential controversy or bias (optional)", text: $controversialAspects, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...4)
                        }
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("New Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        projectManager.createProject(
                            name: name,
                            description: description,
                            topic: topic,
                            depth: depth,
                            sourcePreferences: Array(sourcePreferences),
                            hypotheses: hypotheses,
                            controversialAspects: controversialAspects,
                            sensitivityLevel: sensitivityLevel
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(width: 600, height: 700)
    }
}

struct ProjectDetailView: View {
    let project: Project
    @EnvironmentObject private var projectManager: ProjectManager
    @State private var showingProjectInfo = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Project header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(project.name)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Button(action: { showingProjectInfo = true }) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    if !project.topic.isEmpty {
                        Text(project.topic)
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    } else if !project.description.isEmpty {
                        Text(project.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // Configuration badges
                    HStack(spacing: 8) {
                        Text(project.depth.displayName)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.2))
                            .foregroundColor(.purple)
                            .cornerRadius(6)
                        
                        if project.sensitivityLevel == .high {
                            Text("High Sensitivity")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.2))
                                .foregroundColor(.orange)
                                .cornerRadius(6)
                        }
                        
                        HStack(spacing: 4) {
                            ForEach(project.sourcePreferences.prefix(3), id: \.self) { preference in
                                Circle()
                                    .fill(preference.color)
                                    .frame(width: 8, height: 8)
                            }
                            if project.sourcePreferences.count > 3 {
                                Text("+\(project.sourcePreferences.count - 3)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                VStack(spacing: 8) {
                    // Analysis button
                    Button(action: {
                        Task {
                            await projectManager.analyzeCurrentProject()
                        }
                    }) {
                        HStack {
                            if projectManager.isAnalyzing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(projectManager.isAnalyzing ? "Analyzing..." : "Analyze")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(projectManager.isAnalyzing)
                    
                    // Progress indicator for graph generation
                    if projectManager.isAnalyzing {
                        VStack(spacing: 4) {
                            ProgressView(value: projectManager.analysisProgress)
                                .frame(width: 120)
                            Text("\(Int(projectManager.analysisProgress * 100))%")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Main content
            if let graphData = project.graphData, !graphData.nodes.isEmpty {
                HSplitView {
                    // Graph visualization
                    GraphVisualizationView(graphData: graphData)
                        .frame(minWidth: 400)
                    
                    // Analysis panel
                    AnalysisPanelView(graphData: graphData, insights: projectManager.insights)
                        .frame(minWidth: 300, maxWidth: 400)
                }
            } else {
                // Empty state with better information
                VStack(spacing: 20) {
                    if projectManager.isAnalyzing {
                        ProgressView(value: projectManager.analysisProgress)
                            .frame(width: 200)
                        
                        Text("Generating Knowledge Graph...")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        
                        Text("Analyzing sources and extracting concepts")
                            .font(.body)
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "network")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        
                        Text("Ready to Generate Graph")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 8) {
                            Text("Click 'Analyze' to start generating your knowledge graph")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Text("Configuration: \(project.depth.displayName) depth, \(project.sourcePreferences.count) source type(s)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingProjectInfo) {
            ProjectInfoView(project: project)
        }
    }
}

// MARK: - Interactive Graph Visualization

struct GraphVisualizationView: View {
    @State private var graphData: GraphData
    @State private var selectedNode: GraphNode?
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var draggedNode: GraphNode?
    @State private var showingNodeDetails = false
    
    init(graphData: GraphData) {
        self._graphData = State(initialValue: graphData)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color(nsColor: .textBackgroundColor)
                    .onTapGesture {
                        selectedNode = nil
                        showingNodeDetails = false
                    }
                
                // Graph Canvas
                Canvas { context, size in
                    context.clipToLayer(opacity: 1) { context in
                        // Apply zoom and pan transformations
                        context.translateBy(x: size.width/2 + panOffset.width, 
                                          y: size.height/2 + panOffset.height)
                        context.scaleBy(x: zoomScale, y: zoomScale)
                        
                        // Draw edges first (so they appear behind nodes)
                        drawEdges(context: context)
                        
                        // Draw nodes
                        drawNodes(context: context)
                    }
                }
                .gesture(
                    SimultaneousGesture(
                        // Pan gesture
                        DragGesture()
                            .onChanged { value in
                                if draggedNode == nil {
                                    panOffset = value.translation
                                }
                            },
                        
                        // Zoom gesture
                        MagnificationGesture()
                            .onChanged { value in
                                zoomScale = max(0.1, min(3.0, value))
                            }
                    )
                )
                .overlay(
                    // Node interaction overlay
                    ForEach(graphData.nodes) { node in
                        let screenPos = nodeScreenPosition(node: node, canvasSize: geometry.size)
                        
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 60, height: 60)
                            .position(screenPos)
                            .onTapGesture {
                                selectedNode = node
                                showingNodeDetails = true
                            }
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        draggedNode = node
                                        updateNodePosition(node: node, offset: value.translation, canvasSize: geometry.size)
                                    }
                                    .onEnded { _ in
                                        draggedNode = nil
                                    }
                            )
                    }
                )
                
                // Graph controls
                VStack {
                    HStack {
                        VStack(spacing: 8) {
                            Button(action: { zoomScale = min(3.0, zoomScale * 1.2) }) {
                                Image(systemName: "plus.magnifyingglass")
                                    .font(.title2)
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: { zoomScale = max(0.1, zoomScale / 1.2) }) {
                                Image(systemName: "minus.magnifyingglass")
                                    .font(.title2)
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: resetView) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.title2)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                        
                        Spacer()
                        
                        // Graph info
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(graphData.nodes.count) nodes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(graphData.edges.count) edges")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Zoom: \(Int(zoomScale * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    }
                    
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showingNodeDetails) {
            if let node = selectedNode {
                NodeDetailView(node: binding(for: node))
                    .environmentObject(GraphViewModel(graphData: $graphData))
            }
        }
    }
    
    private func drawEdges(context: GraphicsContext) {
        for edge in graphData.edges {
            guard let sourceNode = graphData.nodes.first(where: { $0.id == edge.sourceId }),
                  let targetNode = graphData.nodes.first(where: { $0.id == edge.targetId }) else {
                continue
            }
            
            let path = Path { path in
                path.move(to: sourceNode.position)
                path.addLine(to: targetNode.position)
            }
            
            context.stroke(path, with: .color(.secondary), lineWidth: 2.0 * edge.weight)
        }
    }
    
    private func drawNodes(context: GraphicsContext) {
        for node in graphData.nodes {
            let isSelected = selectedNode?.id == node.id
            let isDragged = draggedNode?.id == node.id
            
            // Node circle
            let nodeSize: CGFloat = isSelected ? 50 : (isDragged ? 45 : 40)
            let nodeRect = CGRect(
                x: node.position.x - nodeSize/2,
                y: node.position.y - nodeSize/2,
                width: nodeSize,
                height: nodeSize
            )
            
            context.fill(
                Path(ellipseIn: nodeRect),
                with: .color(isSelected ? node.type.color.opacity(0.8) : node.type.color.opacity(0.6))
            )
            
            context.stroke(
                Path(ellipseIn: nodeRect),
                with: .color(isSelected ? .primary : .secondary),
                lineWidth: isSelected ? 3 : 1
            )
            
            // Node label
            let labelRect = CGRect(
                x: node.position.x - 60,
                y: node.position.y + nodeSize/2 + 5,
                width: 120,
                height: 20
            )
            
            context.draw(
                Text(node.label)
                    .font(.caption)
                    .foregroundColor(.primary),
                in: labelRect
            )
        }
    }
    
    private func nodeScreenPosition(node: GraphNode, canvasSize: CGSize) -> CGPoint {
        let transformedX = (node.position.x * zoomScale) + canvasSize.width/2 + panOffset.width
        let transformedY = (node.position.y * zoomScale) + canvasSize.height/2 + panOffset.height
        return CGPoint(x: transformedX, y: transformedY)
    }
    
    private func updateNodePosition(node: GraphNode, offset: CGSize, canvasSize: CGSize) {
        if let index = graphData.nodes.firstIndex(where: { $0.id == node.id }) {
            let newX = node.position.x + offset.width / zoomScale
            let newY = node.position.y + offset.height / zoomScale
            graphData.nodes[index].position = CGPoint(x: newX, y: newY)
        }
    }
    
    private func resetView() {
        zoomScale = 1.0
        panOffset = .zero
    }
    
    private func binding(for node: GraphNode) -> Binding<GraphNode> {
        guard let index = graphData.nodes.firstIndex(where: { $0.id == node.id }) else {
            return .constant(node)
        }
        return $graphData.nodes[index]
    }
}

struct AnalysisPanelView: View {
    let graphData: GraphData
    let insights: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Analysis")
                .font(.headline)
            
            if insights.isEmpty {
                Text("No insights available yet")
                    .font(.body)
                    .foregroundColor(.secondary)
            } else {
                ForEach(insights, id: \.self) { insight in
                    Text(insight)
                        .font(.body)
                        .padding(.horizontal)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Graph Supporting Views and ViewModels

class GraphViewModel: ObservableObject {
    @Binding var graphData: GraphData
    
    init(graphData: Binding<GraphData>) {
        self._graphData = graphData
    }
    
    func addNode(_ node: GraphNode) {
        graphData.nodes.append(node)
        graphData.metadata.totalNodes = graphData.nodes.count
    }
    
    func removeNode(_ node: GraphNode) {
        graphData.nodes.removeAll { $0.id == node.id }
        // Remove associated edges
        graphData.edges.removeAll { $0.sourceId == node.id || $0.targetId == node.id }
        graphData.metadata.totalNodes = graphData.nodes.count
        graphData.metadata.totalEdges = graphData.edges.count
    }
    
    func updateNode(_ node: GraphNode) {
        if let index = graphData.nodes.firstIndex(where: { $0.id == node.id }) {
            graphData.nodes[index] = node
        }
    }
    
    func addEdge(_ edge: GraphEdge) {
        graphData.edges.append(edge)
        graphData.metadata.totalEdges = graphData.edges.count
    }
    
    func removeEdge(_ edge: GraphEdge) {
        graphData.edges.removeAll { $0.id == edge.id }
        graphData.metadata.totalEdges = graphData.edges.count
    }
}

struct NodeDetailView: View {
    @Binding var node: GraphNode
    @EnvironmentObject var graphViewModel: GraphViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var editedLabel: String
    @State private var editedType: NodeType
    @State private var showingDeleteConfirmation = false
    
    init(node: Binding<GraphNode>) {
        self._node = node
        self._editedLabel = State(initialValue: node.wrappedValue.label)
        self._editedType = State(initialValue: node.wrappedValue.type)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Node Information") {
                    HStack {
                        Image(systemName: editedType.iconName)
                            .foregroundColor(editedType.color)
                            .font(.title2)
                        
                        VStack(alignment: .leading) {
                            TextField("Node Label", text: $editedLabel)
                                .font(.headline)
                            
                            Text("Type: \(editedType.displayName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    Picker("Node Type", selection: $editedType) {
                        ForEach(NodeType.allCases, id: \.self) { type in
                            HStack {
                                Image(systemName: type.iconName)
                                    .foregroundColor(type.color)
                                Text(type.displayName)
                            }
                            .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section("Properties") {
                    if node.properties.isEmpty {
                        Text("No properties defined")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(Array(node.properties.keys.sorted()), id: \.self) { key in
                            HStack {
                                Text(key)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(node.properties[key] ?? "")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Section("Position") {
                    HStack {
                        Text("X: \(Int(node.position.x))")
                        Spacer()
                        Text("Y: \(Int(node.position.y))")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Section("Actions") {
                    Button(action: {
                        showingDeleteConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Node")
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Node Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                    .disabled(editedLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Delete Node", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    graphViewModel.removeNode(node)
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete this node? This action cannot be undone and will also remove all connected edges.")
            }
        }
        .frame(width: 400, height: 500)
    }
    
    private func saveChanges() {
        node.label = editedLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        node.type = editedType
        graphViewModel.updateNode(node)
    }
}

// MARK: - Project Information View

struct ProjectInfoView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Basic Information") {
                    LabeledContent("Name", value: project.name)
                    
                    if !project.description.isEmpty {
                        LabeledContent("Description", value: project.description)
                    }
                    
                    if !project.topic.isEmpty {
                        LabeledContent("Topic", value: project.topic)
                    }
                    
                    LabeledContent("Created", value: project.createdAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Last Modified", value: project.lastModified.formatted(date: .abbreviated, time: .shortened))
                }
                
                Section("Analysis Configuration") {
                    HStack {
                        Text("Depth Level")
                        Spacer()
                        Text(project.depth.displayName)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.2))
                            .foregroundColor(.purple)
                            .cornerRadius(6)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Source Preferences")
                            .fontWeight(.medium)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                            ForEach(project.sourcePreferences, id: \.self) { preference in
                                HStack {
                                    Circle()
                                        .fill(preference.color)
                                        .frame(width: 8, height: 8)
                                    Text(preference.displayName)
                                        .font(.caption)
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(preference.color.opacity(0.1))
                                .cornerRadius(6)
                            }
                        }
                    }
                    
                    HStack {
                        Text("Sensitivity Level")
                        Spacer()
                        Text(project.sensitivityLevel.displayName)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(project.sensitivityLevel == .high ? Color.orange.opacity(0.2) : Color.gray.opacity(0.2))
                            .foregroundColor(project.sensitivityLevel == .high ? .orange : .secondary)
                            .cornerRadius(6)
                    }
                }
                
                if !project.hypotheses.isEmpty || !project.controversialAspects.isEmpty {
                    Section("Advanced Options") {
                        if !project.hypotheses.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Hypotheses")
                                    .fontWeight(.medium)
                                Text(project.hypotheses)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if !project.controversialAspects.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Controversial Aspects")
                                    .fontWeight(.medium)
                                Text(project.controversialAspects)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Section("Graph Statistics") {
                    if let graphData = project.graphData {
                        LabeledContent("Nodes", value: "\(graphData.nodes.count)")
                        LabeledContent("Edges", value: "\(graphData.edges.count)")
                        
                        if let lastAnalysis = graphData.metadata.lastAnalysis {
                            LabeledContent("Last Analysis", value: lastAnalysis.formatted(date: .abbreviated, time: .shortened))
                        }
                        
                        if !graphData.metadata.algorithms.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Applied Algorithms")
                                    .fontWeight(.medium)
                                Text(graphData.metadata.algorithms.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("No graph data available")
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
            }
            .navigationTitle("Project Information")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 500, height: 600)
    }
} 