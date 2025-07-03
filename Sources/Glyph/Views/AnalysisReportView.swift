import SwiftUI

struct AnalysisReportView: View {
    let report: AnalysisReport
    let onRegenerate: () -> Void
    
    @State private var selectedSection: AnalysisSection = .summary
    @State private var showingExportOptions = false
    
    enum AnalysisSection: String, CaseIterable {
        case summary = "Summary"
        case knowledgeGaps = "Knowledge Gaps"
        case counterintuitive = "Counterintuitive Insights"
        case uncommon = "Uncommon Insights"
        case recommendations = "Recommendations"
        
        var iconName: String {
            switch self {
            case .summary: return "doc.text"
            case .knowledgeGaps: return "exclamationmark.triangle"
            case .counterintuitive: return "lightbulb"
            case .uncommon: return "link"
            case .recommendations: return "checkmark.circle"
            }
        }
        
        var color: Color {
            switch self {
            case .summary: return .blue
            case .knowledgeGaps: return .orange
            case .counterintuitive: return .yellow
            case .uncommon: return .purple
            case .recommendations: return .green
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Analysis Report")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    HStack {
                        Text("Generated for: \(report.topic)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text("Confidence: \(Int(report.confidence * 100))%")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(confidenceColor.opacity(0.2))
                            .foregroundColor(confidenceColor)
                            .cornerRadius(4)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button("Export") {
                        showingExportOptions = true
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Regenerate") {
                        onRegenerate()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            HSplitView {
                // Sidebar with sections
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sections")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top)
                    
                    ForEach(AnalysisSection.allCases, id: \.self) { section in
                        AnalysisSectionButton(
                            section: section,
                            isSelected: selectedSection == section,
                            count: getSectionCount(section)
                        ) {
                            selectedSection = section
                        }
                    }
                    
                    Spacer()
                    
                    // Report metadata
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Report Info")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Generated:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(formatDate(report.generatedAt))
                                    .font(.caption2)
                                    .monospacedDigit()
                            }
                            
                            HStack {
                                Text("Methodology:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Graph Analysis")
                                    .font(.caption2)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom)
                }
                .frame(minWidth: 200, maxWidth: 250)
                .background(Color(nsColor: .controlBackgroundColor))
                
                // Main content
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedSection {
                        case .summary:
                            AnalysisSummaryView(report: report)
                            
                        case .knowledgeGaps:
                            KnowledgeGapsView(gaps: report.knowledgeGaps)
                            
                        case .counterintuitive:
                            CounterintuitiveInsightsView(insights: report.counterintuitiveInsights)
                            
                        case .uncommon:
                            UncommonInsightsView(insights: report.uncommonInsights)
                            
                        case .recommendations:
                            RecommendationsView(recommendations: report.recommendations)
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showingExportOptions) {
            ExportOptionsView(report: report)
        }
    }
    
    private var confidenceColor: Color {
        if report.confidence >= 0.8 { return .green }
        else if report.confidence >= 0.6 { return .orange }
        else { return .red }
    }
    
    private func getSectionCount(_ section: AnalysisSection) -> Int {
        switch section {
        case .summary: return 1
        case .knowledgeGaps: return report.knowledgeGaps.count
        case .counterintuitive: return report.counterintuitiveInsights.count
        case .uncommon: return report.uncommonInsights.count
        case .recommendations: return report.recommendations.count
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Section Button

struct AnalysisSectionButton: View {
    let section: AnalysisReportView.AnalysisSection
    let isSelected: Bool
    let count: Int
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: section.iconName)
                    .foregroundColor(section.color)
                    .frame(width: 16)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    if count > 1 {
                        Text("\(count) items")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(isSelected ? section.color.opacity(0.1) : Color.clear)
            .overlay(
                Rectangle()
                    .fill(isSelected ? section.color : Color.clear)
                    .frame(width: 3)
                    .padding(.trailing, -1),
                alignment: .trailing
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Summary View

struct AnalysisSummaryView: View {
    let report: AnalysisReport
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Executive Summary")
                .font(.title)
                .fontWeight(.bold)
            
            if !report.summary.isEmpty {
                Text(report.summary)
                    .font(.body)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("This analysis examined your knowledge graph to identify key insights and opportunities for deeper understanding.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            }
            
            // Overview cards
            HStack(spacing: 16) {
                OverviewCard(
                    title: "Knowledge Gaps",
                    count: report.knowledgeGaps.count,
                    color: .orange,
                    icon: "exclamationmark.triangle"
                )
                
                OverviewCard(
                    title: "Counterintuitive Insights",
                    count: report.counterintuitiveInsights.count,
                    color: .yellow,
                    icon: "lightbulb"
                )
                
                OverviewCard(
                    title: "Uncommon Connections",
                    count: report.uncommonInsights.count,
                    color: .purple,
                    icon: "link"
                )
            }
            
            if !report.methodology.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Methodology")
                        .font(.headline)
                    
                    Text(report.methodology)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                }
            }
        }
    }
}

struct OverviewCard: View {
    let title: String
    let count: Int
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Knowledge Gaps View

struct KnowledgeGapsView: View {
    let gaps: [KnowledgeGap]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Knowledge Gaps")
                .font(.title)
                .fontWeight(.bold)
            
            if gaps.isEmpty {
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "No Knowledge Gaps Detected",
                    message: "Your knowledge graph appears to be well-connected with minimal gaps."
                )
            } else {
                Text("The following gaps have been identified in your knowledge graph:")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                ForEach(Array(gaps.enumerated()), id: \.offset) { index, gap in
                    KnowledgeGapCard(gap: gap, index: index + 1)
                }
            }
        }
    }
}

struct KnowledgeGapCard: View {
    let gap: KnowledgeGap
    let index: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("#\(index)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2))
                    .foregroundColor(.orange)
                    .cornerRadius(4)
                
                Text(gap.type.capitalized)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                SeverityBadge(severity: gap.severity)
            }
            
            Text(gap.description)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            if !gap.relatedConcepts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Related Concepts:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        ForEach(gap.relatedConcepts.prefix(3), id: \.self) { concept in
                            Text(concept)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                        
                        if gap.relatedConcepts.count > 3 {
                            Text("+\(gap.relatedConcepts.count - 3) more")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            if !gap.suggestedSources.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Suggested Sources:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    ForEach(gap.suggestedSources.prefix(2), id: \.self) { source in
                        Text("• \(source)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

struct SeverityBadge: View {
    let severity: String
    
    private var severityColor: Color {
        switch severity.lowercased() {
        case "high": return .red
        case "medium": return .orange
        case "low": return .yellow
        default: return .gray
        }
    }
    
    var body: some View {
        Text(severity.capitalized)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(severityColor.opacity(0.2))
            .foregroundColor(severityColor)
            .cornerRadius(4)
    }
}

// MARK: - Counterintuitive Insights View

struct CounterintuitiveInsightsView: View {
    let insights: [CounterintuitiveInsight]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Counterintuitive Insights")
                .font(.title)
                .fontWeight(.bold)
            
            if insights.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No Counterintuitive Insights Found",
                    message: "The analysis didn't identify any unexpected or contradictory patterns."
                )
            } else {
                Text("These insights challenge conventional thinking:")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                ForEach(Array(insights.enumerated()), id: \.offset) { index, insight in
                    CounterintuitiveInsightCard(insight: insight, index: index + 1)
                }
            }
        }
    }
}

struct CounterintuitiveInsightCard: View {
    let insight: CounterintuitiveInsight
    let index: Int
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("#\(index)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.yellow.opacity(0.2))
                    .foregroundColor(.orange)
                    .cornerRadius(4)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(insight.insight)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack {
                        Text("Confidence: \(Int(insight.confidence * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                }
                
                Spacer()
                
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(insight.explanation)
                        .font(.body)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if !insight.supportingEvidence.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Supporting Evidence:")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            ForEach(insight.supportingEvidence, id: \.self) { evidence in
                                Text("• \(evidence)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    if !insight.contradictedBeliefs.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Challenges:")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            ForEach(insight.contradictedBeliefs, id: \.self) { belief in
                                Text("• \(belief)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Uncommon Insights View

struct UncommonInsightsView: View {
    let insights: [UncommonInsight]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Uncommon Insights")
                .font(.title)
                .fontWeight(.bold)
            
            if insights.isEmpty {
                EmptyStateView(
                    icon: "link",
                    title: "No Uncommon Connections Found",
                    message: "The analysis didn't identify any unexpected relationships between distant concepts."
                )
            } else {
                Text("These connections reveal unexpected relationships:")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                ForEach(Array(insights.enumerated()), id: \.offset) { index, insight in
                    UncommonInsightCard(insight: insight, index: index + 1)
                }
            }
        }
    }
}

struct UncommonInsightCard: View {
    let insight: UncommonInsight
    let index: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("#\(index)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.2))
                    .foregroundColor(.purple)
                    .cornerRadius(4)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Text("Strength: \(Int(insight.strength * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("Novelty: \(Int(insight.novelty * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.conceptA)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                }
                
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack {
                    Text(insight.relationship)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.purple)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(insight.conceptB)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.1))
                        .foregroundColor(.green)
                        .cornerRadius(8)
                }
            }
            
            if !insight.explanation.isEmpty {
                Text(insight.explanation)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Recommendations View

struct RecommendationsView: View {
    let recommendations: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Recommendations")
                .font(.title)
                .fontWeight(.bold)
            
            if recommendations.isEmpty {
                EmptyStateView(
                    icon: "checkmark.circle",
                    title: "No Specific Recommendations",
                    message: "Your knowledge graph appears to be well-structured."
                )
            } else {
                Text("Based on the analysis, here are our recommendations:")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                ForEach(Array(recommendations.enumerated()), id: \.offset) { index, recommendation in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                        
                        Text(recommendation)
                            .font(.body)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                }
            }
        }
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.headline)
                .fontWeight(.medium)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - Export Options View

struct ExportOptionsView: View {
    let report: AnalysisReport
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Export Analysis Report")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(spacing: 12) {
                ExportOptionButton(
                    icon: "doc.text",
                    title: "Markdown",
                    description: "Export as Markdown file"
                ) {
                    exportAsMarkdown()
                }
                
                ExportOptionButton(
                    icon: "doc.richtext",
                    title: "PDF",
                    description: "Export as PDF document"
                ) {
                    exportAsPDF()
                }
                
                ExportOptionButton(
                    icon: "doc.plaintext",
                    title: "Text",
                    description: "Export as plain text"
                ) {
                    exportAsText()
                }
            }
            
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(width: 300)
    }
    
    private func exportAsMarkdown() {
        // TODO: Implement markdown export
        dismiss()
    }
    
    private func exportAsPDF() {
        // TODO: Implement PDF export
        dismiss()
    }
    
    private func exportAsText() {
        // TODO: Implement text export
        dismiss()
    }
}

struct ExportOptionButton: View {
    let icon: String
    let title: String
    let description: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
} 