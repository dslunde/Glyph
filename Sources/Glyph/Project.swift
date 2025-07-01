import Foundation
import SwiftUI

// MARK: - Project Model

/// Main project data structure
struct Project: Identifiable, Codable, Hashable {
    let id = UUID()
    var name: String
    var description: String
    var createdAt: Date
    var lastModified: Date
    var isOnline: Bool
    var graphData: GraphData?
    
    init(name: String, description: String = "", isOnline: Bool = true) {
        self.name = name
        self.description = description
        self.createdAt = Date()
        self.lastModified = Date()
        self.isOnline = isOnline
        self.graphData = nil
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