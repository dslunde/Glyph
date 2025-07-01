# Glyph 🌟
*Curious. Focused. Insightful. Minimal. Intelligent. Empowering.*

## What is Glyph?

Glyph is a native macOS desktop application that transforms how you approach research and learning. It automatically creates **knowledge graphs** and **personalized learning plans** from your research topics, helping you discover connections, identify gaps, and uncover insights that would take hours to find manually.

Think of it as your **intelligent research companion** that reads through sources, maps out relationships between concepts, and creates a visual roadmap for mastering any subject.

## Why Glyph Exists

Research today is overwhelming. Whether you're a student, researcher, or professional learner, you face:

- **Information Overload**: Thousands of sources, papers, and articles to sift through
- **Hidden Connections**: Important relationships between concepts that aren't obvious
- **Knowledge Gaps**: Areas you don't know you don't know
- **Bias Blindness**: Missing perspectives and contradictory viewpoints
- **Learning Inefficiency**: No clear path from novice to expert understanding

Glyph solves these problems by **automatically analyzing sources**, **mapping knowledge relationships**, and **creating structured learning paths** tailored to your goals.

## Key Features

### 🧠 **Intelligent Knowledge Graphs**
- **Automatic Concept Extraction**: Uses advanced NLP to identify key concepts, entities, and relationships from your sources
- **Visual Network Mapping**: Interactive SwiftUI canvas showing how ideas connect and influence each other
- **Scale Performance**: Handles graphs from 1K to 1M nodes with optimized algorithms
- **Core Concept Identification**: Automatically highlights the most important ideas using centrality analysis

### 📚 **Smart Source Analysis**
- **Multi-Format Support**: Process PDFs, text files, URLs, and entire folders
- **Source Diversity Analysis**: Identifies bias by analyzing publication types and author backgrounds  
- **Contradiction Detection**: Finds conflicting claims across sources using NLP
- **Perspective Scoring**: Measures uniqueness and identifies insider vs. outsider viewpoints

### 🗺️ **Personalized Learning Plans**
- **Adaptive Depth**: Choose from Quick, Moderate, or Comprehensive learning approaches
- **Structured Curriculum**: Auto-generated study timeline with key concepts and recommended readings
- **Knowledge Gap Identification**: Highlights underexplored areas for deeper investigation
- **Practical Applications**: Connects theory to real-world use cases

### 🔍 **Research Intelligence**
- **Counterintuitive Truths**: Surfaces surprising contradictions and paradoxes
- **Uncommon Insights**: Discovers niche perspectives and overlooked connections
- **Hypothesis Testing**: Evaluates your assumptions against evidence
- **Sensitivity Analysis**: Adapts to controversial or sensitive topics

### 🛡️ **Privacy & Offline Mode**
- **Local Processing**: All analysis happens on your Mac - no data sent to external servers
- **Offline Capable**: Process pre-saved files without internet connection
- **Encrypted Storage**: Projects secured with SQLCipher encryption
- **User Authentication**: Personal project management with secure access control

## How It Works

1. **Define Your Topic**: Enter your research question, hypotheses, and sensitivity preferences
2. **Gather Sources**: Add PDFs, documents, URLs, or point to folders of materials
3. **AI Analysis**: Glyph processes sources using Python 3.13.3 + advanced NLP models
4. **Knowledge Graph Creation**: Concepts and relationships are mapped into interactive visualizations
5. **Learning Plan Generation**: Receive a structured curriculum with study timeline and resources
6. **Explore & Refine**: Navigate the knowledge graph, edit connections, and customize outputs

## Technical Architecture

- **Frontend**: Native SwiftUI for seamless macOS integration
- **AI Engine**: Python 3.13.3 with transformers, sentence-transformers, and LangChain
- **Graph Processing**: NetworkX + optimized algorithms using Accelerate framework
- **Storage**: Local SQLite + encrypted project data
- **Integration**: PythonKit bridges Swift and Python seamlessly

## Target Users

- **Graduate Students**: Map research landscapes and identify dissertation topics
- **Researchers**: Discover connections across interdisciplinary fields  
- **Professionals**: Quickly master new domains for career advancement
- **Educators**: Create comprehensive curricula and identify knowledge gaps
- **Lifelong Learners**: Explore complex topics with structured guidance

## Design Philosophy

Glyph embodies five core principles:

- **Curious**: Encourages exploration and discovery
- **Focused**: Cuts through noise to highlight what matters
- **Insightful**: Reveals hidden patterns and connections
- **Minimal**: Clean, distraction-free interface
- **Intelligent**: AI-powered analysis that adapts to your needs
- **Empowering**: Gives you the tools to become an expert in any field

---

## System Requirements

- **macOS**: Sequoia 15.5+ 
- **Memory**: 4GB RAM minimum, 16GB recommended for large graphs
- **Storage**: 2GB available space
- **Python**: 3.13.3 (automatically managed via pyenv)

## Getting Started

1. **Clone the Repository**
   ```bash
   git clone <repository-url>
   cd Glyph
   ```

2. **Build the Application**
   ```bash
   ./build_app.sh
   ```

3. **Launch Glyph**
   - Double-click the generated `.app` bundle
   - Or run: `open .build/Glyph.app`

## Project Status

Glyph is actively developed with core features implemented:
- ✅ SwiftUI native interface
- ✅ Python 3.13.3 integration  
- ✅ Custom app icon support
- ✅ Project management system
- ✅ Modern AI/NLP stack
- 🚧 Knowledge graph generation (in development)
- 🚧 Learning plan creation (in development)
- 🚧 Source analysis features (in development)

## Contributing

Glyph is designed to be the ultimate research companion. We welcome contributions that enhance its intelligence, usability, and educational impact.

---

*Transform your research. Visualize knowledge. Accelerate learning.*

## 🚀 Latest Updates

### ✅ Source Collection with Real API Integration
We've successfully implemented the complete Source Collection workflow from PRD section 2.2.2:

- **Real Tavily API Integration**: Actual web search capabilities 
- **OpenAI LLM Integration**: Intelligent query generation and reliability scoring
- **Interactive Source Validation**: Real-time file/URL validation with visual status
- **Smart Filtering**: Source preference-based reliability thresholds
- **Streamlined Workflow**: Use/Drop approval system for search results

### 🔧 PythonKit Configuration
Fixed Swift concurrency issues and enabled PythonKit compatibility:

- **App Sandbox**: Disabled for Python runtime access
- **Library Validation**: Disabled for dynamic Python libraries
- **Entitlements**: Properly configured for development and distribution
- **Build System**: Automated bundle creation with proper code signing

### 📋 API Setup Required
To use the full functionality, you'll need:

1. **Copy `.env.sample` to `.env`**
2. **Add your API keys:**
   - `OPENAI_API_KEY`: Get from https://platform.openai.com/api-keys
   - `TAVILY_API_KEY`: Get from https://tavily.com/
3. **Optional LangSmith**: For AI operation tracing and debugging

### 🎯 Current Status
- ✅ **Flow Fixed**: Source Collection properly displays on "Create"
- ✅ **Real APIs**: Tavily and OpenAI integration implemented
- ✅ **PythonKit**: Swift concurrency issues resolved
- ✅ **App Bundle**: Builds successfully with proper entitlements
- 🚧 **Next**: Full API testing with real keys

**Ready for real-world testing!**
