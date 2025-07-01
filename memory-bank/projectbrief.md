# Project Brief: Glyph - Intelligent Knowledge Graph Explorer

## Core Mission
Transform research and learning by automatically creating knowledge graphs and personalized learning plans from any topic or source collection.

## Project Identity
- **Name**: Glyph (originally FlowGenius in PRD)
- **Platform**: macOS Sequoia 15.5+ native desktop application
- **Design Philosophy**: Curious, Focused, Insightful, Minimal, Intelligent, Empowering

## Problem Statement
Modern research is overwhelming and inefficient:
- Information overload across thousands of sources
- Hidden connections between concepts remain invisible
- Knowledge gaps are difficult to identify
- Bias and contradictory viewpoints go unnoticed
- No clear learning path from novice to expert

## Solution Approach
An intelligent research companion that:
1. **Analyzes sources** using advanced NLP and AI
2. **Maps relationships** through interactive knowledge graphs
3. **Creates learning paths** with structured curricula
4. **Identifies insights** including gaps, contradictions, and uncommon perspectives
5. **Operates locally** with full privacy and offline capability

## Success Criteria
- Handle graphs of 1,000 to 1,000,000 nodes efficiently (max 10GB RAM)
- Process multiple source formats (PDFs, text, URLs, folders)
- Generate comprehensive learning plans with practical applications
- Maintain native macOS look and feel with SwiftUI
- Provide real-time progress feedback during processing
- Ensure complete data privacy with local processing

## Core Value Propositions
1. **Time Savings**: Hours of manual research condensed into minutes
2. **Hidden Insights**: Discover connections that would otherwise be missed
3. **Structured Learning**: Clear path from curiosity to expertise
4. **Bias Awareness**: Identify gaps and contradictory perspectives
5. **Privacy First**: All processing happens locally on user's Mac

## Scope Boundaries
**In Scope**:
- Native macOS SwiftUI application
- Local file processing (PDFs, text, folders)
- Knowledge graph visualization and interaction
- Learning plan generation and export
- User authentication and project management
- Offline mode operation

**Out of Scope**:
- Web-based interface
- Real-time online source fetching (offline mode)
- Cloud storage or iCloud sync
- Mobile applications
- Multi-user collaboration features

## Key Constraints
- Maximum 10GB RAM usage for graph processing
- Local storage only, no cloud dependencies
- macOS Sequoia 15.5+ compatibility required
- Python 3.13.3 embedded environment
- App Sandbox disabled for PythonKit integration 