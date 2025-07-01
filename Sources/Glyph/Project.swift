import Foundation
import SwiftUI

// MARK: - Project Model

/// Main project data structure
struct Project: Identifiable, Codable, Hashable {
    let id = UUID()
    var name: String
    var description: String
    var topic: String
    var depth: ProjectDepth
    var sourcePreferences: [SourcePreference]
    var filePaths: [String]  // File and folder paths for analysis
    var urls: [String]       // URLs for analysis
    var hypotheses: String
    var controversialAspects: String
    var sensitivityLevel: SensitivityLevel
    var createdAt: Date
    var lastModified: Date
    var isOnline: Bool
    var graphData: GraphData?
    var learningPlan: String
    
    init(name: String, description: String = "", topic: String = "", 
         depth: ProjectDepth = .moderate, sourcePreferences: [SourcePreference] = [.reliable],
         filePaths: [String] = [], urls: [String] = [],
         hypotheses: String = "", controversialAspects: String = "", 
         sensitivityLevel: SensitivityLevel = .medium, isOnline: Bool = true) {
        self.name = name
        self.description = description
        self.topic = topic
        self.depth = depth
        self.sourcePreferences = sourcePreferences
        self.filePaths = filePaths
        self.urls = urls
        self.hypotheses = hypotheses
        self.controversialAspects = controversialAspects
        self.sensitivityLevel = sensitivityLevel
        self.createdAt = Date()
        self.lastModified = Date()
        self.isOnline = isOnline
        self.graphData = nil
        
        // Initialize with Lorem Ipsum as specified in PRD
        self.learningPlan = """
        # Learning Plan
        
        ## Overview
        Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
        
        ## Phase 1: Foundation
        Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
        
        ### Key Concepts to Master
        - Lorem ipsum dolor sit amet
        - Consectetur adipiscing elit
        - Sed do eiusmod tempor incididunt
        - Ut labore et dolore magna aliqua
        
        ## Phase 2: Advanced Understanding
        Sed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium doloremque laudantium, totam rem aperiam, eaque ipsa quae ab illo inventore veritatis et quasi architecto beatae vitae dicta sunt explicabo.
        
        ### Learning Objectives
        1. Nemo enim ipsam voluptatem quia voluptas sit aspernatur
        2. Aut odit aut fugit, sed quia consequuntur magni dolores
        3. Eos qui ratione voluptatem sequi nesciunt
        4. Neque porro quisquam est, qui dolorem ipsum
        
        ## Phase 3: Practical Application
        At vero eos et accusamus et iusto odio dignissimos ducimus qui blanditiis praesentium voluptatum deleniti atque corrupti quos dolores et quas molestias excepturi sint occaecati cupiditate non provident.
        
        ## Resources and Further Reading
        - Similique sunt in culpa qui officia deserunt mollitia animi
        - Id est laborum et dolorum fuga
        - Et harum quidem rerum facilis est et expedita distinctio
        - Nam libero tempore, cum soluta nobis est eligendi optio
        """
    }
    
    mutating func updateLastModified() {
        lastModified = Date()
    }
    
    // MARK: - Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Project, rhs: Project) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Project Configuration Enums

/// Project depth level as specified in PRD
enum ProjectDepth: String, CaseIterable, Codable {
    case quick = "quick"
    case moderate = "moderate"
    case comprehensive = "comprehensive"
    
    var displayName: String {
        switch self {
        case .quick:
            return "Quick"
        case .moderate:
            return "Moderate"
        case .comprehensive:
            return "Comprehensive"
        }
    }
    
    var description: String {
        switch self {
        case .quick:
            return "Surface-level overview with key concepts"
        case .moderate:
            return "Balanced depth with detailed connections"
        case .comprehensive:
            return "Deep analysis with extensive relationships"
        }
    }
}

/// Source preference types from PRD
enum SourcePreference: String, CaseIterable, Codable {
    case reliable = "reliable"
    case insider = "insider"
    case outsider = "outsider"
    case unreliable = "unreliable"
    
    var displayName: String {
        switch self {
        case .reliable:
            return "Reliable"
        case .insider:
            return "Insider"
        case .outsider:
            return "Outsider"
        case .unreliable:
            return "Unreliable"
        }
    }
    
    var description: String {
        switch self {
        case .reliable:
            return "Established, peer-reviewed sources"
        case .insider:
            return "Industry or domain expert perspectives"
        case .outsider:
            return "External or alternative viewpoints"
        case .unreliable:
            return "Unverified or controversial sources"
        }
    }
    
    var color: Color {
        switch self {
        case .reliable:
            return .green
        case .insider:
            return .blue
        case .outsider:
            return .orange
        case .unreliable:
            return .red
        }
    }
}

/// Sensitivity level for controversial topics
enum SensitivityLevel: String, CaseIterable, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    
    var displayName: String {
        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        }
    }
    
    var description: String {
        switch self {
        case .low:
            return "Standard sensitivity for finding gaps and contradictions"
        case .medium:
            return "Balanced sensitivity for thorough analysis"
        case .high:
            return "High sensitivity for detecting rare perspectives and subtle insights"
        }
    }
}

// MARK: - Graph Data Models

/// Complete graph data structure
struct GraphData: Codable {
    var nodes: [GraphNode] = []
    var edges: [GraphEdge] = []
    var metadata: GraphMetadata = GraphMetadata()
    
    init() {}
}

/// Individual graph node
struct GraphNode: Identifiable, Codable {
    let id = UUID()
    var label: String
    var type: NodeType
    var properties: [String: String]
    var position: CGPoint
    var isSelected: Bool = false
    
    init(label: String, type: NodeType, properties: [String: String] = [:], position: CGPoint = .zero) {
        self.label = label
        self.type = type
        self.properties = properties
        self.position = position
    }
}

/// Node type enumeration
enum NodeType: String, CaseIterable, Codable {
    case concept = "concept"
    case entity = "entity"
    case document = "document"
    case insight = "insight"
    
    var color: Color {
        switch self {
        case .concept:
            return .blue
        case .entity:
            return .green
        case .document:
            return .orange
        case .insight:
            return .purple
        }
    }
    
    var displayName: String {
        switch self {
        case .concept:
            return "Concept"
        case .entity:
            return "Entity"
        case .document:
            return "Document"
        case .insight:
            return "Insight"
        }
    }
    
    var iconName: String {
        switch self {
        case .concept:
            return "lightbulb"
        case .entity:
            return "cube"
        case .document:
            return "doc.text"
        case .insight:
            return "sparkles"
        }
    }
}

/// Graph edge (connection between nodes)
struct GraphEdge: Identifiable, Codable {
    let id = UUID()
    var sourceId: UUID
    var targetId: UUID
    var label: String
    var weight: Double
    var properties: [String: String]
    
    init(sourceId: UUID, targetId: UUID, label: String = "", weight: Double = 1.0, properties: [String: String] = [:]) {
        self.sourceId = sourceId
        self.targetId = targetId
        self.label = label
        self.weight = weight
        self.properties = properties
    }
}

/// Graph metadata and analysis results
struct GraphMetadata: Codable {
    var totalNodes: Int = 0
    var totalEdges: Int = 0
    var algorithms: [String] = []
    var lastAnalysis: Date?
    var centrality: [String: Double] = [:]
    var embeddings: [String: [Double]] = [:]
    
    init() {}
}

// MARK: - Authentication Models

/// User authentication data
struct UserCredentials: Codable {
    var username: String
    var hashedPassword: String
    var lastLoginTime: Date?
    
    init(username: String, password: String) {
        self.username = username
        self.hashedPassword = Self.hashPassword(password)
        self.lastLoginTime = nil
    }
    
    private static func hashPassword(_ password: String) -> String {
        // Simple hash for demo purposes - in production use proper crypto
        return password.data(using: .utf8)?.base64EncodedString() ?? ""
    }
    
    func verifyPassword(_ password: String) -> Bool {
        return hashedPassword == Self.hashPassword(password)
    }
    
    var isSessionValid: Bool {
        guard let lastLogin = lastLoginTime else { return false }
        // 1 hour timeout as specified in PRD
        return Date().timeIntervalSince(lastLogin) < 3600
    }
    
    mutating func updateLoginTime() {
        lastLoginTime = Date()
    }
}

/// Authentication session manager
@MainActor
class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: String?
    private var credentials: UserCredentials?
    
    private let credentialsKey = "glyph_user_credentials"
    
    init() {
        loadStoredCredentials()
        checkSessionValidity()
    }
    
    func login(username: String, password: String) -> Bool {
        if let stored = credentials, stored.username == username, stored.verifyPassword(password) {
            credentials?.updateLoginTime()
            saveCredentials()
            isAuthenticated = true
            currentUser = username
            return true
        }
        return false
    }
    
    func createAccount(username: String, password: String) -> Bool {
        guard !username.isEmpty, password.count >= 6 else { return false }
        
        credentials = UserCredentials(username: username, password: password)
        credentials?.updateLoginTime()
        saveCredentials()
        isAuthenticated = true
        currentUser = username
        return true
    }
    
    func logout() {
        isAuthenticated = false
        currentUser = nil
    }
    
    private func checkSessionValidity() {
        if let creds = credentials, creds.isSessionValid {
            isAuthenticated = true
            currentUser = creds.username
        } else {
            isAuthenticated = false
            currentUser = nil
        }
    }
    
    private func loadStoredCredentials() {
        guard let data = UserDefaults.standard.data(forKey: credentialsKey),
              let creds = try? JSONDecoder().decode(UserCredentials.self, from: data) else {
            return
        }
        credentials = creds
    }
    
    private func saveCredentials() {
        guard let creds = credentials,
              let data = try? JSONEncoder().encode(creds) else {
            return
        }
        UserDefaults.standard.set(data, forKey: credentialsKey)
    }
} 