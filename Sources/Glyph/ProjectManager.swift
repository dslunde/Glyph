import Foundation
import SwiftUI
import Combine

/// Main ViewModel for managing projects and coordinating between UI and services
@MainActor
class ProjectManager: ObservableObject {
    @Published var projects: [Project] = []
    @Published var selectedProject: Project?
    @Published var isOnlineMode = true
    @Published var showingCreateProject = false
    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0.0
    @Published var insights: [String] = []
    
    // Services
    let pythonService = PythonGraphService()
    private let persistenceService = PersistenceService()
    
    // Error handling
    @Published var errorMessage: String = ""
    @Published var showingError = false
    
    private var cancellables: Set<AnyCancellable> = []
    
    init() {
        setupBindings()
        loadProjects()
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
    
    func createProject(name: String, description: String = "", topic: String = "",
                      depth: ProjectDepth = .moderate, sourcePreferences: [SourcePreference] = [.reliable],
                      filePaths: [String] = [], urls: [String] = [],
                      hypotheses: String = "", controversialAspects: String = "",
                      sensitivityLevel: SensitivityLevel = .medium) {
        let newProject = Project(
            name: name,
            description: description,
            topic: topic,
            depth: depth,
            sourcePreferences: sourcePreferences,
            filePaths: filePaths,
            urls: urls,
            hypotheses: hypotheses,
            controversialAspects: controversialAspects,
            sensitivityLevel: sensitivityLevel,
            isOnline: isOnlineMode
        )
        projects.append(newProject)
        selectedProject = newProject
        saveProjects()
        
        // Initialize with sample graph data
        Task {
            await initializeSampleGraph(for: newProject)
        }
    }
    
    func createProjectWithCustomLearningPlan(name: String, description: String = "", topic: String = "",
                      depth: ProjectDepth = .moderate, sourcePreferences: [SourcePreference] = [.reliable],
                      filePaths: [String] = [], urls: [String] = [],
                      hypotheses: String = "", controversialAspects: String = "",
                      sensitivityLevel: SensitivityLevel = .medium, learningPlan: String) {
        var newProject = Project(
            name: name,
            description: description,
            topic: topic,
            depth: depth,
            sourcePreferences: sourcePreferences,
            filePaths: filePaths,
            urls: urls,
            hypotheses: hypotheses,
            controversialAspects: controversialAspects,
            sensitivityLevel: sensitivityLevel,
            isOnline: isOnlineMode
        )
        
        // Override the default learning plan with the custom one
        newProject.learningPlan = learningPlan
        
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
    
    @MainActor
    private func initializeSampleGraph(for project: Project) async {
        var graphData = GraphData()
        
        // Create Spider-Man themed mock nodes (about 10 nodes) with positive coordinates
        let nodes = [
            GraphNode(label: "Spider-Man", type: .entity, properties: ["alias": "Peter Parker", "universe": "616"], position: CGPoint(x: 300, y: 200)),
            GraphNode(label: "Spider Powers", type: .concept, properties: ["type": "superhuman abilities"], position: CGPoint(x: 150, y: 100)),
            GraphNode(label: "Web-Slinging", type: .concept, properties: ["skill": "signature ability"], position: CGPoint(x: 100, y: 250)),
            GraphNode(label: "Great Responsibility", type: .insight, properties: ["quote": "with great power"], position: CGPoint(x: 400, y: 50)),
            GraphNode(label: "Daily Bugle", type: .entity, properties: ["type": "newspaper", "boss": "J. Jonah Jameson"], position: CGPoint(x: 500, y: 200)),
            GraphNode(label: "Green Goblin", type: .entity, properties: ["real_name": "Norman Osborn", "relation": "arch-nemesis"], position: CGPoint(x: 450, y: 350)),
            GraphNode(label: "Uncle Ben", type: .entity, properties: ["status": "deceased", "role": "mentor"], position: CGPoint(x: 200, y: 400)),
            GraphNode(label: "Queens NYC", type: .entity, properties: ["type": "location", "home": "neighborhood"], position: CGPoint(x: 50, y: 150)),
            GraphNode(label: "Spider Sense", type: .concept, properties: ["type": "precognitive ability"], position: CGPoint(x: 350, y: 50)),
            GraphNode(label: "Amazing Fantasy #15", type: .document, properties: ["year": "1962", "significance": "first appearance"], position: CGPoint(x: 550, y: 100))
        ]
        
        graphData.nodes = nodes
        
        // Create edges connecting the Spider-Man concepts
        let edges = [
            GraphEdge(sourceId: nodes[0].id, targetId: nodes[1].id, label: "possesses", weight: 0.9),
            GraphEdge(sourceId: nodes[1].id, targetId: nodes[2].id, label: "enables", weight: 0.8),
            GraphEdge(sourceId: nodes[1].id, targetId: nodes[8].id, label: "includes", weight: 0.7),
            GraphEdge(sourceId: nodes[0].id, targetId: nodes[3].id, label: "learns", weight: 1.0),
            GraphEdge(sourceId: nodes[6].id, targetId: nodes[3].id, label: "teaches", weight: 0.9),
            GraphEdge(sourceId: nodes[0].id, targetId: nodes[4].id, label: "works_for", weight: 0.6),
            GraphEdge(sourceId: nodes[0].id, targetId: nodes[5].id, label: "fights", weight: 0.8),
            GraphEdge(sourceId: nodes[0].id, targetId: nodes[7].id, label: "lives_in", weight: 0.7),
            GraphEdge(sourceId: nodes[9].id, targetId: nodes[0].id, label: "introduces", weight: 1.0),
            GraphEdge(sourceId: nodes[6].id, targetId: nodes[0].id, label: "mentors", weight: 0.9),
            GraphEdge(sourceId: nodes[5].id, targetId: nodes[6].id, label: "causes_death", weight: 0.8),
            GraphEdge(sourceId: nodes[4].id, targetId: nodes[0].id, label: "criticizes", weight: 0.5)
        ]
        graphData.edges = edges
        
        // Update metadata
        graphData.metadata.totalNodes = graphData.nodes.count
        graphData.metadata.totalEdges = graphData.edges.count
        graphData.metadata.algorithms = ["centrality", "embedding"]
        graphData.metadata.lastAnalysis = Date()
        
        // Update project
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index].graphData = graphData
            projects[index].updateLastModified()
            
            // Update selected project if it's the one we just updated
            if selectedProject?.id == project.id {
                selectedProject = projects[index]
            }
            
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