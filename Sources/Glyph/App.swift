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
            
            if !project.description.isEmpty {
                Text(project.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            HStack {
                Label("\(project.graphData?.nodes.count ?? 0)", systemImage: "circle")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Label("\(project.graphData?.edges.count ?? 0)", systemImage: "arrow.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
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
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
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
                        .lineLimit(3...6)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("New Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        projectManager.createProject(name: name, description: description)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(width: 400, height: 300)
    }
}

struct ProjectDetailView: View {
    let project: Project
    @EnvironmentObject private var projectManager: ProjectManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Project header
            HStack {
                VStack(alignment: .leading) {
                    Text(project.name)
                        .font(.title)
                        .fontWeight(.bold)
                    
                    if !project.description.isEmpty {
                        Text(project.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
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
                // Empty state
                VStack(spacing: 20) {
                    Image(systemName: "network")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("No graph data available")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Text("Graph data is being initialized...")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// Placeholder views for missing components
struct GraphVisualizationView: View {
    let graphData: GraphData
    
    var body: some View {
        VStack {
            Text("Graph Visualization")
                .font(.headline)
            Text("\(graphData.nodes.count) nodes, \(graphData.edges.count) edges")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
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