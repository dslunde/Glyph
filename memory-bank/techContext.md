# Technical Context: Glyph Development Stack and Constraints

## Core Technology Stack

### Frontend Technologies
- **SwiftUI**: Native macOS UI framework
  - Version: Latest (macOS Sequoia 15.5+)
  - Purpose: All user interface components
  - Benefits: Native performance, macOS integration, future-proof

- **Swift 6.1.2**: Primary programming language
  - Package Manager: Swift Package Manager
  - Frameworks: SwiftUI, Foundation, Accelerate
  - Architecture: MVVM pattern with services

### AI/ML Backend
- **Python 3.13.3**: Embedded AI engine
  - Installation: pyenv-managed for consistent environment
  - Integration: PythonKit for Swift-Python bridge
  - Purpose: NLP, graph analysis, machine learning

### Key Python Libraries
```python
# Core AI & ML
torch==2.7.1                    # Deep learning framework
numpy==2.3.1                    # Numerical computing
scipy==1.14.1                   # Scientific computing
scikit-learn==1.7.0             # Machine learning algorithms

# Graph Analysis & Advanced Analytics
networkx==3.5                   # Graph theory and analysis (AI Insights)
openai>=1.0.0                   # OpenAI API for LLM enhancement (AI Insights)

# Modern NLP & Language Models
transformers>=4.53.0            # Hugging Face transformers
sentence-transformers>=2.2.0    # Sentence embeddings
langchain>=0.1.0               # LLM application framework
langchain-core>=0.1.0          # Core LangChain functionality
langchain-community>=0.0.10    # Community integrations
langsmith>=0.0.70              # LangChain monitoring
langgraph>=0.0.40              # LangChain workflow graphs

# Traditional NLP
nltk==3.9.1                    # Natural language toolkit
spacy==3.8.7                   # Industrial NLP
textstat==0.7.7                # Text statistics

# Data Processing
pandas>=2.1.0                  # Data manipulation
requests>=2.31.0               # HTTP library
python-dotenv>=1.0.0           # Environment variables
```

### Storage Technologies
- **SQLite**: Primary database
  - Enhancement: SQLCipher for encryption
  - Purpose: Project metadata, user data
  - Location: Local filesystem only

- **JSON/GraphML**: Graph serialization
  - JSON: API compatibility and debugging
  - GraphML: Standard graph exchange format
  - Purpose: Knowledge graph persistence

### Integration Layer
- **PythonKit**: Swift-Python bridge
  - Version: 0.3.1+
  - Purpose: Seamless Swift ↔ Python communication
  - Constraint: Requires App Sandbox to be disabled

## Development Environment

### System Requirements
- **macOS**: Sequoia 15.5+ (required for latest SwiftUI features)
- **Xcode**: 16.4+ with Swift 6.1.2 support
- **Python**: 3.13.3 via pyenv (consistent environment)
- **Hardware**: 8GB RAM minimum, 16GB recommended for large graphs
- **Architecture**: arm64 (Apple Silicon) recommended

### Development Setup
```bash
# 1. Python Environment Setup
pyenv install 3.13.3
pyenv local 3.13.3

# 2. Python Dependencies
pip install -r requirements.txt

# 3. Swift Package Resolution
swift package resolve

# 4. Build and Run
swift build --configuration release
./build_app.sh  # Creates macOS app bundle
```

### Project Structure
```
Glyph/
├── Package.swift              # Swift package configuration
├── requirements.txt           # Python dependencies
├── build_app.sh              # App bundle build script
├── Sources/
│   └── Glyph/
│       ├── App.swift         # Application entry point
│       ├── Models/           # Data structures
│       ├── ViewModels/       # Business logic
│       ├── Views/           # SwiftUI components
│       ├── Services/        # Core functionality
│       └── Resources/       # Assets, icons, data
├── Tests/                   # Test suites
└── memory-bank/            # Project documentation
```

## Technical Constraints

### Performance Constraints
- **Memory Limit**: Maximum 10GB RAM for graph processing
- **Graph Scale**: Support 1,000 to 1,000,000 nodes efficiently
- **Processing Time**: Real-time progress feedback required
- **Responsiveness**: UI must remain interactive during processing

### Platform Constraints
- **macOS Only**: No cross-platform requirements (focused native experience)
- **Local Processing**: No cloud dependencies or external APIs
- **Offline Mode**: Full functionality without internet connection
- **File System Access**: Needs broad file access for document processing

### Security Constraints
- **Data Privacy**: All processing local, no data transmission
- **Encryption**: SQLite databases must be encrypted
- **Authentication**: Local user authentication required
- **Sandboxing**: Limited due to PythonKit requirements

### Integration Constraints
- **Python Runtime**: Must embed Python 3.13.3 environment
- **Library Compatibility**: Python packages must support macOS
- **Memory Sharing**: Efficient data transfer between Swift and Python
- **Error Handling**: Graceful degradation when Python components fail

## Algorithm Implementation Strategy

### Swift vs Python Decision Matrix
| Operation Type | Implementation | Rationale |
|----------------|----------------|-----------|
| UI Updates | Swift | Native performance, direct SwiftUI integration |
| Graph Visualization | Swift | Real-time interaction, smooth animations |
| NLP Processing | Python | Mature libraries, research ecosystem |
| Graph Algorithms | Python (NetworkX) | Proven implementations, optimized C backend |
| Matrix Operations | Swift (Accelerate) | Native performance, GPU acceleration |
| File I/O | Swift | Native file system integration |
| Data Persistence | Swift | Core Data or SQLite integration |

### Performance Optimization Strategies
- **Lazy Loading**: Load data on demand to manage memory
- **Chunked Processing**: Process large datasets in batches
- **Caching**: Store expensive computations (embeddings, centrality)
- **Progressive Rendering**: Update UI incrementally during processing
- **Background Processing**: Use concurrent queues for non-UI operations

## Development Workflow

### Version Control
- **Git**: Primary version control system
- **GitHub Flow**: Branching strategy
- **Conventional Commits**: Commit message format

### Dependency Management
- **Swift Packages**: Native dependency resolution
- **Python Packages**: pip + requirements.txt with version constraints
- **Preference**: Flexible versions (>=) over exact pins (==) when possible

### Testing Strategy
- **Unit Tests**: XCTest for Swift components, pytest for Python
- **Integration Tests**: PythonKit bridge functionality
- **Performance Tests**: Memory usage and processing speed
- **UI Tests**: Critical user workflows

### Build and Deployment
- **Development Builds**: `swift build` for testing
- **App Bundles**: `build_app.sh` for distribution
- **Icon Integration**: Automated iconset generation and embedding
- **Code Signing**: macOS app distribution requirements

## Known Technical Challenges

### 1. Memory Management
- **Challenge**: Large graphs can exceed 10GB limit
- **Mitigation**: Sparse representations, progressive loading, user warnings

### 2. Python Integration
- **Challenge**: Swift-Python data marshalling overhead
- **Mitigation**: Minimize data transfers, use efficient serialization

### 3. App Store Distribution
- **Challenge**: App Sandbox restrictions conflict with PythonKit
- **Mitigation**: Direct distribution, clear documentation about requirements

### 4. Performance Scaling
- **Challenge**: Graph algorithms don't scale linearly
- **Mitigation**: Algorithm selection based on graph size, user feedback

## Future Technical Considerations

### Potential Enhancements
- **Metal Compute**: GPU acceleration for graph algorithms
- **Core ML**: On-device model inference for NLP tasks
- **CloudKit**: Optional cloud sync while maintaining local-first approach
- **Plugins**: Extensible architecture for custom analysis modules

### Technology Evolution
- **Swift Concurrency**: Adoption of async/await patterns
- **SwiftUI Updates**: Leverage new framework capabilities
- **Python Ecosystem**: Stay current with ML/NLP library evolution
- **macOS Features**: Integrate new system capabilities as available

### AI Insights System Dependencies
- **NetworkX 3.5**: Core graph analysis algorithms (centrality, clustering, community detection)
- **OpenAI API**: Optional LLM enhancement for deeper insights (fallback to graph-based analysis)
- **Advanced Analysis Module**: `advanced_analysis.py` with sophisticated graph algorithms
- **Analysis Data Models**: Comprehensive Swift models for all insight types 