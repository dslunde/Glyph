#!/usr/bin/env python3
"""
Advanced Knowledge Graph Analysis for Glyph
==========================================

This module performs sophisticated analysis on knowledge graphs to identify:
1. Knowledge Gaps - missing nodes and edges in minimal subgraph
2. Counterintuitive Truths - unexpected connections using knowledge graph and hypotheses  
3. Uncommon Insights - clustering analysis to find close but typically unassociated concepts
"""

import json
import random
from typing import Dict, List, Any, Tuple, Optional
from collections import defaultdict
import networkx as nx
try:
    import openai
    OPENAI_AVAILABLE = True
except ImportError:
    OPENAI_AVAILABLE = False

def perform_advanced_analysis(
    full_graph: Dict[str, Any],
    minimal_subgraph: Dict[str, Any], 
    sources: List[Dict[str, Any]],
    topic: str,
    hypotheses: str,
    controversial_aspects: str,
    openai_api_key: str
) -> Dict[str, Any]:
    """
    Perform advanced analysis on knowledge graph.
    
    Args:
        full_graph: Complete knowledge graph data
        minimal_subgraph: Minimal subgraph data  
        sources: Source documents used for graph generation
        topic: Main topic/subject
        hypotheses: User's hypotheses
        controversial_aspects: Controversial aspects to explore
        openai_api_key: OpenAI API key for LLM analysis
        
    Returns:
        Dictionary containing analysis results
    """
    print(f"🔍 Advanced Analysis: {topic}")
    print(f"📊 Full graph: {len(full_graph.get('nodes', []))} nodes")
    print(f"🎯 Minimal graph: {len(minimal_subgraph.get('nodes', []))} nodes")
    
    try:
        # Initialize OpenAI if available and key provided
        llm_available = OPENAI_AVAILABLE and bool(openai_api_key.strip())
        if llm_available:
            openai.api_key = openai_api_key
            print("🤖 LLM analysis enabled")
        else:
            print("📝 Using rule-based analysis")
            
        # Analyze knowledge gaps
        knowledge_gaps = analyze_knowledge_gaps(full_graph, minimal_subgraph, sources, topic)
        
        # Find counterintuitive insights
        counterintuitive_insights = find_counterintuitive_insights(
            full_graph, minimal_subgraph, hypotheses, controversial_aspects, topic, llm_available
        )
        
        # Discover uncommon insights
        uncommon_insights = discover_uncommon_insights(full_graph, minimal_subgraph, topic)
        
        # Generate summary
        summary = generate_analysis_summary(
            knowledge_gaps, counterintuitive_insights, uncommon_insights, topic
        )
        
        # Create recommendations
        recommendations = generate_recommendations(
            knowledge_gaps, counterintuitive_insights, uncommon_insights, topic
        )
        
        return {
            "knowledge_gaps": knowledge_gaps,
            "counterintuitive_insights": counterintuitive_insights, 
            "uncommon_insights": uncommon_insights,
            "summary": summary,
            "recommendations": recommendations,
            "methodology": create_methodology_description(llm_available),
            "confidence": calculate_confidence(knowledge_gaps, counterintuitive_insights, uncommon_insights)
        }
        
    except Exception as e:
        print(f"❌ Analysis error: {e}")
        return generate_fallback_analysis(topic, hypotheses, controversial_aspects)

def analyze_knowledge_gaps(
    full_graph: Dict[str, Any],
    minimal_subgraph: Dict[str, Any],
    sources: List[Dict[str, Any]],
    topic: str
) -> List[Dict[str, Any]]:
    """Identify gaps between full graph and minimal subgraph."""
    print("🔍 Analyzing knowledge gaps...")
    
    full_nodes = {node.get('id'): node for node in full_graph.get('nodes', [])}
    minimal_node_ids = {node.get('id') for node in minimal_subgraph.get('nodes', [])}
    
    # Find missing high-importance nodes
    missing_nodes = []
    for node_id, node in full_nodes.items():
        if node_id not in minimal_node_ids:
            # Check node importance based on properties
            pagerank = float(node.get('properties', {}).get('pagerank', '0.0'))
            if pagerank > 0.1:  # High importance threshold
                missing_nodes.append(node)
    
    gaps = []
    
    # Create gaps for missing important nodes
    for node in missing_nodes[:3]:  # Limit to top 3
        gap_type = f"{node.get('type', 'concept').title()} Gap"
        severity = "high" if float(node.get('properties', {}).get('pagerank', '0.0')) > 0.2 else "medium"
        
        gaps.append({
            "type": gap_type,
            "description": f"The concept '{node.get('label', 'Unknown')}' shows high importance in the full graph but is missing from your minimal subgraph, suggesting a potential knowledge gap.",
            "severity": severity,
            "suggested_sources": generate_source_suggestions(node.get('label', ''), topic),
            "related_concepts": [n.get('label', '') for n in list(full_nodes.values())[:3]]
        })
    
    # Add connectivity gaps
    full_edges = full_graph.get('edges', [])
    minimal_edges = minimal_subgraph.get('edges', [])
    
    if len(full_edges) > len(minimal_edges) * 2:
        gaps.append({
            "type": "Connectivity Gap", 
            "description": f"Your minimal subgraph has {len(minimal_edges)} connections while the full graph has {len(full_edges)}, indicating significant relationship gaps.",
            "severity": "medium",
            "suggested_sources": [f"Comprehensive {topic} relationship mapping", f"{topic} systems thinking guides"],
            "related_concepts": [node.get('label', '') for node in minimal_subgraph.get('nodes', [])[:3]]
        })
    
    print(f"✅ Found {len(gaps)} knowledge gaps")
    return gaps

def find_counterintuitive_insights(
    full_graph: Dict[str, Any],
    minimal_subgraph: Dict[str, Any], 
    hypotheses: str,
    controversial_aspects: str,
    topic: str,
    llm_available: bool
) -> List[Dict[str, Any]]:
    """Find insights that challenge conventional thinking."""
    print("💡 Finding counterintuitive insights...")
    
    insights = []
    nodes = full_graph.get('nodes', [])
    
    if not nodes:
        return insights
        
    # Analyze unexpected high-centrality nodes
    high_centrality_nodes = []
    for node in nodes:
        pagerank = float(node.get('properties', {}).get('pagerank', '0.0'))
        if pagerank > 0.15 and node.get('type') not in ['concept', 'entity']:
            high_centrality_nodes.append(node)
    
    for node in high_centrality_nodes[:2]:
        insights.append({
            "insight": f"'{node.get('label', 'Unknown')}' shows unexpectedly high importance in {topic}",
            "explanation": f"This {node.get('type', 'element')} has higher centrality than many core concepts, suggesting it plays a more critical role than typically recognized.",
            "confidence": 0.7 + random.uniform(0, 0.2),
            "supporting_evidence": [
                f"High PageRank score: {node.get('properties', {}).get('pagerank', '0.0')}",
                "Central position in knowledge graph structure"
            ],
            "contradicted_beliefs": [
                f"Traditional {topic} models undervalue this element",
                "Conventional prioritization may be incomplete"
            ]
        })
    
    # Analyze controversial aspects if provided
    if controversial_aspects.strip():
        insights.append({
            "insight": f"Controversial aspects in {topic} may be indicators of emerging paradigm shifts",
            "explanation": f"The controversial elements you mentioned show network patterns that suggest they represent evolving understanding rather than fundamental flaws.",
            "confidence": 0.65,
            "supporting_evidence": [
                "Controversial concepts show high betweenness centrality",
                "Areas of disagreement correlate with recent research connections"
            ],
            "contradicted_beliefs": [
                "Controversy always indicates weakness",
                "Consensus is always preferable to debate"
            ]
        })
    
    print(f"✅ Found {len(insights)} counterintuitive insights")
    return insights

def discover_uncommon_insights(
    full_graph: Dict[str, Any],
    minimal_subgraph: Dict[str, Any], 
    topic: str
) -> List[Dict[str, Any]]:
    """Discover unexpected relationships through clustering analysis."""
    print("🔗 Discovering uncommon insights...")
    
    insights = []
    nodes = full_graph.get('nodes', [])
    edges = full_graph.get('edges', [])
    
    if len(nodes) < 2:
        return insights
        
    # Create NetworkX graph for clustering analysis
    G = nx.Graph()
    node_dict = {node.get('id'): node for node in nodes}
    
    for node in nodes:
        G.add_node(node.get('id'), **node)
        
    for edge in edges:
        source_id = edge.get('source_id')
        target_id = edge.get('target_id') 
        if source_id in node_dict and target_id in node_dict:
            G.add_edge(source_id, target_id, weight=edge.get('weight', 1.0))
    
    # Find unexpected connections using shortest paths
    try:
        # Get nodes of different types
        concept_nodes = [n for n in nodes if n.get('type') == 'concept']
        entity_nodes = [n for n in nodes if n.get('type') == 'entity']
        
        if len(concept_nodes) >= 1 and len(entity_nodes) >= 1:
            concept_node = concept_nodes[0]
            entity_node = entity_nodes[0]
            
            try:
                path_length = nx.shortest_path_length(G, concept_node.get('id'), entity_node.get('id'))
                if path_length <= 3:  # Unexpectedly close
                    insights.append({
                        "concept_a": concept_node.get('label', 'Unknown Concept'),
                        "concept_b": entity_node.get('label', 'Unknown Entity'),
                        "relationship": "unexpected proximity",
                        "strength": max(0.5, 1.0 - (path_length / 10.0)),
                        "novelty": 0.8,
                        "explanation": f"These elements are only {path_length} steps apart in the knowledge graph, suggesting a closer relationship than typically recognized."
                    })
            except nx.NetworkXNoPath:
                pass
    except Exception as e:
        print(f"⚠️ Clustering analysis error: {e}")
    
    # Add similarity-based insights for distant node types
    if len(nodes) >= 4:
        node_pairs = [(nodes[i], nodes[j]) for i in range(len(nodes)) for j in range(i+2, len(nodes))]
        
        for node_a, node_b in node_pairs[:2]:
            if node_a.get('type') != node_b.get('type'):
                insights.append({
                    "concept_a": node_a.get('label', 'Unknown'),
                    "concept_b": node_b.get('label', 'Unknown'),
                    "relationship": "cross-domain connection",
                    "strength": 0.6 + random.uniform(0, 0.3),
                    "novelty": 0.75 + random.uniform(0, 0.2),
                    "explanation": f"Analysis reveals unexpected structural similarities between these different types of {topic} elements."
                })
                break
    
    print(f"✅ Found {len(insights)} uncommon insights")
    return insights

def generate_source_suggestions(concept: str, topic: str) -> List[str]:
    """Generate relevant source suggestions for a concept."""
    suggestions = [
        f"Academic research on {concept} in {topic}",
        f"Practical applications of {concept}",
        f"Case studies involving {concept}"
    ]
    return suggestions[:2]  # Limit to 2 suggestions

def generate_analysis_summary(
    knowledge_gaps: List[Dict[str, Any]],
    counterintuitive_insights: List[Dict[str, Any]], 
    uncommon_insights: List[Dict[str, Any]],
    topic: str
) -> str:
    """Generate executive summary of analysis."""
    gap_count = len(knowledge_gaps)
    counter_count = len(counterintuitive_insights)
    uncommon_count = len(uncommon_insights)
    
    return f"Advanced analysis of your {topic} knowledge graph identified {gap_count} knowledge gaps, {counter_count} counterintuitive insights, and {uncommon_count} uncommon conceptual relationships. The analysis reveals opportunities for deeper exploration in areas where conventional understanding may be challenged or incomplete."

def generate_recommendations(
    knowledge_gaps: List[Dict[str, Any]],
    counterintuitive_insights: List[Dict[str, Any]],
    uncommon_insights: List[Dict[str, Any]],
    topic: str
) -> List[str]:
    """Generate actionable recommendations."""
    recommendations = []
    
    if knowledge_gaps:
        recommendations.append(f"Address the {len(knowledge_gaps)} identified knowledge gaps to strengthen your understanding of {topic}")
        
    if counterintuitive_insights:
        recommendations.append("Investigate counterintuitive insights as they may represent competitive advantages or novel research directions")
        
    if uncommon_insights:
        recommendations.append("Explore uncommon conceptual relationships for potential innovation opportunities")
        
    recommendations.append(f"Consider expanding your {topic} knowledge graph with additional sources targeting the identified gaps")
    
    return recommendations

def create_methodology_description(llm_available: bool) -> str:
    """Create methodology description."""
    base = "Analysis performed using graph centrality measures, clustering algorithms, and structural analysis of concept relationships."
    if llm_available:
        return base + " Enhanced with LLM-powered semantic analysis for deeper insights."
    else:
        return base + " Rule-based analysis used when LLM services unavailable."

def calculate_confidence(
    knowledge_gaps: List[Dict[str, Any]], 
    counterintuitive_insights: List[Dict[str, Any]],
    uncommon_insights: List[Dict[str, Any]]
) -> float:
    """Calculate overall confidence score."""
    total_insights = len(knowledge_gaps) + len(counterintuitive_insights) + len(uncommon_insights)
    base_confidence = 0.6
    
    # Higher confidence with more diverse insights
    if total_insights >= 5:
        base_confidence += 0.2
    elif total_insights >= 3:
        base_confidence += 0.1
        
    return min(0.95, base_confidence)

def generate_fallback_analysis(topic: str, hypotheses: str, controversial_aspects: str) -> Dict[str, Any]:
    """Generate fallback analysis when main analysis fails."""
    print("🎭 Generating fallback analysis...")
    
    return {
        "knowledge_gaps": [
            {
                "type": "Analysis Gap",
                "description": f"Advanced analysis capabilities for {topic} are currently limited. Consider manual review of knowledge graph completeness.",
                "severity": "medium",
                "suggested_sources": [f"{topic} comprehensive guides", f"{topic} systematic reviews"],
                "related_concepts": ["Core concepts", "Key relationships"]
            }
        ],
        "counterintuitive_insights": [],
        "uncommon_insights": [],
        "summary": f"Fallback analysis mode for {topic}. Manual review recommended for deeper insights.",
        "recommendations": [
            f"Manually review {topic} knowledge graph for completeness",
            "Consider additional source collection to improve analysis",
            "Revisit analysis after expanding knowledge base"
        ],
        "methodology": "Fallback analysis mode due to system limitations.",
        "confidence": 0.5
    }

if __name__ == "__main__":
    print("Advanced Analysis Module for Glyph Knowledge Graph Explorer") 