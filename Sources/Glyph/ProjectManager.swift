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
    @Published var showingKnowledgeGraphProgress = false
    @Published var knowledgeGraphSources: [[String: Any]] = []
    
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
        
        print("✅ Created new project: \(name) with empty state")
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
        
        print("✅ Created new project with custom learning plan: \(name)")
    }
    
    func createProjectWithCustomLearningPlanAndSources(name: String, description: String = "", topic: String = "",
                      depth: ProjectDepth = .moderate, sourcePreferences: [SourcePreference] = [.reliable],
                      filePaths: [String] = [], urls: [String] = [],
                      hypotheses: String = "", controversialAspects: String = "",
                      sensitivityLevel: SensitivityLevel = .medium, learningPlan: String, sources: [[String: Any]]) {
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
        
        // Convert and store sources
        newProject.sources = sources.map { sourceDict in
            ProcessedSource(
                title: sourceDict["title"] as? String ?? "Unknown Title",
                content: sourceDict["content"] as? String ?? "",
                url: sourceDict["url"] as? String ?? "",
                score: sourceDict["score"] as? Double ?? 0.8,
                publishedDate: sourceDict["published_date"] as? String ?? "",
                query: sourceDict["query"] as? String ?? "",
                reliabilityScore: sourceDict["reliability_score"] as? Int ?? 80,
                sourceType: sourceDict["source_type"] as? String ?? "web",
                wordCount: sourceDict["word_count"] as? Int ?? 0
            )
        }
        
        print("🔍 DEBUG: About to store \(sources.count) sources in new project")
        print("🔍 DEBUG: First source title: \(sources.first?["title"] as? String ?? "none")")
        
        projects.append(newProject)
        selectedProject = newProject
        saveProjects()
        
        print("✅ Created new project with custom learning plan and \(sources.count) sources: \(name)")
        print("🔍 DEBUG: Stored project sources: \(newProject.sources?.count ?? 0)")
        if let firstSource = newProject.sources?.first {
            print("🔍 DEBUG: First stored source: \(firstSource.title)")
        }
    }
    
    func deleteProject(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        if selectedProject?.id == project.id {
            selectedProject = projects.first
        }
        saveProjects()
    }
    
    func renameProject(_ project: Project, to newName: String) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        
        projects[index].name = newName
        projects[index].updateLastModified()
        
        // Update selected project if it's the one we just renamed
        if selectedProject?.id == project.id {
            selectedProject = projects[index]
        }
        
        saveProjects()
    }
    
    func selectProject(_ project: Project) {
        selectedProject = project
    }
    
    // MARK: - Knowledge Graph Generation
    
    /// Start knowledge graph generation from source collection results
    func startKnowledgeGraphGeneration(from sources: [[String: Any]], for project: Project) {
        knowledgeGraphSources = sources
        selectedProject = project
        showingKnowledgeGraphProgress = true
    }
    
    /// Complete knowledge graph generation and update the project
    func completeKnowledgeGraphGeneration(with graphData: GraphData) {
        guard let project = selectedProject else { 
            print("❌ DEBUG: No selected project for graph completion")
            return 
        }
        
        print("🔍 DEBUG: Completing knowledge graph generation for project: \(project.name)")
        print("🔍 DEBUG: Received graph data: \(graphData.nodes.count) nodes, \(graphData.edges.count) edges")
        print("🔍 DEBUG: Minimal subgraph: \(graphData.minimalSubgraph?.nodes.count ?? 0) nodes")
        
        // Update the project with the generated graph data
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index].graphData = graphData
            projects[index].updateLastModified()
            
            // Update selected project
            selectedProject = projects[index]
            
            print("🔍 DEBUG: Updated project at index \(index)")
            print("🔍 DEBUG: Project now has \(projects[index].graphData?.nodes.count ?? 0) nodes")
            print("🔍 DEBUG: Project sources count: \(projects[index].sources?.count ?? 0)")
            
            // Save changes
            saveProjects()
            
            print("✅ Knowledge graph saved to project: \(graphData.nodes.count) nodes, \(graphData.edges.count) edges")
            if let minimalSubgraph = graphData.minimalSubgraph {
                print("   🎯 Minimal subgraph: \(minimalSubgraph.nodes.count) nodes, \(minimalSubgraph.edges.count) edges")
            }
        } else {
            print("❌ DEBUG: Could not find project index for project \(project.id)")
        }
        
        // Hide the progress view
        showingKnowledgeGraphProgress = false
    }
    
    /// Cancel knowledge graph generation
    func cancelKnowledgeGraphGeneration() {
        showingKnowledgeGraphProgress = false
        knowledgeGraphSources = []
    }
    
    // MARK: - Analysis Report Management
    
    func saveAnalysisReport(_ report: AnalysisReport, for project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        
        projects[index].analysisReport = report
        projects[index].updateLastModified()
        
        // Update selected project if it's the one we just updated
        if selectedProject?.id == project.id {
            selectedProject = projects[index]
        }
        
        saveProjects()
        print("✅ Analysis report saved for project: \(project.name)")
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