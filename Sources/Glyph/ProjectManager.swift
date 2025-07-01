import Foundation
import SwiftUI
import Combine

/// Main ViewModel for managing projects and coordinating between UI and services
class ProjectManager: ObservableObject {
    @Published var projects: [Project] = []
    @Published var selectedProject: Project?
    @Published var isOnlineMode = true
    @Published var showingCreateProject = false
    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0.0
    @Published var insights: [String] = []
    
    // Services
    private let pythonService = PythonGraphService()
    private let persistenceService = PersistenceService()
    
    // Error handling
    @Published var errorMessage: String?
    @Published var showingError = false
    
    private var cancellables: Set<AnyCancellable> = []
    
    init() {
        setupBindings()
        loadProjects()
        createSampleProject()
    }
    
    private func setupBindings() {
        // Bind Python service online mode to our online mode
        pythonService.$isOnlineMode
            .receive(on: DispatchQueue.main)
            .assign(to: \.isOnlineMode, on: self)
            .store(in: &cancellables)
        
        // Handle Python service errors
        pythonService.$lastError
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.showError(error)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Project Management
    
    func createProject(name: String, description: String = "") {
        let newProject = Project(name: name, description: description, isOnline: isOnlineMode)
        projects.append(newProject)
        selectedProject = newProject
        saveProjects()
        
        // Initialize with sample graph data
        Task {
            await initializeSampleGraph(for: newProject)
        }
    }
    
    func deleteProject(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        if selectedProject?.id == project.id {
            selectedProject = projects.first
        }
        saveProjects()
    }
    
    func selectProject(_ project: Project) {
        selectedProject = project
    }
    
    // MARK: - Graph Analysis
    
    @MainActor
    func analyzeCurrentProject() async {
        guard let project = selectedProject,
              let graphData = project.graphData else {
            showError("No project or graph data available for analysis")
            return
        }
        
        isAnalyzing = true
        analysisProgress = 0.0
        insights = []
        
        do {
            // Prepare data for analysis
            analysisProgress = 0.2
            _ = pythonService.prepareDataForAI(graphData: graphData)
            
            // Simulate analysis steps
            analysisProgress = 0.4
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            // Generate insights based on graph structure
            analysisProgress = 0.6
            let nodeCount = graphData.nodes.count
            let edgeCount = graphData.edges.count
            let density = edgeCount > 0 ? Double(edgeCount) / Double(nodeCount * (nodeCount - 1) / 2) : 0.0
            
            analysisProgress = 0.8
            
            // Create insights
            var newInsights: [String] = []
            
            if nodeCount > 0 {
                newInsights.append("📊 Graph contains \(nodeCount) nodes and \(edgeCount) edges")
            }
            
            if density > 0.5 {
                newInsights.append("🔗 High connectivity detected - dense network structure")
            } else if density > 0.2 {
                newInsights.append("⚖️ Moderate connectivity - balanced network structure")
            } else {
                newInsights.append("🌐 Sparse network - opportunities for new connections")
            }
            
            let conceptNodes = graphData.nodes.filter { $0.type == .concept }.count
            let entityNodes = graphData.nodes.filter { $0.type == .entity }.count
            
            if conceptNodes > entityNodes {
                newInsights.append("💡 Concept-heavy graph - rich in abstract ideas")
            } else if entityNodes > conceptNodes {
                newInsights.append("🏷️ Entity-focused graph - concrete and specific")
            }
            
            if isOnlineMode {
                newInsights.append("🌐 Online mode: Real-time AI insights available")
            } else {
                newInsights.append("📱 Offline mode: Local analysis complete")
            }
            
            analysisProgress = 1.0
            insights = newInsights
            
        } catch {
            showError("Analysis failed: \(error.localizedDescription)")
        }
        
        isAnalyzing = false
    }
    
    // MARK: - Sample Data Creation
    
    private func createSampleProject() {
        if projects.isEmpty {
            let sampleProject = Project(
                name: "Knowledge Discovery",
                description: "Exploring connections between concepts and insights",
                isOnline: true
            )
            projects.append(sampleProject)
            selectedProject = sampleProject
            
            Task {
                await initializeSampleGraph(for: sampleProject)
            }
        }
    }
    
    @MainActor
    private func initializeSampleGraph(for project: Project) async {
        var graphData = GraphData()
        
        // Create sample nodes
        let nodes = [
            GraphNode(label: "Machine Learning", type: .concept, properties: ["domain": "AI"], position: CGPoint(x: 100, y: 100)),
            GraphNode(label: "Neural Networks", type: .concept, properties: ["complexity": "high"], position: CGPoint(x: 200, y: 150)),
            GraphNode(label: "Data Analysis", type: .concept, properties: ["domain": "Analytics"], position: CGPoint(x: 150, y: 200)),
            GraphNode(label: "Python", type: .entity, properties: ["type": "language"], position: CGPoint(x: 250, y: 100)),
            GraphNode(label: "Research Paper", type: .document, properties: ["source": "academic"], position: CGPoint(x: 300, y: 200)),
            GraphNode(label: "Pattern Recognition", type: .insight, properties: ["importance": "high"], position: CGPoint(x: 175, y: 250))
        ]
        
        graphData.nodes = nodes
        
        // Create sample edges
        if nodes.count >= 6 {
            let edges = [
                GraphEdge(sourceId: nodes[0].id, targetId: nodes[1].id, label: "uses", weight: 0.8),
                GraphEdge(sourceId: nodes[1].id, targetId: nodes[3].id, label: "implemented_in", weight: 0.9),
                GraphEdge(sourceId: nodes[0].id, targetId: nodes[2].id, label: "requires", weight: 0.7),
                GraphEdge(sourceId: nodes[2].id, targetId: nodes[5].id, label: "leads_to", weight: 0.6),
                GraphEdge(sourceId: nodes[4].id, targetId: nodes[0].id, label: "describes", weight: 0.8),
                GraphEdge(sourceId: nodes[3].id, targetId: nodes[2].id, label: "enables", weight: 0.5)
            ]
            graphData.edges = edges
        }
        
        // Update metadata
        graphData.metadata.totalNodes = graphData.nodes.count
        graphData.metadata.totalEdges = graphData.edges.count
        graphData.metadata.algorithms = ["centrality", "embedding"]
        graphData.metadata.lastAnalysis = Date()
        
        // Update project
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index].graphData = graphData
            saveProjects()
        }
    }
    
    // MARK: - Online/Offline Mode
    
    func toggleOnlineMode() {
        pythonService.toggleOnlineMode()
        isOnlineMode.toggle()
    }
    
    // MARK: - Persistence
    
    private func loadProjects() {
        projects = persistenceService.loadProjects()
    }
    
    private func saveProjects() {
        persistenceService.saveProjects(projects)
    }
    
    // MARK: - Error Handling
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
    
    // MARK: - Python Service Info
    
    func getPythonServiceStatus() -> [String: Bool] {
        return pythonService.checkPythonDependencies()
    }
    
    var isPythonInitialized: Bool {
        pythonService.isInitialized
    }
} 