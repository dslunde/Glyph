# System Patterns: Glyph Architecture and Design Decisions

## High-Level Architecture

### Hybrid Native-AI Architecture
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   SwiftUI       │    │   PythonKit     │    │   Python AI     │
│   Frontend      │◄──►│   Bridge        │◄──►│   Engine        │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Local SQLite  │    │   Project       │    │   NLP Models    │
│   Storage       │    │   Management    │    │   & Libraries   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Core Design Patterns

#### Model-View-ViewModel (MVVM)
- **Views**: SwiftUI components for interface
- **ViewModels**: Business logic and state management
- **Models**: Data structures (Project, GraphNode, GraphEdge)
- **Services**: Abstracted functionality (Python integration, persistence)

#### Service Layer Pattern
- **PythonGraphService**: AI/ML processing bridge
- **PersistenceService**: Data storage and retrieval
- **ProjectManager**: Project lifecycle management
- **Authentication Service**: User access control (planned)

#### Bridge Pattern
- **PythonKit Integration**: Swift ↔ Python communication
- **Abstract graph operations** from implementation details
- **Fallback mechanisms** for Swift vs Python algorithms

## Key Technical Decisions

### 1. Native macOS with SwiftUI
**Decision**: Use SwiftUI for the entire frontend
**Rationale**: 
- Native performance and integration
- Access to macOS-specific features (Keychain, file system)
- Consistent with design philosophy (Minimal, Intelligent)
- Future-proof with Apple's UI framework evolution

### 2. Python 3.13.3 Integration via PythonKit
**Decision**: Embed Python runtime for AI/ML processing
**Rationale**:
- Access to mature NLP/ML ecosystem (transformers, NetworkX, etc.)
- Avoid reimplementing complex algorithms in Swift
- Leverage existing research and community libraries
- Maintain performance for computationally intensive tasks

### 3. Local-First Architecture
**Decision**: All processing happens locally, no cloud dependencies
**Rationale**:
- Privacy and security (sensitive research data)
- Offline capability (essential for research scenarios)
- No subscription/API costs for users
- Full user control over data

### 4. Hybrid Graph Processing
**Decision**: Use both Swift (UI interactions) and Python (analysis) for graphs
**Rationale**:
- Swift: Fast UI updates, native performance for visualization
- Python: Access to NetworkX, scikit-learn, advanced algorithms
- Best of both worlds for different use cases

## Component Relationships

### Data Flow Architecture
```
User Input → SwiftUI → ViewModel → Service Layer → Python Engine
    ↑                                    ↓              ↓
    └── Results ← UI Updates ← State ← Processing ← Analysis
```

### Service Dependencies
- **ProjectManager** depends on PersistenceService
- **SwiftUI Views** depend on ViewModels and ProjectManager
- **PythonGraphService** is independent (single responsibility)
- **ViewModels** orchestrate services but don't directly depend on each other

## Performance Patterns

### Memory Management
- **Lazy Loading**: Load projects and graphs on demand
- **Sparse Representation**: Use efficient data structures for large graphs
- **Progressive Rendering**: Display graph incrementally as it loads
- **Memory Monitoring**: Track RAM usage, warn before 10GB limit

### Algorithmic Efficiency
- **Accelerate Framework**: Use for matrix operations in Swift
- **NetworkX Optimization**: Leverage optimized C implementations
- **Batch Processing**: Process sources in chunks to manage memory
- **Caching Strategy**: Cache expensive computations (embeddings, centrality)

## Error Handling Patterns

### Graceful Degradation
- **Python Import Failures**: Fall back to basic graph operations
- **Large Graph Handling**: Warn user, offer simplified processing
- **File Processing Errors**: Continue with successful sources, report failures

### User Communication
- **Progress Indicators**: Real-time feedback for long operations
- **Error Messages**: Clear, actionable explanations
- **Fallback Options**: Alternative approaches when primary fails

## Security Patterns

### Data Protection
- **Local Storage**: SQLite with SQLCipher encryption
- **Keychain Integration**: Secure credential storage
- **No Network Communication**: Eliminate remote attack vectors
- **File System Isolation**: Respect macOS sandboxing where possible

### Input Validation
- **File Type Checking**: Validate document formats before processing
- **Size Limits**: Prevent memory exhaustion attacks
- **Path Traversal Protection**: Secure file access patterns

## Extensibility Patterns

### Plugin Architecture (Future)
- **Python Module System**: Load custom analysis modules
- **Swift Protocol Extensions**: Extend graph visualization
- **Export Format Plugins**: Support additional output formats

### Configuration Management
- **User Preferences**: Persistent settings for behavior customization
- **Algorithm Selection**: Choose between Swift/Python implementations
- **Performance Tuning**: Adjust processing parameters based on hardware

## Testing Patterns

### Unit Testing Strategy
- **Swift Components**: XCTest for ViewModels and Services
- **Python Components**: pytest for graph algorithms
- **Integration Points**: Test PythonKit bridge thoroughly
- **Mock Services**: Abstract external dependencies

### Performance Testing
- **Memory Usage**: Automated testing with large graphs
- **Processing Speed**: Benchmark key algorithms
- **UI Responsiveness**: Measure frame rates during graph interactions

## Development Patterns

### Code Organization
```
Sources/
├── Glyph/
│   ├── App.swift              # Entry point
│   ├── Models/                # Data structures
│   ├── ViewModels/           # Business logic
│   ├── Views/                # SwiftUI components
│   ├── Services/             # Core functionality
│   └── Resources/            # Assets and data
└── Tests/                    # Test suites
```

### Dependency Management
- **Swift Package Manager**: Native dependency management
- **requirements.txt**: Python package specifications
- **Version Pinning**: Stable versions for production, flexible for development
- **Conflict Resolution**: Prefer packages without exact version constraints 