# FlowGenius Project Requirement Document (PRD)

## 1. Project Overview
- **Purpose**: Build a macOS desktop app to create knowledge graphs and learning plans for research topics.
- **Target Platform**: macOS Sequoia 15.
- **Design Goals**: Curious, Focused, Insightful, Minimal, Intelligent, Empowering.
- **UI Style**: macOS native, minimalistic.
- **Offline Functionality**: Process only pre-saved files/folders; no online fetching in offline mode.
- **Authentication**: User authentication for project access control.
- **Performance**: Handle graphs of 1000–1,000,000 nodes, max 10 GB RAM, with progress display.

## 2. Technical Requirements

### 2.1 System Architecture
- **Frontend**: SwiftUI for native macOS UI.
- **Backend**: Python 3.13.3 (embedded via `pyenv`) for NLP and graph processing.
- **Integration**: PythonKit for Swift-Python bridging.
- **Storage**: Local SQLite for project metadata; JSON/GraphML for knowledge graphs; PDF for learning plans.
- **Offline Mode**: Process only local files/folders (PDFs, text).

### 2.2 Functional Requirements

#### 2.2.1 User Interface
- **Initial Login**
  - Users need to login with locally stored credentials
  - Logins should timeout after 1 hour of inactivity
- **Sidebar**:
  - "New Project" button.
  - List of user-specific previous projects (filtered by authentication).
- **New Project Flow**:
  - Input fields: Topic, Depth (Quick, Moderate, Comprehensive), Source Preferences (Reliable, Insider, Outsider, Unreliable) and inputs for File/Folder paths and URLs (adjustable number), Hypotheses (optional), Controversial Aspects (optional), Sensitivity Level (Low, Medium, High).
  - Preview and customize outputs (Learning Plan, Knowledge Graph).
- **Previous Project Flow**:
  - Load and display view with tabs for Learning Plan and Knowledge Graph.
- **Learning Plan View**:
  - Loads rich text editor with contents of Learning Plan
- **Knowledge Graph View**:
  - Interactive SwiftUI canvas (zoom, drag, click nodes for details).
  - Edit graph (add/remove nodes, adjust edges).
- **Progress Indicator**:
  - Display real-time progress for knowledge graph generation.

#### 2.2.2 Source Collection
- **Manual Input**:
  - Accept URLs, DOIs, PDFs, text files, or folder paths.
  - Tag sources: Reliable, Unreliable, Insider, Outsider.
- **Automated Search**:
  - Integrate APIs (LangSearch, Google Scholar, arXiv) with placeholder for API keys.
  - Display source metadata (title, author, date).
- **Source Analysis**:
  - Diversity analysis to flag bias (publication types, author backgrounds).
  - Contradiction detection via NLP (conflicting claims across sources).
  - Perspective scoring for uniqueness (cosine similarity on text embeddings).

#### 2.2.3 Knowledge Graph Generation
- **Processing**:
  - Use NLP (Swift NaturalLanguage or Python via `transformers`, `sentence-transformers`) to extract concepts, entities, relationships.
  - Generate graph with nodes (concepts) and edges (relationships).
- **Graph Analysis**:
  - **Core Concepts**: Degree Centrality (Swift custom or `networkx`), Betweenness (Brandes’ Algorithm), Eigenvector (Accelerate framework), PageRank (Metal kernel).
  - **Knowledge Gaps**: Identify missing nodes/edges via Wikidata/ConceptNet comparison.
  - **Counterintuitive Truths**: Highlight contradictions using sentiment/stance analysis.
  - **Uncommon Insights**: Cluster (k-means) for outlier concepts; prioritize low-frequency, high-relevance sources.
- **Performance**:
  - Optimize for 1,000–1,000,000 nodes, max 10 GB RAM.
  - Use sparse matrix operations (Accelerate or `scipy.sparse`).

#### 2.2.4 Output Creation
- **Learning Plan**:
  - Markdown document with sections: Key Concepts, Recommended Readings, Study Timeline, Open Questions, Practical Applications.
  - Export as PDF.
- **Requirements Document**:
  - Outline scope, objectives, technical requirements, resources.
- **Knowledge Gaps**:
  - List underexplored subtopics.
- **Counterintuitive Truths**:
  - Summarize contradictions.
- **Uncommon Insights**:
  - Highlight niche perspectives.
- **Customization**:
  - Allow reordering, adding notes to outputs.

#### 2.2.5 Export and Save
- **Storage**:
  - Save projects locally in SQLite (metadata) and GraphML (graphs).
  - Optional JSON for compatibility.
- **Export**:
  - Learning Plan as PDF.
  - Knowledge Graph as GraphML.
- **Revisiting**:
  - Load and update saved projects.

### 2.3 Core Algorithms
- **Centrality**:
  - Degree: `networkx.degree_centrality`.
  - Betweenness: Brandes’ Algorithm (`networkx`).
  - Eigenvector: Accelerate framework fallback `networkx.eigenvector_centrality`.
  - PageRank:`networkx.pagerank`.
- **Shortest Path**:
  - Brandes: Reuse for betweenness.
  - Closeness: BFS/Dijkstra (`networkx.closeness_centrality`).
  - All-pairs: Johnson’s or Floyd-Warshall (`scipy.sparse.csgraph`).
- **Minimal Subgraph**:
  - Steiner Tree: C++ bridge with fallback `networkx.algorithms.approximation`.
  - MST: Kruskal/Prim (Swift with fallback `networkx.minimum_spanning_tree`).
  - Topological Sort: DFS (Swift with fallback `networkx.topological_sort`).
- **Uncommon Insights**:
  - Louvain/Leiden: `igraph`.
  - Node2Vec: Python (`nodevectors`).
- **Knowledge Gaps**:
  - Link Prediction: Node2Vec + similarity (`scikit-learn`).
  - Anomaly Detection: GraphSAGE/LOF (`graph-learning`).
  - Structural Holes: Clustering coefficient (`networkx.clustering`).
- **Counterintuitive Truths**:
  - Multi-hop Inference: BFS (Swift).
  - Semantic Similarity: Node2Vec embeddings (`fastText`).

### 2.4 Dependencies
- **Swift**:
  - SwiftUI: Native UI.
  - NaturalLanguage: Basic NLP.
  - Accelerate: Matrix operations.
  - PythonKit: Python integration.
- **Python** (via `requirements.txt`):
  - `torch`, `numpy`, `scipy`, `scikit-learn`: ML and math.
  - `networkx`: Graph analysis.
  - `transformers`, `sentence-transformers`, `langchain`: NLP.
  - `nltk`, `spacy`: Traditional NLP.
  - `pandas`, `requests`: Data processing.
  - `matplotlib`, `plotly`: Visualization.
- **Python Setup**:
  - Embed Python 3.13.3 via `pyenv`.
  - Disable App Sandbox for PythonKit compatibility.

### 2.5 Security
- **Authentication**:
  - Local user authentication (macOS Keychain or custom login).
  - Restrict project access to authenticated user.
- **Data Storage**:
  - Encrypt SQLite database with SQLCipher.
  - Store projects locally, no iCloud syncing.

### 2.6 Development Steps
1. **Setup Environment**:
   - Configure Xcode for macOS Sequoia 15.
   - Embed Python 3.13.3 with `pyenv`.
   - Install Python dependencies from `requirements.txt`.
   - Set up PythonKit, disable App Sandbox.
2. **Build UI**:
   - Create SwiftUI sidebar with New Project and project list.
   - Implement input forms for topic, depth, source preferences, hypotheses, sensitivity.
   - Design interactive knowledge graph canvas.
   - Add progress indicator for graph generation.
3. **Source Collection**:
   - Implement file/folder parsing (PDFs, text).
   - Add placeholder API integration (LangSearch, Google Scholar, arXiv).
   - Build source tagging and metadata display.
   - Develop diversity analysis and contradiction detection (Python NLP).
4. **Knowledge Graph**:
   - Process sources with NLP (`transformers`, `sentence-transformers`).
   - Generate graph using `networkx` or Swift.
   - Implement centrality, shortest path, and subgraph algorithms.
   - Detect gaps, contradictions, and insights.
5. **Output Generation**:
   - Create Markdown learning plan and requirements document.
   - Export as PDF (Swift or Python `reportlab`).
   - Save graphs as GraphML.
6. **Storage and Authentication**:
   - Set up SQLite with SQLCipher for encrypted storage.
   - Implement user authentication with macOS Keychain.
   - Enable project loading and updating.
7. **Optimization**:
   - Optimize graph processing for 1000–1,000,000 nodes, max 10 GB RAM.
   - Use sparse matrices and Metal/Accelerate for performance.
8. **Testing**:
   - Test UI functionality (SwiftUI).
   - Validate graph algorithms (`networkx` vs. Swift).
   - Ensure offline mode and authentication work.

## 3. Deliverables
- macOS app (FlowGenius) for Sequoia 15.
- Embedded Python 3.13.3 environment.
- Source code with SwiftUI frontend and Python backend.
- Documentation for setup, usage, and maintenance.
- Sample project data for testing.

## 4. Constraints
- No online source fetching in offline mode.
- Max 10 GB RAM for graph processing.
- Local storage only, no iCloud.
- Support GraphML for graphs (or more compact format if feasible).
