import Foundation

// MARK: - Analysis Report

struct AnalysisReport: Codable, Identifiable {
    let id: UUID
    let projectId: UUID
    let generatedAt: Date
    let topic: String
    let knowledgeGaps: [KnowledgeGap]
    let counterintuitiveInsights: [CounterintuitiveInsight]
    let uncommonInsights: [UncommonInsight]
    let summary: String
    let recommendations: [String]
    let methodology: String
    let confidence: Double
    
    init(
        id: UUID = UUID(),
        projectId: UUID,
        generatedAt: Date = Date(),
        topic: String,
        knowledgeGaps: [KnowledgeGap] = [],
        counterintuitiveInsights: [CounterintuitiveInsight] = [],
        uncommonInsights: [UncommonInsight] = [],
        summary: String = "",
        recommendations: [String] = [],
        methodology: String = "",
        confidence: Double = 0.8
    ) {
        self.id = id
        self.projectId = projectId
        self.generatedAt = generatedAt
        self.topic = topic
        self.knowledgeGaps = knowledgeGaps
        self.counterintuitiveInsights = counterintuitiveInsights
        self.uncommonInsights = uncommonInsights
        self.summary = summary
        self.recommendations = recommendations
        self.methodology = methodology
        self.confidence = confidence
    }
}

// MARK: - Knowledge Gap

struct KnowledgeGap: Codable, Identifiable {
    let id: UUID
    let type: String
    let description: String
    let severity: String // "high", "medium", "low"
    let suggestedSources: [String]
    let relatedConcepts: [String]
    
    init(
        id: UUID = UUID(),
        type: String,
        description: String,
        severity: String = "medium",
        suggestedSources: [String] = [],
        relatedConcepts: [String] = []
    ) {
        self.id = id
        self.type = type
        self.description = description
        self.severity = severity
        self.suggestedSources = suggestedSources
        self.relatedConcepts = relatedConcepts
    }
}

// MARK: - Counterintuitive Insight

struct CounterintuitiveInsight: Codable, Identifiable {
    let id: UUID
    let insight: String
    let explanation: String
    let confidence: Double
    let supportingEvidence: [String]
    let contradictedBeliefs: [String]
    
    init(
        id: UUID = UUID(),
        insight: String,
        explanation: String,
        confidence: Double = 0.7,
        supportingEvidence: [String] = [],
        contradictedBeliefs: [String] = []
    ) {
        self.id = id
        self.insight = insight
        self.explanation = explanation
        self.confidence = confidence
        self.supportingEvidence = supportingEvidence
        self.contradictedBeliefs = contradictedBeliefs
    }
}

// MARK: - Uncommon Insight

struct UncommonInsight: Codable, Identifiable {
    let id: UUID
    let conceptA: String
    let conceptB: String
    let relationship: String
    let strength: Double // 0.0 to 1.0
    let novelty: Double // 0.0 to 1.0
    let explanation: String
    
    init(
        id: UUID = UUID(),
        conceptA: String,
        conceptB: String,
        relationship: String,
        strength: Double = 0.5,
        novelty: Double = 0.5,
        explanation: String = ""
    ) {
        self.id = id
        self.conceptA = conceptA
        self.conceptB = conceptB
        self.relationship = relationship
        self.strength = strength
        self.novelty = novelty
        self.explanation = explanation
    }
}

// MARK: - Analysis Report Extensions

extension AnalysisReport {
    var totalInsights: Int {
        return knowledgeGaps.count + counterintuitiveInsights.count + uncommonInsights.count
    }
    
    var hasContent: Bool {
        return totalInsights > 0 || !summary.isEmpty || !recommendations.isEmpty
    }
    
    var formattedGeneratedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: generatedAt)
    }
    
    var confidenceLevel: String {
        if confidence >= 0.8 { return "High" }
        else if confidence >= 0.6 { return "Medium" }
        else { return "Low" }
    }
    
    var confidenceColor: String {
        if confidence >= 0.8 { return "green" }
        else if confidence >= 0.6 { return "orange" }
        else { return "red" }
    }
}

// MARK: - Mock Data for Testing

extension AnalysisReport {
    static var mockReport: AnalysisReport {
        return AnalysisReport(
            projectId: UUID(),
            topic: "Artificial Intelligence and Machine Learning",
            knowledgeGaps: [
                KnowledgeGap(
                    type: "Conceptual Gap",
                    description: "The relationship between neural networks and deep learning architectures is not fully established in your knowledge graph.",
                    severity: "high",
                    suggestedSources: [
                        "Deep Learning textbook by Ian Goodfellow",
                        "Neural Networks: A Comprehensive Foundation"
                    ],
                    relatedConcepts: ["Neural Networks", "Deep Learning", "Backpropagation"]
                ),
                KnowledgeGap(
                    type: "Implementation Gap",
                    description: "Missing connections between theoretical concepts and practical applications in computer vision.",
                    severity: "medium",
                    suggestedSources: [
                        "Computer Vision: Algorithms and Applications",
                        "OpenCV documentation"
                    ],
                    relatedConcepts: ["Computer Vision", "Image Processing", "Pattern Recognition"]
                )
            ],
            counterintuitiveInsights: [
                CounterintuitiveInsight(
                    insight: "Overfitting can sometimes improve model performance in specific domains",
                    explanation: "While overfitting is generally considered harmful, in certain specialized domains with limited data variation, models that appear to overfit on training data can actually generalize better to similar real-world scenarios.",
                    confidence: 0.75,
                    supportingEvidence: [
                        "Medical imaging studies with limited pathology variation",
                        "Domain-specific language models for technical jargon"
                    ],
                    contradictedBeliefs: [
                        "Overfitting always leads to poor generalization",
                        "Complex models are always worse than simple ones"
                    ]
                )
            ],
            uncommonInsights: [
                UncommonInsight(
                    conceptA: "Quantum Computing",
                    conceptB: "Natural Language Processing",
                    relationship: "optimization enhancement",
                    strength: 0.7,
                    novelty: 0.9,
                    explanation: "Quantum algorithms could potentially solve certain NLP optimization problems exponentially faster than classical computers."
                ),
                UncommonInsight(
                    conceptA: "Blockchain Technology",
                    conceptB: "Machine Learning Model Verification",
                    relationship: "integrity assurance",
                    strength: 0.6,
                    novelty: 0.8,
                    explanation: "Blockchain could provide immutable records of model training processes and data lineage for AI transparency."
                )
            ],
            summary: "This analysis reveals significant gaps in the practical implementation connections within your AI knowledge graph, while identifying several counterintuitive relationships that challenge conventional thinking about machine learning optimization and generalization.",
            recommendations: [
                "Focus on building stronger connections between theoretical concepts and their practical implementations",
                "Explore interdisciplinary connections, particularly between emerging technologies like quantum computing and established AI fields",
                "Consider adding more case studies and real-world examples to strengthen the knowledge graph's practical utility",
                "Investigate the counterintuitive insights identified, as they may represent areas of competitive advantage or novel research directions"
            ],
            methodology: "This analysis used graph centrality measures, clustering algorithms, and semantic similarity analysis to identify knowledge gaps, unexpected connections, and areas where conventional wisdom might be challenged. The confidence score reflects the statistical significance of the patterns identified.",
            confidence: 0.82
        )
    }
} 