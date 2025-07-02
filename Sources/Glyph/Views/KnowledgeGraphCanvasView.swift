import SwiftUI

struct KnowledgeGraphCanvasView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @State private var minimalGraphData: GraphData = GraphData()
    @State private var selectedNode: GraphNode?
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var draggedNode: GraphNode?
    @State private var showingNodeDetails = false
    @State private var showingControls = true
    @State private var currentProjectId: UUID?
    
    // User controls
    @State private var nodeSize: Double = 40.0
    @State private var nodeSpacing: Double = 1.0
    @State private var edgeVisibility: Double = 1.0
    
    private var project: Project? {
        projectManager.selectedProject
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with info and controls toggle
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Knowledge Graph Canvas")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    HStack {
                        Text("Minimal Subgraph")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                        
                        Text("\(minimalGraphData.nodes.count) nodes • \(minimalGraphData.edges.count) edges")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: { showingControls.toggle() }) {
                    Image(systemName: showingControls ? "sidebar.right" : "sidebar.left")
                        .font(.title2)
                }
                .buttonStyle(.bordered)
                .help("Toggle Controls")
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Main content
            HSplitView {
                // Graph visualization
                GeometryReader { geometry in
                    ZStack {
                        // Background
                        Color(nsColor: .controlBackgroundColor)
                            .onTapGesture {
                                selectedNode = nil
                                showingNodeDetails = false
                            }
                        
                        // Graph Canvas
                        Canvas { context, size in
                            print("🖼️ Canvas rendering: size=\(size), nodes=\(minimalGraphData.nodes.count), panOffset=\(panOffset), zoomScale=\(zoomScale)")
                            
                            // Apply transformations: translate to center, then apply pan and zoom
                            context.translateBy(x: size.width / 2, y: size.height / 2)
                            context.translateBy(x: panOffset.width, y: panOffset.height)
                            context.scaleBy(x: zoomScale, y: zoomScale)
                            
                            print("🔧 Canvas transformations applied: center=(\(size.width/2), \(size.height/2)), pan=\(panOffset), zoom=\(zoomScale)")
                            
                            // Draw edges first
                            drawEdges(context: context)
                            
                            // Draw nodes
                            drawNodes(context: context)
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
                                        zoomScale = max(0.1, min(5.0, value))
                                    }
                            )
                        )
                        .overlay(
                            // Node interaction overlay
                            ForEach(minimalGraphData.nodes) { node in
                                let screenPos = nodeScreenPosition(node: node, canvasSize: geometry.size)
                                
                                Circle()
                                    .fill(Color.clear)
                                    .frame(width: nodeSize + 20, height: nodeSize + 20)
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
                        
                        // Graph controls overlay
                        VStack {
                            HStack {
                                VStack(spacing: 8) {
                                    Button(action: { zoomScale = min(5.0, zoomScale * 1.2) }) {
                                        Image(systemName: "plus.magnifyingglass")
                                            .font(.title3)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    
                                    Button(action: { zoomScale = max(0.1, zoomScale / 1.2) }) {
                                        Image(systemName: "minus.magnifyingglass")
                                            .font(.title3)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    
                                    Button(action: centerGraph) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.title3)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .help("Center and Reset View")
                                }
                                .padding(.top, 12)
                                .padding(.leading, 12)
                                
                                Spacer()
                            }
                            
                            Spacer()
                        }
                    }
                }
                .frame(minWidth: 400)
                
                // Controls panel
                if showingControls {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // View Controls
                            ControlSection(title: "View Controls") {
                                VStack(spacing: 12) {
                                    ControlSlider(
                                        title: "Node Size",
                                        value: $nodeSize,
                                        range: 20...80,
                                        step: 5,
                                        formatter: { "\(Int($0))px" }
                                    )
                                    
                                    ControlSlider(
                                        title: "Node Spacing",
                                        value: $nodeSpacing,
                                        range: 0.5...3.0,
                                        step: 0.1,
                                        formatter: { String(format: "%.1fx", $0) }
                                    )
                                    
                                    ControlSlider(
                                        title: "Edge Visibility",
                                        value: $edgeVisibility,
                                        range: 0.0...1.0,
                                        step: 0.1,
                                        formatter: { "\(Int($0 * 100))%" }
                                    )
                                }
                            }
                            
                            // Graph Analysis
                            ControlSection(title: "Graph Analysis") {
                                VStack(alignment: .leading, spacing: 8) {
                                    AnalysisStatRow(
                                        label: "Total Nodes",
                                        value: "\(minimalGraphData.nodes.count)"
                                    )
                                    
                                    AnalysisStatRow(
                                        label: "Total Edges",
                                        value: "\(minimalGraphData.edges.count)"
                                    )
                                    
                                    if let selectedNode = selectedNode {
                                        Divider()
                                        
                                        Text("Selected Node")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        
                                        AnalysisStatRow(
                                            label: "Type",
                                            value: selectedNode.type.displayName
                                        )
                                        
                                        AnalysisStatRow(
                                            label: "Connections",
                                            value: "\(nodeConnections(selectedNode))"
                                        )
                                    }
                                }
                            }
                            
                            Spacer()
                        }
                        .padding()
                    }
                    .frame(minWidth: 280, maxWidth: 350)
                    .background(Color(nsColor: .controlBackgroundColor))
                }
            }
        }
        .sheet(isPresented: $showingNodeDetails) {
            if let node = selectedNode {
                NodeDetailView(node: binding(for: node))
                    .environmentObject(GraphViewModel(graphData: $minimalGraphData))
            }
        }
        .onAppear {
            checkProjectChange()
        }
        .onChange(of: project?.id) { _ in
            checkProjectChange()
        }
        .onChange(of: nodeSpacing) { _ in
            applyNodeSpacing()
        }
    }
    
    // MARK: - Drawing Functions
    
    private func drawEdges(context: GraphicsContext) {
        guard edgeVisibility > 0 else { return }
        
        for edge in minimalGraphData.edges {
            guard let sourceNode = minimalGraphData.nodes.first(where: { $0.id == edge.sourceId }),
                  let targetNode = minimalGraphData.nodes.first(where: { $0.id == edge.targetId }) else {
                continue
            }
            
            // Use actual node positions (which should be in canvas coordinates)
            let sourcePos = CGPoint(x: sourceNode.position.x, y: sourceNode.position.y)
            let targetPos = CGPoint(x: targetNode.position.x, y: targetNode.position.y)
            
            let path = Path { path in
                path.move(to: sourcePos)
                path.addLine(to: targetPos)
            }
            
            let edgeColor = Color.secondary.opacity(edgeVisibility * 0.6)
            let lineWidth = 1.0 + (edge.weight * 0.5)
            
            context.stroke(path, with: .color(edgeColor), lineWidth: lineWidth)
        }
    }
    
    private func drawNodes(context: GraphicsContext) {
        print("🎨 Drawing \(minimalGraphData.nodes.count) nodes")
        
        guard !minimalGraphData.nodes.isEmpty else {
            print("❌ No nodes to draw")
            return
        }
        
        let firstFewNodes = minimalGraphData.nodes.prefix(3)
        for (index, node) in firstFewNodes.enumerated() {
            print("🎯 Node \(index): '\(node.label)' at (\(node.position.x), \(node.position.y)) type: \(node.type)")
        }
        
        for (index, node) in minimalGraphData.nodes.enumerated() {
            let isSelected = selectedNode?.id == node.id
            let isDragged = draggedNode?.id == node.id
            
            let currentNodeSize = nodeSize * (isSelected ? 1.2 : (isDragged ? 1.1 : 1.0))
            
            // Use node position directly (should be in canvas coordinates)
            let nodePos = CGPoint(x: node.position.x, y: node.position.y)
            let nodeRect = CGRect(
                x: nodePos.x - currentNodeSize/2,
                y: nodePos.y - currentNodeSize/2,
                width: currentNodeSize,
                height: currentNodeSize
            )
            
            // Debug first few nodes
            if index < 3 {
                print("🎨 Drawing node \(index): rect=\(nodeRect), size=\(currentNodeSize)")
            }
            
            // Node color based on type
            let nodeColor = node.type.color.opacity(isSelected ? 0.9 : 0.8)
            
            // Draw node circle
            context.fill(
                Path(ellipseIn: nodeRect),
                with: .color(nodeColor)
            )
            
            // Draw node border
            let borderColor = isSelected ? Color.primary : Color.secondary.opacity(0.8)
            context.stroke(
                Path(ellipseIn: nodeRect),
                with: .color(borderColor),
                lineWidth: isSelected ? 3 : 1.5
            )
            
            // Draw node label
            let labelText = Text(node.label.count > 15 ? String(node.label.prefix(15)) + "..." : node.label)
                .font(.system(size: max(10, currentNodeSize * 0.2)))
                .foregroundColor(.primary)
            
            let labelRect = CGRect(
                x: nodePos.x - 60,
                y: nodePos.y + currentNodeSize/2 + 4,
                width: 120,
                height: 20
            )
            
            context.draw(labelText, in: labelRect)
        }
        
        print("✅ Finished drawing \(minimalGraphData.nodes.count) nodes")
    }
    

    
    // MARK: - Project Management
    
    private func checkProjectChange() {
        // Reset state if project has changed
        if currentProjectId != project?.id {
            print("🔄 Graph view project changed from \(currentProjectId?.uuidString ?? "none") to \(project?.id.uuidString ?? "none")")
            
            // Clear all state for the new project
            selectedNode = nil
            draggedNode = nil
            showingNodeDetails = false
            zoomScale = 1.0
            panOffset = .zero
            
            // Load graph data for the new project
            loadProjectGraphData()
            
            // Update current project tracking
            currentProjectId = project?.id
            
            // Initialize positions and center view
            initializeNodePositions()
            centerGraph()
        }
    }
    
    private func loadProjectGraphData() {
        // Initialize with minimal subgraph or fallback to full graph
        var graphData = GraphData()
        
        guard let project = project else {
            print("📊 No project selected")
            minimalGraphData = graphData
            return
        }
        
        if let minimalSubgraph = project.graphData?.minimalSubgraph {
            graphData.nodes = minimalSubgraph.nodes
            graphData.edges = minimalSubgraph.edges
            graphData.metadata = project.graphData?.metadata ?? GraphMetadata()
            print("📊 Loaded minimal subgraph: \(graphData.nodes.count) nodes, \(graphData.edges.count) edges")
        } else if let fullGraphData = project.graphData {
            graphData.nodes = fullGraphData.nodes
            graphData.edges = fullGraphData.edges
            graphData.metadata = fullGraphData.metadata
            print("📊 Loaded full graph: \(graphData.nodes.count) nodes, \(graphData.edges.count) edges")
        } else {
            print("📊 No graph data available for project")
        }
        
        minimalGraphData = graphData
    }
    
    // MARK: - Helper Functions
    
    private func nodeScreenPosition(node: GraphNode, canvasSize: CGSize) -> CGPoint {
        let transformedX = (node.position.x * zoomScale) + panOffset.width + canvasSize.width / 2
        let transformedY = (node.position.y * zoomScale) + panOffset.height + canvasSize.height / 2
        return CGPoint(x: transformedX, y: transformedY)
    }
    
    private func updateNodePosition(node: GraphNode, offset: CGSize, canvasSize: CGSize) {
        if let index = minimalGraphData.nodes.firstIndex(where: { $0.id == node.id }) {
            let newX = node.position.x + offset.width / zoomScale
            let newY = node.position.y + offset.height / zoomScale
            minimalGraphData.nodes[index].position = CGPoint(x: newX, y: newY)
        }
    }
    
    private func centerGraph() {
        print("🎯 centerGraph() called with \(minimalGraphData.nodes.count) nodes")
        zoomScale = 1.0
        panOffset = .zero
        
        if !minimalGraphData.nodes.isEmpty {
            // Scale positions to fit a reasonable viewport (400x300)
            scaleNodesToFitViewport()
        } else {
            print("🎯 No nodes, panOffset set to zero")
        }
    }
    
    private func scaleNodesToFitViewport() {
        let positions = minimalGraphData.nodes.map { $0.position }
        let minX = positions.map { $0.x }.min() ?? 0
        let maxX = positions.map { $0.x }.max() ?? 0
        let minY = positions.map { $0.y }.min() ?? 0
        let maxY = positions.map { $0.y }.max() ?? 0
        
        print("🎯 Original graph bounds: x=[\(minX), \(maxX)], y=[\(minY), \(maxY)]")
        
        let graphWidth = maxX - minX
        let graphHeight = maxY - minY
        
        // Target viewport size (smaller than canvas to leave margin)
        let targetWidth: CGFloat = 400
        let targetHeight: CGFloat = 300
        
        // Calculate scale factor to fit in target viewport
        let scaleX = graphWidth > 0 ? targetWidth / graphWidth : 1.0
        let scaleY = graphHeight > 0 ? targetHeight / graphHeight : 1.0
        let scale = min(scaleX, scaleY, 1.0) // Don't scale up, only down
        
        print("🎯 Scaling factor: \(scale) (target: \(targetWidth)x\(targetHeight))")
        
        // Scale and center all nodes
        let graphCenterX = (minX + maxX) / 2
        let graphCenterY = (minY + maxY) / 2
        
        for index in minimalGraphData.nodes.indices {
            let node = minimalGraphData.nodes[index]
            
            // Translate to origin, scale, then center around zero
            let scaledX = (node.position.x - graphCenterX) * scale
            let scaledY = (node.position.y - graphCenterY) * scale
            
            minimalGraphData.nodes[index].position = CGPoint(x: scaledX, y: scaledY)
        }
        
        // Debug: Show new bounds
        let newPositions = minimalGraphData.nodes.map { $0.position }
        let newMinX = newPositions.map { $0.x }.min() ?? 0
        let newMaxX = newPositions.map { $0.x }.max() ?? 0
        let newMinY = newPositions.map { $0.y }.min() ?? 0
        let newMaxY = newPositions.map { $0.y }.max() ?? 0
        
        print("🎯 Scaled graph bounds: x=[\(newMinX), \(newMaxX)], y=[\(newMinY), \(newMaxY)]")
        
        // Show first few scaled positions
        let firstThreeNodes = minimalGraphData.nodes.prefix(3)
        for (index, node) in firstThreeNodes.enumerated() {
            print("🎯 Scaled Node \(index): '\(node.label)' at (\(node.position.x), \(node.position.y))")
        }
    }
    
    private func applyNodeSpacing() {
        // Adjust node positions based on spacing multiplier
        guard !minimalGraphData.nodes.isEmpty else { return }
        
        let centerX = minimalGraphData.nodes.map { $0.position.x }.reduce(0, +) / CGFloat(minimalGraphData.nodes.count)
        let centerY = minimalGraphData.nodes.map { $0.position.y }.reduce(0, +) / CGFloat(minimalGraphData.nodes.count)
        
        for index in minimalGraphData.nodes.indices {
            let node = minimalGraphData.nodes[index]
            let offsetX = (node.position.x - centerX) * CGFloat(nodeSpacing)
            let offsetY = (node.position.y - centerY) * CGFloat(nodeSpacing)
            
            minimalGraphData.nodes[index].position = CGPoint(
                x: centerX + offsetX,
                y: centerY + offsetY
            )
        }
    }
    
    private func nodeConnections(_ node: GraphNode) -> Int {
        return minimalGraphData.edges.filter { edge in
            edge.sourceId == node.id || edge.targetId == node.id
        }.count
    }
    
    private func binding(for node: GraphNode) -> Binding<GraphNode> {
        guard let index = minimalGraphData.nodes.firstIndex(where: { $0.id == node.id }) else {
            return .constant(node)
        }
        return $minimalGraphData.nodes[index]
    }
    
    private func initializeNodePositions() {
        print("🔍 initializeNodePositions called with \(minimalGraphData.nodes.count) nodes")
        
        // Check if nodes need position initialization
        let nodesNeedPositioning = minimalGraphData.nodes.allSatisfy { node in
            node.position.x == 0 && node.position.y == 0
        }
        
        print("🔍 Nodes need positioning: \(nodesNeedPositioning)")
        
        guard nodesNeedPositioning && !minimalGraphData.nodes.isEmpty else { 
            print("🔍 Skipping position initialization: nodesNeedPositioning=\(nodesNeedPositioning), isEmpty=\(minimalGraphData.nodes.isEmpty)")
            return 
        }
        
        print("🎯 Initializing node positions for \(minimalGraphData.nodes.count) nodes")
        
        // Generate positions using a force-directed layout
        generateForceDirectedLayout()
        
        // Debug: Check positions after generation
        let firstThreeNodes = minimalGraphData.nodes.prefix(3)
        for (index, node) in firstThreeNodes.enumerated() {
            print("🎯 After positioning - Node \(index): '\(node.label)' at (\(node.position.x), \(node.position.y))")
        }
        
        print("✅ Node positions initialized")
    }
    
    private func generateForceDirectedLayout() {
        let nodeCount = minimalGraphData.nodes.count
        guard nodeCount > 0 else { 
            print("❌ generateForceDirectedLayout: No nodes to position")
            return 
        }
        
        print("🎯 generateForceDirectedLayout: Positioning \(nodeCount) nodes")
        
        // Canvas dimensions for positioning
        let canvasWidth: CGFloat = 800
        let canvasHeight: CGFloat = 600
        let centerX = canvasWidth / 2
        let centerY = canvasHeight / 2
        
        print("🎯 Canvas dimensions: \(canvasWidth) x \(canvasHeight), center: (\(centerX), \(centerY))")
        
        // For small graphs, use a simple circular layout
        if nodeCount <= 20 {
            print("🎯 Using circular layout for \(nodeCount) nodes")
            generateCircularLayout(centerX: centerX, centerY: centerY, radius: min(canvasWidth, canvasHeight) * 0.3)
            return
        }
        
        print("🎯 Using force-directed layout for \(nodeCount) nodes")
        
        // For larger graphs, use a force-directed approach
        let iterations = 50
        let springLength: CGFloat = 100
        let springStrength: CGFloat = 0.1
        let repulsionForce: CGFloat = 1000
        let damping: CGFloat = 0.9
        
        // Initialize random positions
        for index in minimalGraphData.nodes.indices {
            let angle = Double.random(in: 0...(2 * Double.pi))
            let radius = Double.random(in: 50...200)
            
            minimalGraphData.nodes[index].position = CGPoint(
                x: centerX + CGFloat(cos(angle) * radius),
                y: centerY + CGFloat(sin(angle) * radius)
            )
        }
        
        // Run force-directed layout iterations
        for _ in 0..<iterations {
            var forces: [CGPoint] = Array(repeating: .zero, count: nodeCount)
            
            // Calculate repulsion forces between all node pairs
            for i in 0..<nodeCount {
                for j in (i+1)..<nodeCount {
                    let node1Pos = minimalGraphData.nodes[i].position
                    let node2Pos = minimalGraphData.nodes[j].position
                    
                    let dx = node2Pos.x - node1Pos.x
                    let dy = node2Pos.y - node1Pos.y
                    let distance = sqrt(dx*dx + dy*dy)
                    
                    if distance > 0 {
                        let force = repulsionForce / (distance * distance)
                        let fx = (dx / distance) * force
                        let fy = (dy / distance) * force
                        
                        forces[i].x -= fx
                        forces[i].y -= fy
                        forces[j].x += fx
                        forces[j].y += fy
                    }
                }
            }
            
            // Calculate attraction forces for connected nodes
            for edge in minimalGraphData.edges {
                guard let sourceIndex = minimalGraphData.nodes.firstIndex(where: { $0.id == edge.sourceId }),
                      let targetIndex = minimalGraphData.nodes.firstIndex(where: { $0.id == edge.targetId }) else {
                    continue
                }
                
                let sourcePos = minimalGraphData.nodes[sourceIndex].position
                let targetPos = minimalGraphData.nodes[targetIndex].position
                
                let dx = targetPos.x - sourcePos.x
                let dy = targetPos.y - sourcePos.y
                let distance = sqrt(dx*dx + dy*dy)
                
                if distance > 0 {
                    let force = springStrength * (distance - springLength)
                    let fx = (dx / distance) * force
                    let fy = (dy / distance) * force
                    
                    forces[sourceIndex].x += fx
                    forces[sourceIndex].y += fy
                    forces[targetIndex].x -= fx
                    forces[targetIndex].y -= fy
                }
            }
            
            // Apply forces with damping
            for index in minimalGraphData.nodes.indices {
                let newX = minimalGraphData.nodes[index].position.x + forces[index].x * damping
                let newY = minimalGraphData.nodes[index].position.y + forces[index].y * damping
                
                // Keep nodes within canvas bounds
                let clampedX = max(-canvasWidth/2, min(canvasWidth*1.5, newX))
                let clampedY = max(-canvasHeight/2, min(canvasHeight*1.5, newY))
                
                minimalGraphData.nodes[index].position = CGPoint(x: clampedX, y: clampedY)
            }
        }
    }
    
    private func generateCircularLayout(centerX: CGFloat, centerY: CGFloat, radius: CGFloat) {
        print("🔄 generateCircularLayout: center=(\(centerX), \(centerY)), radius=\(radius), nodes=\(minimalGraphData.nodes.count)")
        
        let nodeCount = minimalGraphData.nodes.count
        
        for (index, _) in minimalGraphData.nodes.enumerated() {
            let angle = 2 * Double.pi * Double(index) / Double(nodeCount)
            let x = centerX + radius * CGFloat(cos(angle))
            let y = centerY + radius * CGFloat(sin(angle))
            
            minimalGraphData.nodes[index].position = CGPoint(x: x, y: y)
            
            // Debug first few positions
            if index < 3 {
                print("🔄 Circular position \(index): node at (\(x), \(y)) angle=\(angle)")
            }
        }
        
        print("✅ Circular layout complete")
    }
}

// MARK: - Supporting Views

struct ControlSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            content
        }
        .padding()
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(8)
    }
}

struct ControlSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let formatter: (Double) -> String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                
                Spacer()
                
                Text(formatter(value))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            
            Slider(value: $value, in: range, step: step)
                .accentColor(.blue)
        }
    }
}

struct AnalysisStatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }
} 