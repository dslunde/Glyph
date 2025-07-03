import SwiftUI
import AppKit
import PythonKit
import os.log

@main
struct GlyphApp: App {
    init() {
        print("🚀 Glyph starting with API configuration")
        
        // Configure Python asynchronously to avoid blocking app startup
        Task {
            await Self.configurePythonAsync()
        }
    }
    
    private static func configurePythonAsync() async {
        print("🐍 Starting asynchronous Python configuration...")
        PythonGraphService.ensurePythonConfigured()
        print("✅ Python configuration completed")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject private var projectManager = ProjectManager()
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var environmentService = EnvironmentService.shared
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                NavigationSplitView {
                    // Sidebar
                    VStack {
                        // Header with New Project button
                        HStack {
                            Text("Glyph")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            Button(action: {
                                projectManager.showingCreateProject = true
                            }) {
                                Image(systemName: "plus")
                                    .font(.title2)
                            }
                            .buttonStyle(.borderedProminent)
                            .help("Create New Project")
                        }
                        .padding()
                        
                        // Configuration Status
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: environmentService.isFullyConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(environmentService.isFullyConfigured ? .green : .orange)
                                Text("API Configuration")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            
                            Text(environmentService.configurationMessage)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        
                        Divider()
                        
                        // Projects List
                        List(selection: $projectManager.selectedProject) {
                            ForEach(projectManager.projects, id: \.id) { project in
                                ProjectRowView(project: project)
                                    .tag(project)
                                    .contextMenu {
                                        Button("Delete", role: .destructive) {
                                            projectManager.deleteProject(project)
                                        }
                                    }
                            }
                            .onDelete(perform: deleteProjects)
                        }
                        .listStyle(SidebarListStyle())
                        
                        Spacer()
                        
                        // Mode Toggle
                        HStack {
                            Text(projectManager.isOnlineMode ? "Online" : "Offline")
                                .font(.caption)
                                .foregroundColor(projectManager.isOnlineMode ? .green : .orange)
                            
                            Spacer()
                            
                            Button(action: {
                                projectManager.toggleOnlineMode()
                            }) {
                                Image(systemName: projectManager.isOnlineMode ? "wifi" : "wifi.slash")
                                    .foregroundColor(projectManager.isOnlineMode ? .green : .orange)
                            }
                            .buttonStyle(.plain)
                            .help("Toggle Online/Offline Mode")
                        }
                        .padding()
                    }
                    .frame(minWidth: 250)
                    
                } detail: {
                    // Main Content
                    if let selectedProject = projectManager.selectedProject {
                        ProjectDetailView(project: selectedProject)
                            .environmentObject(projectManager)
                    } else {
                        // Welcome View
                        VStack {
                            Image(systemName: "network")
                                .font(.system(size: 64))
                                .foregroundColor(.secondary)
                            
                            Text("Welcome to Glyph")
                                .font(.title)
                                .fontWeight(.bold)
                                .padding(.top)
                            
                            Text("Create a project to start building knowledge graphs")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding()
                            
                            Button("Create New Project") {
                                projectManager.showingCreateProject = true
                            }
                            .buttonStyle(.borderedProminent)
                            .padding()
                            
                            // Configuration guidance
                            if !environmentService.isFullyConfigured {
                                VStack(spacing: 8) {
                                    HStack {
                                        Image(systemName: "info.circle")
                                            .foregroundColor(.blue)
                                        Text("API Configuration Required")
                                            .font(.headline)
                                    }
                                    
                                    Text("To use search features, configure your API keys:")
                                        .font(.body)
                                        .multilineTextAlignment(.center)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("1. Copy `.env.sample` to `.env`")
                                        Text("2. Add your OpenAI API key")
                                        Text("3. Add your Tavily API key")
                                        Text("4. Restart the application")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                                .padding()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .sheet(isPresented: $projectManager.showingCreateProject) {
                    CreateProjectView()
                        .environmentObject(projectManager)
                }
                .sheet(isPresented: $projectManager.showingKnowledgeGraphProgress) {
                    if let project = projectManager.selectedProject {
                        KnowledgeGraphProgressView(
                            sources: projectManager.knowledgeGraphSources,
                            topic: project.topic.isEmpty ? project.name : project.topic,
                            onCompletion: { graphData in
                                projectManager.completeKnowledgeGraphGeneration(with: graphData)
                            },
                            onCancel: {
                                projectManager.cancelKnowledgeGraphGeneration()
                            }
                        )
                    } else {
                        VStack {
                            Text("Error: No project selected")
                                .font(.title2)
                            Button("Cancel") {
                                projectManager.cancelKnowledgeGraphGeneration()
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                    }
                }
                .alert("Error", isPresented: $projectManager.showingError) {
                    Button("OK") { }
                } message: {
                    Text(projectManager.errorMessage)
                }
            } else {
                // Login View
                LoginView()
                    .environmentObject(authManager)
            }
        }
        .onAppear {
            // Reload environment configuration on app launch
            environmentService.reloadConfiguration()
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
    @State private var filePaths: [String] = [""]
    @State private var urls: [String] = [""]
    @State private var hypotheses = ""
    @State private var controversialAspects = ""
    @State private var sensitivityLevel: SensitivityLevel = .medium
    @State private var showingSourceCollection = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Project")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Create") {
                        showingSourceCollection = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!formIsValid)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
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
                            
                            // Custom grid layout with specific order
                            VStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    // Top Left: Reliable
                                    SourcePreferenceCard(
                                        preference: .reliable,
                                        isSelected: sourcePreferences.contains(.reliable)
                                    ) {
                                        toggleSourcePreference(.reliable)
                                    }
                                    
                                    // Top Right: Unreliable
                                    SourcePreferenceCard(
                                        preference: .unreliable,
                                        isSelected: sourcePreferences.contains(.unreliable)
                                    ) {
                                        toggleSourcePreference(.unreliable)
                                    }
                                }
                                
                                HStack(spacing: 8) {
                                    // Bottom Left: Insider
                                    SourcePreferenceCard(
                                        preference: .insider,
                                        isSelected: sourcePreferences.contains(.insider)
                                    ) {
                                        toggleSourcePreference(.insider)
                                    }
                                    
                                    // Bottom Right: Outsider
                                    SourcePreferenceCard(
                                        preference: .outsider,
                                        isSelected: sourcePreferences.contains(.outsider)
                                    ) {
                                        toggleSourcePreference(.outsider)
                                    }
                                }
                            }
                        }
                        
                        // File and Folder Paths
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("File/Folder Paths")
                                    .font(.headline)
                                
                                Spacer()
                                
                                Button(action: { filePaths.append("") }) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.green)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Text("Add local file or folder paths to analyze")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ForEach(filePaths.indices, id: \.self) { index in
                                HStack {
                                    TextField("Enter file or folder path", text: $filePaths[index])
                                        .textFieldStyle(.roundedBorder)
                                    
                                    Button(action: { selectFile(for: index) }) {
                                        Image(systemName: "folder")
                                            .foregroundColor(.blue)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Browse for file or folder")
                                    
                                    if filePaths.count > 1 {
                                        Button(action: { filePaths.remove(at: index) }) {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        
                        // URLs
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("URLs")
                                    .font(.headline)
                                
                                Spacer()
                                
                                Button(action: { urls.append("") }) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.green)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Text("Add web URLs to analyze (will be processed in offline mode)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ForEach(urls.indices, id: \.self) { index in
                                HStack {
                                    TextField("Enter URL (https://...)", text: $urls[index])
                                        .textFieldStyle(.roundedBorder)
                                    
                                    if urls.count > 1 {
                                        Button(action: { urls.remove(at: index) }) {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sensitivity Level")
                                .font(.headline)
                            
                            HStack {
                                Text("Algorithm sensitivity for finding gaps and contradictions")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Menu {
                                    ForEach(SensitivityLevel.allCases, id: \.self) { level in
                                        Button(action: { sensitivityLevel = level }) {
                                            HStack {
                                                Text(level.displayName)
                                                if sensitivityLevel == level {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(sensitivityLevel.displayName)
                                        Image(systemName: "chevron.down")
                                            .font(.caption)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
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
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
        }
        .frame(width: 700, height: 800)
        .sheet(isPresented: $showingSourceCollection) {
            SourceCollectionView(
                projectConfig: ProjectConfiguration(
                    name: name,
                    description: description,
                    topic: topic,
                    depth: depth,
                    sourcePreferences: Array(sourcePreferences),
                    filePaths: filePaths.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                    urls: urls.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                    hypotheses: hypotheses,
                    controversialAspects: controversialAspects,
                    sensitivityLevel: sensitivityLevel
                )
            )
            .environmentObject(projectManager)
            .onDisappear {
                dismiss()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private var formIsValid: Bool {
        let nameValid = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let topicValid = !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let sourcePrefsValid = !sourcePreferences.isEmpty
        
        // File paths validation: can have at most 1 empty field (n paths, at least n-1 filled)
        let nonEmptyPaths = filePaths.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let requiredFilledPaths = max(0, filePaths.count - 1) // Can leave 1 empty
        let filePathsValid = nonEmptyPaths.count >= requiredFilledPaths
        
        // URLs validation: can have at most 1 empty field (m URLs, at least m-1 filled)
        let nonEmptyUrls = urls.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let requiredFilledUrls = max(0, urls.count - 1) // Can leave 1 empty
        let urlsValid = nonEmptyUrls.count >= requiredFilledUrls

        return (nameValid && topicValid && sourcePrefsValid && filePathsValid && urlsValid)
    }
    
    private func toggleSourcePreference(_ preference: SourcePreference) {
        if sourcePreferences.contains(preference) {
            sourcePreferences.remove(preference)
        } else {
            sourcePreferences.insert(preference)
        }
    }
    
    private func selectFile(for index: Int) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                filePaths[index] = url.path
            }
        }
    }
}

// MARK: - Project Configuration Model

struct ProjectConfiguration {
    let name: String
    let description: String
    let topic: String
    let depth: ProjectDepth
    let sourcePreferences: [SourcePreference]
    let filePaths: [String]
    let urls: [String]
    let hypotheses: String
    let controversialAspects: String
    let sensitivityLevel: SensitivityLevel
}

// MARK: - Source Collection View

struct SourceCollectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var projectManager: ProjectManager
    
    let projectConfig: ProjectConfiguration
    
    @State private var manualSources: [ManualSource] = []
    @State private var enhancedManualSources: [[String: Any]] = []
    @State private var searchResults: [SearchResult] = []
    @State private var isSearching = false
    @State private var canContinue = false
    @State private var searchLimit = 5
    @State private var reliabilityThreshold: Double = 60.0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Source Collection")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Validating sources for \(projectConfig.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            VStack(spacing: 0) {
                // Manual Sources Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Manual Sources")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    if manualSources.isEmpty {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("No manual sources added")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(manualSources) { source in
                                ManualSourceRow(source: source)
                            }
                        }
                    }
                }
                .padding()
                
                Divider()
                
                // Online Search Results Section (if online mode)
                if projectManager.isOnlineMode {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Search Results")
                                .font(.title3)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            // Search controls
                            HStack(spacing: 8) {
                                Text("Limit:")
                                    .font(.caption)
                                Stepper("\(searchLimit)", value: $searchLimit, in: 1...20)
                                    .frame(width: 80)
                                
                                Text("Threshold:")
                                    .font(.caption)
                                Stepper("\(Int(reliabilityThreshold))%", value: $reliabilityThreshold, in: 0...100, step: 10)
                                    .frame(width: 80)
                            }
                            .font(.caption)
                        }
                        
                        if isSearching {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Searching for sources...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        } else if searchResults.isEmpty {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.gray)
                                Text("Click 'Get More Results' to search for sources")
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 8) {
                                    ForEach(searchResults) { result in
                                        SearchResultRow(result: result) { action in
                                            handleSearchResultAction(result: result, action: action)
                                        }
                                    }
                                }
                                .padding(.bottom)
                            }
                            .frame(maxHeight: 300)
                        }
                    }
                    .padding()
                    
                    Divider()
                } else {
                    // Offline mode message
                    VStack {
                        HStack {
                            Image(systemName: "wifi.slash")
                                .foregroundColor(.orange)
                            Text("Offline Mode: Online search features disabled")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .padding()
                    
                    Divider()
                }
                
                Spacer()
                
                // Bottom buttons
                HStack {
                    Button("Get More Results") {
                        Task {
                            await performSearch()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!projectManager.isOnlineMode || isSearching)
                    
                    Spacer()
                    
                    Button("Continue") {
                        createProjectWithSources()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canContinue)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .frame(width: 800, height: 700)
        .onAppear {
            setupManualSources()
            updateContinueState()
        }
    }
    
    // MARK: - Helper Methods
    
    private func setupManualSources() {
        print("🔍 DEBUG: setupManualSources() called")
        print("🔍 DEBUG: projectConfig.filePaths = \(projectConfig.filePaths)")
        print("🔍 DEBUG: projectConfig.urls = \(projectConfig.urls)")
        print("🔍 DEBUG: projectManager.isOnlineMode = \(projectManager.isOnlineMode)")
        
        manualSources.removeAll()
        
        // Add file paths
        for filePath in projectConfig.filePaths {
            let source = ManualSource(
                path: filePath,
                type: .file,
                status: .validating
            )
            manualSources.append(source)
            print("🔍 DEBUG: Added file source: \(filePath)")
        }
        
        // Add URLs
        for url in projectConfig.urls {
            let source = ManualSource(
                path: url,
                type: .url,
                status: projectManager.isOnlineMode ? .validating : .invalid
            )
            manualSources.append(source)
            print("🔍 DEBUG: Added URL source: \(url), status: \(source.status)")
        }
        
        print("🔍 DEBUG: Total manual sources added: \(manualSources.count)")
        
        // Start enhanced processing and validation
        Task {
            print("🔍 DEBUG: Starting processManualSourcesWithEnhancement task")
            await processManualSourcesWithEnhancement()
        }
    }
    
    private func processManualSourcesWithEnhancement() async {
        print("🔍 DEBUG: processManualSourcesWithEnhancement() called")
        
        // First do basic validation
        await validateManualSources()
        
        // Then run enhanced processing if we have valid sources
        let validFilePaths = projectConfig.filePaths.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let validUrls = projectConfig.urls.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        print("🔍 DEBUG: validFilePaths = \(validFilePaths.count), validUrls = \(validUrls.count)")
        
        if !validFilePaths.isEmpty || !validUrls.isEmpty {
            do {
                print("🚀 Running enhanced source processing...")
                print("🔍 DEBUG: About to call processManualSources with:")
                print("   - filePaths: \(validFilePaths)")
                print("   - urls: \(validUrls)")
                print("   - topic: \(projectConfig.topic)")
                
                let enhancedResult = try await projectManager.pythonService.processManualSources(
                    filePaths: validFilePaths,
                    urls: validUrls,
                    topic: projectConfig.topic,
                    maxPages: 10
                )
                
                print("🔍 DEBUG: Enhanced processing returned: \(enhancedResult)")
                
                // Extract enhanced sources
                if let sources = enhancedResult["sources"] as? [[String: Any]] {
                    await MainActor.run {
                        // Store enhanced sources for knowledge graph generation
                        enhancedManualSources = sources
                        print("✅ Enhanced processing complete: \(sources.count) total sources")
                        print("🔍 DEBUG: Stored \(enhancedManualSources.count) enhanced sources")
                        
                        // Update UI to show enhancement results
                        if let metadata = enhancedResult["metadata"] as? [String: Any] {
                            let filesProcessed = metadata["files_processed"] as? Int ?? 0
                            let urlsExpanded = metadata["total_discovered_pages"] as? Int ?? 0
                            
                            print("🔍 DEBUG: Metadata - files: \(filesProcessed), urls: \(urlsExpanded)")
                            
                            // Update manual source status to show enhancement
                            for index in manualSources.indices {
                                if manualSources[index].status == .valid {
                                    if manualSources[index].type == .file && filesProcessed > 0 {
                                        manualSources[index].enhancementInfo = "Content extracted"
                                    } else if manualSources[index].type == .url && urlsExpanded > 0 {
                                        manualSources[index].enhancementInfo = "Expanded to \(urlsExpanded) pages"
                                    }
                                }
                            }
                        }
                        
                        updateContinueState()
                    }
                } else {
                    print("❌ DEBUG: No sources found in enhanced result")
                    await MainActor.run {
                        enhancedManualSources = []
                        updateContinueState()
                    }
                }
                
            } catch {
                print("❌ Enhanced source processing failed: \(error)")
                await MainActor.run {
                    // Fall back to basic manual sources
                    enhancedManualSources = []
                    updateContinueState()
                }
            }
        } else {
            print("🔍 DEBUG: No valid sources to process")
        }
    }
    
    private func validateManualSources() async {
        for index in manualSources.indices {
            let source = manualSources[index]
            
            switch source.type {
            case .file:
                let fileExists = FileManager.default.fileExists(atPath: source.path)
                let isReadable = FileManager.default.isReadableFile(atPath: source.path)
                
                await MainActor.run {
                    manualSources[index].status = (fileExists && isReadable) ? .valid : .invalid
                    updateContinueState()
                }
                
            case .url:
                if projectManager.isOnlineMode {
                    // In a real implementation, we'd check URL reachability
                    // For now, simulate async validation
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    
                    await MainActor.run {
                        // Simple URL validation - check if it looks like a proper URL
                        if source.path.hasPrefix("http://") || source.path.hasPrefix("https://") {
                            manualSources[index].status = .valid
                        } else {
                            manualSources[index].status = .invalid
                        }
                        updateContinueState()
                    }
                } else {
                    await MainActor.run {
                        manualSources[index].status = .invalid
                        updateContinueState()
                    }
                }
            }
        }
    }
    
    private func updateContinueState() {
        // Continue is enabled when all manual sources are validated (not in .validating state)
        canContinue = !manualSources.contains { $0.status == .validating }
    }
    
    private func performSearch() async {
        guard projectManager.isOnlineMode else { return }
        
        isSearching = true
        
        // Start LangSmith tracing
        let langSmith = LangSmithService.shared
        let runId = await langSmith.startSearchRun(
            topic: projectConfig.topic,
            searchLimit: searchLimit,
            reliabilityThreshold: reliabilityThreshold
        )
        
        do {
            let startTime = Date()
            
            // Validate API Keys
            let apiKeysValid = [
                "OPENAI_API_KEY": EnvironmentService.shared.hasAPIKey(for: "OPENAI_API_KEY"),
                "TAVILY_API_KEY": EnvironmentService.shared.hasAPIKey(for: "TAVILY_API_KEY")
            ]
            await langSmith.logAPIKeyValidation(runId: runId, keys: apiKeysValid)
            
            // Run LangGraph workflow (PRIMARY APPROACH)
            // This replaces the old sequential API calls with a state machine that provides:
            // - Robust error handling and recovery
            // - Comprehensive LangSmith tracing
            // - State-based progress tracking
            // - Automatic fallback strategies
            print("🚀 Starting LangGraph source collection workflow...")
            let workflowResult = try await runLangGraphWorkflow()
            
            // Process workflow results
            if workflowResult["success"] as? Bool == true {
                if let results = workflowResult["results"] as? [[String: Any]] {
                    let filteredResults = results.compactMap { resultDict -> TavilyResult? in
                        guard let title = resultDict["title"] as? String,
                              let url = resultDict["url"] as? String,
                              let content = resultDict["content"] as? String else {
                            return nil
                        }
                        
                        var result = TavilyResult(
                            title: title,
                            url: url,
                            content: content,
                            score: resultDict["score"] as? Double ?? 0.0,
                            publishedDate: resultDict["published_date"] as? String ?? ""
                        )
                        result.reliabilityScore = resultDict["reliability_score"] as? Double ?? 50.0
                        return result
                    }
                    
                    // Stream results to UI
                    await streamResults(filteredResults)
                    
                    // Log success to LangSmith
                    let totalDuration = Date().timeIntervalSince(startTime)
                    let metadata = workflowResult["metadata"] as? [String: Any] ?? [:]
                    
                    await langSmith.endSearchRun(
                        runId: runId,
                        outputs: [
                            "total_results": filteredResults.count,
                            "total_duration": totalDuration,
                            "queries_generated": metadata["total_queries"] as? Int ?? 0,
                            "search_successful": true,
                            "workflow_type": "langgraph",
                            "error_count": metadata["error_count"] as? Int ?? 0,
                            "fallback_used": metadata["fallback_used"] as? Bool ?? false
                        ]
                    )
                    
                    print("✅ LangGraph workflow completed successfully")
                    print("   📊 Final results: \(filteredResults.count)")
                    print("   ⚠️  Errors: \(metadata["error_count"] as? Int ?? 0)")
                    print("   🔄 Fallback used: \(metadata["fallback_used"] as? Bool ?? false)")
                    
                } else {
                    throw APIError.invalidResponse
                }
            } else {
                let errorMessage = workflowResult["error_message"] as? String ?? "Unknown workflow error"
                throw APIError.networkError(errorMessage)
            }
            
        } catch {
            print("❌ LangGraph workflow failed: \(error)")
            
            // Log error to LangSmith
            await langSmith.logError(
                runId: runId,
                stepName: "LangGraph Workflow",
                error: error,
                context: [
                    "topic": projectConfig.topic,
                    "search_limit": searchLimit,
                    "reliability_threshold": reliabilityThreshold,
                    "workflow_type": "langgraph"
                ]
            )
            
            // End failed run
            await langSmith.endSearchRun(
                runId: runId,
                outputs: [
                    "search_successful": false,
                    "error_message": error.localizedDescription,
                    "workflow_type": "langgraph"
                ],
                error: error.localizedDescription
            )
            
            await MainActor.run {
                // Show error to user
                projectManager.errorMessage = "LangGraph workflow failed: \(error.localizedDescription)"
                projectManager.showingError = true
            }
        }
        
        isSearching = false
    }
    
    private func runLangGraphWorkflow() async throws -> [String: Any] {
        // Get API keys
        let openaiApiKey = EnvironmentService.shared.getAPIKey(for: "OPENAI_API_KEY") ?? ""
        let tavilyApiKey = EnvironmentService.shared.getAPIKey(for: "TAVILY_API_KEY") ?? ""
        
        guard !openaiApiKey.isEmpty else {
            throw APIError.missingKey("OpenAI API key not found. Please check your .env file.")
        }
        
        guard !tavilyApiKey.isEmpty else {
            throw APIError.missingKey("Tavily API key not found. Please check your .env file.")
        }
        
        // Convert source preferences to string array
        let sourcePrefs = projectConfig.sourcePreferences.map { $0.rawValue }
        
        // Call the LangGraph workflow through Python service
        print("🔄 Calling LangGraph source collection workflow...")
        let result = try await projectManager.pythonService.runSourceCollectionWorkflow(
            topic: projectConfig.topic,
            searchLimit: searchLimit,
            reliabilityThreshold: reliabilityThreshold,
            sourcePreferences: sourcePrefs,
            openaiApiKey: openaiApiKey,
            tavilyApiKey: tavilyApiKey
        )
        
        return result
    }
    
    // MARK: - Deprecated Helper Methods (No longer used with LangGraph workflow)
    // These methods were used by the old sequential processing approach.
    // The LangGraph workflow handles filtering logic internally.
    
    private func streamResults(_ results: [TavilyResult]) async {
        // Convert to SearchResult and stream them
        for result in results {
            let searchResult = SearchResult(
                title: result.title,
                author: extractAuthor(from: result.content),
                date: formatDate(result.publishedDate),
                reliabilityScore: Int(result.reliabilityScore),
                url: result.url,
                status: .pending
            )
            
            await MainActor.run {
                searchResults.append(searchResult)
            }
            
            // Small delay for smooth streaming effect
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        }
    }
    
    private func extractAuthor(from content: String) -> String {
        // Simple author extraction from content
        // In a real implementation, this could be more sophisticated
        if content.contains("by ") {
            let components = content.components(separatedBy: "by ")
            if components.count > 1 {
                let authorPart = components[1].components(separatedBy: " ").prefix(3).joined(separator: " ")
                return authorPart.trimmingCharacters(in: .punctuationCharacters)
            }
        }
        return "Unknown Author"
    }
    
    private func formatDate(_ dateString: String) -> String {
        if dateString.isEmpty {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: Date())
        }
        return dateString
    }
    
    private func handleSearchResultAction(result: SearchResult, action: SearchResultAction) {
        if let index = searchResults.firstIndex(where: { $0.id == result.id }) {
            switch action {
            case .use:
                searchResults[index].status = .approved
                print("✅ User approved result: \(result.title)")
            case .drop:
                searchResults.remove(at: index)
                print("❌ User dropped result: \(result.title)")
            }
            
            // Log user actions to LangSmith
            let langSmith = LangSmithService.shared
            if let runId = langSmith.currentRunId {
                let approvedCount = searchResults.filter { $0.status == .approved }.count
                let totalCount = searchResults.count + (action == .drop ? 1 : 0) // Include dropped result in total
                Task {
                    await langSmith.logUserActions(
                        runId: runId,
                        approved: approvedCount,
                        dropped: totalCount - approvedCount
                    )
                }
            }
        }
    }
    
    private func createProjectWithSources() {
        print("🚨🚨🚨 DEBUG: createProjectWithSources() called - THIS SHOULD BE VISIBLE! 🚨🚨🚨")
        print("🔍 DEBUG: createProjectWithSources() called")
        
        // Collect approved sources
        let approvedSources = searchResults.filter { $0.status == .approved }
        let validManualSources = manualSources.filter { $0.status == .valid }
        
        print("🔍 DEBUG: approvedSources = \(approvedSources.count), validManualSources = \(validManualSources.count)")
        
        // Convert SearchResults to the format expected by knowledge graph generation
        let sourcesForKG = approvedSources.map { searchResult in
            [
                "title": searchResult.title,
                "content": "Research article by \(searchResult.author) from \(searchResult.date). Reliability score: \(searchResult.reliabilityScore)%",
                "url": searchResult.url,
                "score": Double(searchResult.reliabilityScore) / 100.0,
                "published_date": searchResult.date,
                "query": projectConfig.topic,
                "reliability_score": searchResult.reliabilityScore
            ] as [String: Any]
        }
        
        // Use enhanced manual sources if available, otherwise fall back to basic sources
        let manualSourcesForKG: [[String: Any]]
        if !enhancedManualSources.isEmpty {
            print("🚀 Using enhanced manual sources for knowledge graph: \(enhancedManualSources.count) sources")
            manualSourcesForKG = enhancedManualSources
        } else {
            print("🔄 Using basic manual sources for knowledge graph: \(validManualSources.count) sources")
            manualSourcesForKG = validManualSources.map { manualSource in
                [
                    "title": manualSource.type == .file ? "File Source" : "URL Source", 
                    "content": "Manual source: \(manualSource.path)",
                    "url": manualSource.path,
                    "score": 0.8,
                    "published_date": "",
                    "query": projectConfig.topic,
                    "reliability_score": 80
                ] as [String: Any]
            }
        }
        
        let allSources = sourcesForKG + manualSourcesForKG
        
        // Create learning plan with approved sources instead of Lorem Ipsum
        let learningPlan = generateLearningPlanWithSources(approvedSources: approvedSources, manualSources: validManualSources)
        
        print("🔍 DEBUG: About to create project with custom learning plan and \(allSources.count) sources")
        
        // Create the project
        projectManager.createProjectWithCustomLearningPlanAndSources(
            name: projectConfig.name,
            description: projectConfig.description,
            topic: projectConfig.topic,
            depth: projectConfig.depth,
            sourcePreferences: projectConfig.sourcePreferences,
            filePaths: projectConfig.filePaths,
            urls: projectConfig.urls,
            hypotheses: projectConfig.hypotheses,
            controversialAspects: projectConfig.controversialAspects,
            sensitivityLevel: projectConfig.sensitivityLevel,
            learningPlan: learningPlan,
            sources: allSources
        )
        
        print("🔍 DEBUG: Project created, now starting knowledge graph generation")
        
        // Start knowledge graph generation with the same sources
        if !allSources.isEmpty {
            if let createdProject = projectManager.selectedProject {
                print("🔍 DEBUG: Calling startKnowledgeGraphGeneration with \(allSources.count) sources")
                projectManager.startKnowledgeGraphGeneration(from: allSources, for: createdProject)
            } else {
                print("❌ DEBUG: No selected project found!")
            }
        } else {
            print("🔍 DEBUG: No sources available for knowledge graph generation!")
        }
        
        print("🔍 DEBUG: About to dismiss the SourceCollectionView")
        dismiss()
    }
    
    private func generateLearningPlanWithSources(approvedSources: [SearchResult], manualSources: [ManualSource]) -> String {
        var plan = """
        # Learning Plan for \(projectConfig.name)
        
        ## Overview
        This learning plan has been generated based on your approved sources and configuration.
        
        **Topic**: \(projectConfig.topic)
        **Depth Level**: \(projectConfig.depth.displayName)
        **Source Preferences**: \(projectConfig.sourcePreferences.map(\.displayName).joined(separator: ", "))
        
        """
        
        if !approvedSources.isEmpty {
            plan += """
            
            ## Approved Research Sources
            
            """
            
            for (index, source) in approvedSources.enumerated() {
                plan += """
                \(index + 1). **\(source.title)**
                   - Author: \(source.author)
                   - Date: \(source.date)
                   - Reliability Score: \(source.reliabilityScore)%
                   - URL: \(source.url)
                
                """
            }
        }
        
        if !manualSources.isEmpty {
            plan += """
            
            ## Manual Sources
            
            """
            
            for (index, source) in manualSources.enumerated() {
                plan += """
                \(index + 1). **\(source.type == .file ? "File" : "URL")**: \(source.path)
                   - Status: \(source.status == .valid ? "✅ Valid" : "❌ Invalid")
                
                """
            }
        }
        
        plan += """
        
        ## Learning Phases
        
        ### Phase 1: Foundation Building
        Begin with the approved sources to establish core understanding of \(projectConfig.topic).
        
        ### Phase 2: Deep Dive Analysis
        Analyze the relationships and connections between concepts from your sources.
        
        ### Phase 3: Synthesis and Application
        Apply insights to your specific hypotheses and controversial aspects.
        
        ## Next Steps
        1. Review and organize your approved sources
        2. Create detailed notes from each source
        3. Identify patterns and connections
        4. Generate knowledge graph from findings
        
        """
        
        if !projectConfig.hypotheses.isEmpty {
            plan += """
            ## Initial Hypotheses to Explore
            \(projectConfig.hypotheses)
            
            """
        }
        
        if !projectConfig.controversialAspects.isEmpty {
            plan += """
            ## Controversial Aspects to Consider
            \(projectConfig.controversialAspects)
            
            """
        }
        
        return plan
    }
}

// MARK: - Supporting Data Models

struct ManualSource: Identifiable {
    let id = UUID()
    let path: String
    let type: ManualSourceType
    var status: ValidationStatus
    var enhancementInfo: String?
}

enum ManualSourceType {
    case file
    case url
}

enum ValidationStatus {
    case validating
    case valid
    case invalid
    
    var iconName: String {
        switch self {
        case .validating:
            return "clock"
        case .valid:
            return "checkmark.circle.fill"
        case .invalid:
            return "xmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .validating:
            return .orange
        case .valid:
            return .green
        case .invalid:
            return .red
        }
    }
}

struct SearchResult: Identifiable {
    let id = UUID()
    let title: String
    let author: String
    let date: String
    let reliabilityScore: Int
    let url: String
    var status: SearchResultStatus
}

enum SearchResultStatus {
    case pending
    case approved
    case dropped
}

enum SearchResultAction {
    case use
    case drop
}

struct TavilyResult {
    let title: String
    let url: String
    let content: String
    let score: Double
    let publishedDate: String
    var reliabilityScore: Double = 0.0
}

enum APIError: Error {
    case missingKey(String)
    case networkError(String)
    case invalidResponse
    
    var localizedDescription: String {
        switch self {
        case .missingKey(let key):
            return "Missing API key: \(key)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidResponse:
            return "Invalid API response"
        }
    }
}

// MARK: - Supporting Views

struct ManualSourceRow: View {
    let source: ManualSource
    
    var body: some View {
        HStack {
            Image(systemName: source.status.iconName)
                .foregroundColor(source.status.color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(source.type == .file ? "File" : "URL")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let enhancement = source.enhancementInfo {
                        Text("• \(enhancement)")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                
                Text(source.path)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(source.status == .validating ? "Validating..." : (source.status == .valid ? "Valid" : "Invalid"))
                    .font(.caption)
                    .foregroundColor(source.status.color)
                
                if source.status == .valid && source.enhancementInfo != nil {
                    Text("Enhanced")
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(3)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(source.status.color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct SearchResultRow: View {
    let result: SearchResult
    let onAction: (SearchResultAction) -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.headline)
                    .lineLimit(2)
                
                HStack {
                    Text("By \(result.author)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(result.date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Reliability: \(result.reliabilityScore)%")
                        .font(.caption)
                        .foregroundColor(result.reliabilityScore >= 60 ? .green : (result.reliabilityScore <= 40 ? .red : .orange))
                    
                    Spacer()
                }
            }
            
            Spacer()
            
            if result.status == .pending {
                VStack(spacing: 8) {
                    Button("Use") {
                        onAction(.use)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    Button("Drop") {
                        onAction(.drop)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                Text("Approved")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .cornerRadius(4)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Source Preference Card Component

struct SourcePreferenceCard: View {
    let preference: SourcePreference
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(preference.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(preference.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(preference.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? preference.color.opacity(0.1) : Color.clear)
                    .stroke(preference.color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

struct ProjectDetailView: View {
    let project: Project
    @EnvironmentObject private var projectManager: ProjectManager
    @State private var showingProjectInfo = false
    @State private var selectedTab = 0
    
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
                    // Analysis button (disabled for now)
                    Button(action: {
                        // Coming soon - do nothing for now
                    }) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Analyze")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
                    .overlay(
                        // Invisible overlay to capture hover for tooltip since disabled buttons don't show help
                        Rectangle()
                            .fill(Color.clear)
                            .help("Coming Soon: Advanced analysis features")
                    )
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Tab View as specified in PRD
            TabView(selection: $selectedTab) {
                // Learning Plan Tab
                LearningPlanView()
                    .tabItem {
                        Image(systemName: "doc.text")
                        Text("Learning Plan")
                    }
                    .tag(0)
                
                // Knowledge Graph Tab  
                KnowledgeGraphCanvasView()
                    .tabItem {
                        Image(systemName: "network")
                        Text("Knowledge Graph")
                    }
                    .tag(1)
                
                // Chat Assistant Tab
                ChatView()
                    .tabItem {
                        Image(systemName: "message")
                        Text("Chat")
                    }
                    .tag(2)
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
    @State private var cursorPosition: CGPoint = .zero
    
    init(graphData: GraphData) {
        self._graphData = State(initialValue: graphData)
    }
    
    var body: some View {
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
                    context.clipToLayer(opacity: 1) { context in
                        // Apply zoom and pan transformations
                        context.translateBy(x: panOffset.width, y: panOffset.height)
                        context.scaleBy(x: zoomScale, y: zoomScale)
                        
                        // Draw edges first (so they appear behind nodes)
                        drawEdges(context: context)
                        
                        // Draw nodes
                        drawNodes(context: context)
                        
                        // Draw cursor position indicator
                        let cursorInGraph = CGPoint(
                            x: (cursorPosition.x - panOffset.width) / zoomScale,
                            y: (cursorPosition.y - panOffset.height) / zoomScale
                        )
                        
                        let cursorRect = CGRect(x: cursorInGraph.x - 5, y: cursorInGraph.y - 5, width: 10, height: 10)
                        context.fill(Path(ellipseIn: cursorRect), with: .color(.red))
                    }
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        cursorPosition = location
                    case .ended:
                        break
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
                        
                        // Debug info
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
                            Text("Cursor: (\(Int(cursorPosition.x)), \(Int(cursorPosition.y)))")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Text("Pan: (\(Int(panOffset.width)), \(Int(panOffset.height)))")
                                .font(.caption)
                                .foregroundColor(.blue)
                            if let firstNode = graphData.nodes.first {
                                Text("First node: (\(Int(firstNode.position.x)), \(Int(firstNode.position.y)))")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
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
        .onAppear {
            resetView()
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
        let transformedX = (node.position.x * zoomScale) + panOffset.width
        let transformedY = (node.position.y * zoomScale) + panOffset.height
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
        
        // Center the view on the graph nodes
        if !graphData.nodes.isEmpty {
            let minX = graphData.nodes.map { $0.position.x }.min() ?? 0
            let maxX = graphData.nodes.map { $0.position.x }.max() ?? 0
            let minY = graphData.nodes.map { $0.position.y }.min() ?? 0
            let maxY = graphData.nodes.map { $0.position.y }.max() ?? 0
            
            let centerX = (minX + maxX) / 2
            let centerY = (minY + maxY) / 2
            
            // Offset to center the graph in the view (assuming 400x300 visible area)
            panOffset = CGSize(width: 200 - centerX, height: 150 - centerY)
        } else {
            panOffset = .zero
        }
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

// MARK: - Authentication Views

struct LoginView: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var username = ""
    @State private var password = ""
    @State private var isCreatingAccount = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 30) {
            // App branding
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 80))
                    .foregroundColor(.purple)
                
                VStack(spacing: 8) {
                    Text("Glyph")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Knowledge Graph Explorer")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Login form
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Username")
                        .font(.headline)
                    TextField("Enter username", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.headline)
                    SecureField("Enter password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                }
                
                VStack(spacing: 12) {
                    Button(action: performLogin) {
                        Text(isCreatingAccount ? "Create Account" : "Login")
                            .frame(width: 280)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(username.isEmpty || password.isEmpty)
                    
                    Button(action: { isCreatingAccount.toggle() }) {
                        Text(isCreatingAccount ? "Already have an account? Login" : "Need an account? Create one")
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
            }
            
            Text("Sessions timeout after 1 hour of inactivity")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func performLogin() {
        if isCreatingAccount {
            if password.count < 6 {
                errorMessage = "Password must be at least 6 characters"
                showingError = true
                return
            }
            
            if authManager.createAccount(username: username, password: password) {
                // Success - authManager will handle state
            } else {
                errorMessage = "Failed to create account"
                showingError = true
            }
        } else {
            if authManager.login(username: username, password: password) {
                // Success - authManager will handle state
            } else {
                errorMessage = "Invalid username or password"
                showingError = true
            }
        }
    }
}

// MARK: - Tab Views

// LearningPlanView is now implemented in Sources/Glyph/Views/LearningPlanView.swift

struct KnowledgeGraphView: View {
    let project: Project
    @EnvironmentObject private var projectManager: ProjectManager
    
    var body: some View {
        VStack(spacing: 0) {
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
                    Image(systemName: "network")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("Loading Knowledge Graph...")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 8) {
                        Text("Graph data is being initialized")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Text("Configuration: \(project.depth.displayName) depth, \(project.sourcePreferences.count) source type(s)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
} 