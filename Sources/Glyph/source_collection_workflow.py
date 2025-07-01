#!/usr/bin/env python3
"""
LangGraph Source Collection Workflow for Glyph
==============================================

This module implements a LangGraph-based workflow for orchestrating the source
collection process. It replaces the sequential orchestration with a proper
state machine that can handle complex flows, error recovery, and branching logic.

Workflow States:
- initialize: Setup and validation
- generate_queries: Create search queries using LLM
- search_sources: Find sources using Tavily API
- score_reliability: Evaluate source reliability
- filter_results: Apply user preferences and thresholds
- stream_results: Return results to user
- handle_errors: Error recovery and fallbacks

Features:
- State-based orchestration with LangGraph
- Automatic error handling and recovery
- Branching logic based on user preferences
- Real-time progress tracking
- Comprehensive LangSmith tracing
"""

import os
import sys
import json
import asyncio
from typing import List, Dict, Any, Optional, TypedDict, Annotated
from datetime import datetime

# LangGraph imports
try:
    from langgraph.graph import StateGraph, END
    from langgraph.graph.message import add_messages
    from langchain_core.messages import BaseMessage, HumanMessage, AIMessage
    LANGGRAPH_AVAILABLE = True
    print("✅ LangGraph available")
except ImportError:
    print("❌ LangGraph not available - install with: pip install langgraph")
    LANGGRAPH_AVAILABLE = False

# LangSmith tracing
try:
    from langsmith import traceable  # type: ignore[assignment]
    LANGSMITH_AVAILABLE = True
    print("✅ LangSmith tracing available")
except ImportError:
    print("⚠️ LangSmith not available - operations will not be traced")
    LANGSMITH_AVAILABLE = False
    from typing import Callable, TypeVar
    
    F = TypeVar('F', bound=Callable[..., Any])
    
    def traceable(name: Optional[str] = None):  # type: ignore[misc]
        """Fallback traceable decorator when LangSmith is not available.
        
        Args:
            name: Optional name for the traced function (ignored in fallback).
            
        Returns:
            Decorator function that returns the original function unchanged.
        """
        def decorator(func: F) -> F:
            return func
        return decorator

# API integrations
try:
    import openai
    OPENAI_AVAILABLE = True
    print("✅ OpenAI module available")
except ImportError:
    print("❌ OpenAI module not available")
    OPENAI_AVAILABLE = False

try:
    from tavily import TavilyClient
    TAVILY_AVAILABLE = True
    print("✅ Tavily module available")
except ImportError:
    print("❌ Tavily module not available")
    TAVILY_AVAILABLE = False

# Environment setup
try:
    from dotenv import load_dotenv
    load_dotenv()
    print("✅ Environment variables loaded")
except ImportError:
    print("⚠️ python-dotenv not available - using system environment only")

# Import our existing API functions
sys.path.append(os.path.dirname(os.path.abspath(__file__)))


# MARK: - State Definition

class SourceCollectionState(TypedDict):
    """State object that flows through the LangGraph workflow"""
    # Input parameters
    topic: str
    search_limit: int
    reliability_threshold: float
    source_preferences: List[str]
    api_keys: Dict[str, str]
    
    # Workflow state
    current_step: str
    progress: float
    error_count: int
    retry_count: int
    
    # Generated data
    search_queries: List[str]
    raw_results: List[Dict[str, Any]]
    scored_results: List[Dict[str, Any]]
    filtered_results: List[Dict[str, Any]]
    
    # Messages for LangSmith tracing
    messages: Annotated[List[BaseMessage], add_messages]
    
    # Metadata
    run_id: Optional[str]
    start_time: Optional[datetime]
    step_timings: Dict[str, float]
    
    # Final outputs
    success: bool
    final_results: List[Dict[str, Any]]
    error_message: Optional[str]


# MARK: - Workflow Nodes

@traceable(name="initialize_workflow")
def initialize_node(state: SourceCollectionState) -> SourceCollectionState:
    """Initialize the workflow and validate inputs.
    
    Args:
        state: The current workflow state containing input parameters and configuration.
        
    Returns:
        Updated state with initialization data, validation results, and setup metadata.
        
    Note:
        Sets up initial workflow state, validates API keys, and prepares tracing messages.
    """
    print(f"🚀 Initializing source collection for topic: '{state['topic']}'")
    
    # Update state
    state["current_step"] = "initialize"
    state["progress"] = 0.1
    state["start_time"] = datetime.now()
    state["step_timings"] = {}
    state["error_count"] = 0
    state["retry_count"] = 0
    
    # Validate API keys
    api_keys_valid = {}
    for key_name in ["OPENAI_API_KEY", "TAVILY_API_KEY"]:
        key_value = state["api_keys"].get(key_name, "")
        api_keys_valid[key_name] = bool(key_value and key_value != "demo-key")
    
    # Add initialization message
    init_message = HumanMessage(
        content=f"Starting source collection workflow for topic: {state['topic']}"
    )
    state["messages"] = [init_message]
    
    print(f"📊 API Key validation: {api_keys_valid}")
    print(f"🎯 Search parameters: limit={state['search_limit']}, threshold={state['reliability_threshold']}%")
    print(f"🎨 Source preferences: {state['source_preferences']}")
    
    return state


@traceable(name="generate_search_queries")
def generate_queries_node(state: SourceCollectionState) -> SourceCollectionState:
    """Generate search queries using OpenAI LLM"""
    print("🤖 Generating search queries...")
    
    step_start = datetime.now()
    state["current_step"] = "generate_queries"
    state["progress"] = 0.2
    
    try:
        if not OPENAI_AVAILABLE:
            raise Exception("OpenAI module not available")
        
        openai_key = state["api_keys"].get("OPENAI_API_KEY", "")
        if not openai_key or openai_key == "demo-key":
            raise Exception("Invalid OpenAI API key")
        
        client = openai.OpenAI(api_key=openai_key)
        
        # Create focused prompt based on source preferences
        source_context = ""
        if "reliable" in state["source_preferences"]:
            source_context += "Focus on academic, government, and authoritative sources. "
        if "unreliable" in state["source_preferences"]:
            source_context += "Include alternative perspectives and non-mainstream sources. "
        if "insider" in state["source_preferences"]:
            source_context += "Look for expert opinions and industry insider knowledge. "
        if "outsider" in state["source_preferences"]:
            source_context += "Include external critiques and independent analysis. "
        
        prompt = f"""Generate 5 specific, focused search queries for researching: {state['topic']}

{source_context}

The queries should be:
1. Comprehensive yet specific
2. Cover different aspects and perspectives
3. Suitable for academic and web search
4. Written in natural language

Cover these areas:
1. Fundamental concepts and definitions
2. Recent developments and research (2024)
3. Expert opinions and analysis
4. Practical applications and case studies
5. Controversies and different perspectives

Return only the queries, one per line, without numbering."""
        
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[{"role": "user", "content": prompt}],
            temperature=0.7,
            max_tokens=500,
            timeout=30
        )
        
        content = response.choices[0].message.content or ""
        queries = [q.strip() for q in content.split('\n') if q.strip()]
        
        # Ensure we have exactly 5 queries
        if len(queries) < 5:
            fallback_queries = [
                f"{state['topic']} fundamentals and basic concepts",
                f"{state['topic']} latest research and developments 2024",
                f"{state['topic']} expert opinions and analysis",
                f"{state['topic']} practical applications and case studies",
                f"{state['topic']} controversies and different perspectives"
            ]
            queries.extend(fallback_queries[len(queries):])
        elif len(queries) > 5:
            queries = queries[:5]
        
        state["search_queries"] = queries
        
        # Add success message
        success_message = AIMessage(
            content=f"Generated {len(queries)} search queries successfully"
        )
        state["messages"].append(success_message)
        
        print(f"✅ Generated {len(queries)} queries:")
        for i, query in enumerate(queries, 1):
            print(f"   {i}. {query}")
            
    except Exception as e:
        print(f"❌ Query generation failed: {e}")
        state["error_count"] += 1
        
        # Use fallback queries
        state["search_queries"] = [
            f"{state['topic']} fundamentals and basic concepts",
            f"{state['topic']} latest research and developments 2024",
            f"{state['topic']} expert opinions and analysis",
            f"{state['topic']} practical applications and case studies",
            f"{state['topic']} controversies and different perspectives"
        ]
        
        error_message = AIMessage(
            content=f"Query generation failed, using fallback queries: {str(e)}"
        )
        state["messages"].append(error_message)
    
    # Record timing
    duration = (datetime.now() - step_start).total_seconds()
    state["step_timings"]["generate_queries"] = duration
    
    return state


@traceable(name="search_with_tavily")
def search_sources_node(state: SourceCollectionState) -> SourceCollectionState:
    """Search for sources using Tavily API"""
    print(f"🔍 Searching with {len(state['search_queries'])} queries...")
    
    step_start = datetime.now()
    state["current_step"] = "search_sources"
    state["progress"] = 0.4
    
    all_results = []
    
    try:
        if not TAVILY_AVAILABLE:
            raise Exception("Tavily module not available")
        
        tavily_key = state["api_keys"].get("TAVILY_API_KEY", "")
        if not tavily_key or tavily_key == "demo-key":
            raise Exception("Invalid Tavily API key")
        
        client = TavilyClient(api_key=tavily_key)
        
        for i, query in enumerate(state["search_queries"]):
            print(f"   🔍 Query {i+1}/{len(state['search_queries'])}: {query[:50]}...")
            
            try:
                search_results = client.search(
                    query=query,
                    search_depth="advanced",
                    max_results=state["search_limit"],
                    include_answer=True,
                    include_raw_content=True
                )
                
                # Process results
                for result in search_results.get("results", []):
                    processed_result = {
                        "title": result.get("title", ""),
                        "url": result.get("url", ""),
                        "content": result.get("content", ""),
                        "score": result.get("score", 0.0),
                        "published_date": result.get("published_date", ""),
                        "query": query,
                        "reliability_score": None  # Will be filled in next step
                    }
                    all_results.append(processed_result)
                    
            except Exception as e:
                print(f"   ❌ Query '{query[:30]}...' failed: {e}")
                state["error_count"] += 1
                continue
        
        state["raw_results"] = all_results
        
        success_message = AIMessage(
            content=f"Found {len(all_results)} results from Tavily search"
        )
        state["messages"].append(success_message)
        
        print(f"✅ Found {len(all_results)} total results")
        
    except Exception as e:
        print(f"❌ Search failed: {e}")
        state["error_count"] += 1
        
        # Generate fallback results
        state["raw_results"] = generate_fallback_search_results(
            state["search_queries"], 
            state["search_limit"]
        )
        
        error_message = AIMessage(
            content=f"Search failed, using fallback results: {str(e)}"
        )
        state["messages"].append(error_message)
    
    # Record timing
    duration = (datetime.now() - step_start).total_seconds()
    state["step_timings"]["search_sources"] = duration
    
    return state


@traceable(name="score_source_reliability")
def score_reliability_node(state: SourceCollectionState) -> SourceCollectionState:
    """Score the reliability of each source using LLM"""
    print(f"🎯 Scoring reliability for {len(state['raw_results'])} results...")
    
    step_start = datetime.now()
    state["current_step"] = "score_reliability"
    state["progress"] = 0.6
    
    scored_results = []
    
    try:
        if not OPENAI_AVAILABLE:
            raise Exception("OpenAI module not available")
        
        openai_key = state["api_keys"].get("OPENAI_API_KEY", "")
        if not openai_key or openai_key == "demo-key":
            raise Exception("Invalid OpenAI API key")
        
        client = openai.OpenAI(api_key=openai_key)
        
        for i, result in enumerate(state["raw_results"]):
            if i % 5 == 0:  # Progress update every 5 results
                print(f"   📊 Scoring {i+1}/{len(state['raw_results'])}...")
            
            try:
                title = result.get("title", "")
                url = result.get("url", "")
                content = result.get("content", "")[:500]  # Limit content
                
                prompt = f"""Score the reliability of this source on a scale of 0-100:

Title: {title}
URL: {url}
Content preview: {content}

Consider:
- Domain authority (.edu, .gov, .org vs .com)
- Content quality and depth
- Presence of citations or references
- Potential bias indicators
- Recency and relevance

Source preferences: {state['source_preferences']}

Return only a number between 0-100."""
                
                response = client.chat.completions.create(
                    model="gpt-4o-mini",
                    messages=[{"role": "user", "content": prompt}],
                    temperature=0.3,
                    max_tokens=10,
                    timeout=15
                )
                
                try:
                    content = response.choices[0].message.content or "50"
                    score = int(content.strip())
                    score = max(0, min(100, score))  # Clamp to 0-100
                except (ValueError, AttributeError):
                    score = generate_domain_score(url)  # Fallback scoring
                
                result_copy = result.copy()
                result_copy["reliability_score"] = score
                scored_results.append(result_copy)
                
            except Exception as e:
                print(f"   ⚠️ Scoring failed for result {i+1}: {e}")
                # Use fallback scoring
                result_copy = result.copy()
                result_copy["reliability_score"] = generate_domain_score(result.get("url", ""))
                scored_results.append(result_copy)
                state["error_count"] += 1
        
        state["scored_results"] = scored_results
        
        success_message = AIMessage(
            content=f"Scored reliability for {len(scored_results)} results"
        )
        state["messages"].append(success_message)
        
        print(f"✅ Scored {len(scored_results)} results")
        
    except Exception as e:
        print(f"❌ Reliability scoring failed: {e}")
        state["error_count"] += 1
        
        # Use fallback scoring for all results
        for result in state["raw_results"]:
            result_copy = result.copy()
            result_copy["reliability_score"] = generate_domain_score(result.get("url", ""))
            scored_results.append(result_copy)
        
        state["scored_results"] = scored_results
        
        error_message = AIMessage(
            content=f"Reliability scoring failed, using fallback: {str(e)}"
        )
        state["messages"].append(error_message)
    
    # Record timing
    duration = (datetime.now() - step_start).total_seconds()
    state["step_timings"]["score_reliability"] = duration
    
    return state


@traceable(name="filter_by_preferences")
def filter_results_node(state: SourceCollectionState) -> SourceCollectionState:
    """Filter results based on user preferences and reliability threshold"""
    print(f"🔬 Filtering {len(state['scored_results'])} results...")
    
    step_start = datetime.now()
    state["current_step"] = "filter_results"
    state["progress"] = 0.8
    
    # Determine filtering logic based on source preferences
    has_reliable = "reliable" in state["source_preferences"]
    has_unreliable = "unreliable" in state["source_preferences"]
    
    if has_reliable and not has_unreliable:
        threshold = 60.0  # >= 60%
        filter_func = lambda score: score >= threshold
    elif not has_reliable and has_unreliable:
        threshold = 40.0  # <= 40%
        filter_func = lambda score: score <= threshold
    else:
        # Both or neither - accept if >= 60% or <= 40%
        filter_func = lambda score: score >= 60.0 or score <= 40.0
    
    filtered_results = []
    for result in state["scored_results"]:
        reliability_score = result.get("reliability_score", 50)
        
        if filter_func(reliability_score):
            filtered_results.append(result)
    
    state["filtered_results"] = filtered_results
    
    # Sort by reliability score (descending)
    state["filtered_results"].sort(
        key=lambda x: x.get("reliability_score", 0), 
        reverse=True
    )
    
    filter_message = AIMessage(
        content=f"Filtered to {len(filtered_results)} results based on preferences"
    )
    state["messages"].append(filter_message)
    
    print(f"✅ Filtered to {len(filtered_results)} results")
    if filtered_results:
        print(f"   📊 Score range: {filtered_results[-1]['reliability_score']}% - {filtered_results[0]['reliability_score']}%")
    
    # Record timing
    duration = (datetime.now() - step_start).total_seconds()
    state["step_timings"]["filter_results"] = duration
    
    return state


@traceable(name="finalize_results")
def finalize_node(state: SourceCollectionState) -> SourceCollectionState:
    """Finalize the workflow and prepare results for return"""
    print("🎉 Finalizing workflow...")
    
    state["current_step"] = "finalize"
    state["progress"] = 1.0
    state["success"] = True
    state["final_results"] = state["filtered_results"]
    
    # Calculate total duration
    if state["start_time"]:
        total_duration = (datetime.now() - state["start_time"]).total_seconds()
        state["step_timings"]["total"] = total_duration
    
    final_message = AIMessage(
        content=f"Workflow completed successfully with {len(state['final_results'])} results"
    )
    state["messages"].append(final_message)
    
    print(f"✅ Workflow completed successfully!")
    print(f"   📊 Final results: {len(state['final_results'])}")
    print(f"   ⏱️  Total duration: {state['step_timings'].get('total', 0):.2f}s")
    print(f"   ⚠️  Errors encountered: {state['error_count']}")
    
    return state


@traceable(name="handle_workflow_error")
def error_handler_node(state: SourceCollectionState) -> SourceCollectionState:
    """Handle errors and determine recovery strategy"""
    print("❌ Handling workflow error...")
    
    state["current_step"] = "error_handler"
    state["retry_count"] += 1
    
    # If we have partial results, try to continue
    if state["filtered_results"] and len(state["filtered_results"]) > 0:
        print("🔄 Partial results available, continuing with fallback...")
        state["success"] = True
        state["final_results"] = state["filtered_results"]
        state["error_message"] = f"Completed with {state['error_count']} errors but partial results available"
    else:
        print("💥 No usable results, workflow failed")
        state["success"] = False
        state["final_results"] = []
        state["error_message"] = f"Workflow failed after {state['error_count']} errors"
    
    error_message = AIMessage(
        content=f"Error handling: {state['error_message']}"
    )
    state["messages"].append(error_message)
    
    return state


# MARK: - Workflow Routing Logic

def should_continue(state: SourceCollectionState) -> str:
    """Determine the next step in the LangGraph workflow based on current state.
    
    This function implements the routing logic for the source collection workflow.
    It examines the current step and error count to decide whether to proceed to
    the next step, handle errors, or terminate the workflow.
    
    Args:
        state: Current workflow state containing step information and data.
        
    Returns:
        String indicating the next workflow node to execute:
        - "generate_queries": Move to query generation
        - "search_sources": Move to source search
        - "score_reliability": Move to reliability scoring
        - "filter_results": Move to result filtering
        - "finalize": Move to result finalization
        - "error_handler": Move to error handling
        - END: Terminate the workflow
        
    Note:
        This function implements fail-fast behavior by routing to error_handler
        when too many errors occur (>10) or when expected data is missing.
    """
    current_step: str = state["current_step"]
    error_count: int = state["error_count"]
    
    # Check for too many errors - fail-fast behavior
    if error_count > 10:
        return "error_handler"
    
    # Normal workflow progression with validation
    if current_step == "initialize":
        return "generate_queries"
    elif current_step == "generate_queries":
        if state["search_queries"]:
            return "search_sources"
        else:
            return "error_handler"
    elif current_step == "search_sources":
        if state["raw_results"]:
            return "score_reliability"
        else:
            return "error_handler"
    elif current_step == "score_reliability":
        if state["scored_results"]:
            return "filter_results"
        else:
            return "error_handler"
    elif current_step == "filter_results":
        return "finalize"
    elif current_step == "finalize":
        return END
    elif current_step == "error_handler":
        return END
    
    return END


# MARK: - Helper Functions

def generate_domain_score(url: str) -> int:
    """Generate reliability score based on domain authority.
    
    This function analyzes the URL's domain to assign a reliability score based on
    common domain authority patterns. Academic and government domains receive higher
    scores, while commercial domains receive more variable scores.
    
    Args:
        url: The URL to analyze for domain authority.
        
    Returns:
        Reliability score between 0-100, where higher scores indicate more reliable domains.
        
    Examples:
        >>> generate_domain_score("https://stanford.edu/research")
        85  # Academic domain gets high score
        >>> generate_domain_score("https://example.com/blog")
        55  # Commercial domain gets moderate score
    """
    import random
    url_lower = url.lower()
    
    if "edu" in url_lower or "gov" in url_lower:
        return random.randint(75, 90)
    elif "org" in url_lower:
        return random.randint(60, 80)
    elif any(domain in url_lower for domain in ["wikipedia", "scholar", "nature", "science"]):
        return random.randint(80, 95)
    elif "com" in url_lower or "net" in url_lower:
        return random.randint(40, 70)
    else:
        return random.randint(50, 75)


def generate_fallback_search_results(queries: List[str], limit: int) -> List[Dict[str, Any]]:
    """Generate fallback search results when Tavily API is unavailable.
    
    This function creates mock search results that maintain the expected data structure
    when the real Tavily API is unavailable. This ensures the workflow can continue
    with sample data for testing and demo purposes.
    
    Args:
        queries: List of search queries to generate results for.
        limit: Maximum number of results to generate across all queries.
        
    Returns:
        List of dictionaries containing mock search results with required fields:
        - title: Article title
        - url: Mock URL
        - content: Sample content
        - score: Simulated relevance score
        - published_date: Mock publication date
        - query: Original search query
        - reliability_score: Initially None, to be filled by scoring step
        
    Note:
        This is a fallback function used when real API calls fail. The generated
        data follows the same structure as real Tavily results.
    """
    results: List[Dict[str, Any]] = []
    for i, query in enumerate(queries[:limit]):
        result: Dict[str, Any] = {
            "title": f"Research on {query}",
            "url": f"https://example.com/article{i + 1}",
            "content": f"Comprehensive analysis of {query} with detailed findings.",
            "score": 0.7 + (i * 0.05),
            "published_date": f"2024-01-{15 + i}",
            "query": query,
            "reliability_score": None
        }
        results.append(result)
    return results


# MARK: - Workflow Definition

def create_source_collection_workflow() -> StateGraph:
    """Create and configure the LangGraph workflow for source collection.
    
    This function constructs a complete state machine workflow for orchestrating
    the source collection process. The workflow includes initialization, query
    generation, source search, reliability scoring, result filtering, and
    comprehensive error handling.
    
    Returns:
        Configured StateGraph workflow ready for compilation and execution.
        
    Raises:
        ImportError: If LangGraph is not available.
        
    Note:
        The workflow supports automatic error recovery and branching logic based
        on intermediate results. Each node can route to error_handler if needed.
    """
    if not LANGGRAPH_AVAILABLE:
        raise ImportError("LangGraph is required but not available")
    
    # Create the workflow graph
    workflow: StateGraph = StateGraph(SourceCollectionState)
    
    # Add workflow nodes
    workflow.add_node("initialize", initialize_node)
    workflow.add_node("generate_queries", generate_queries_node)
    workflow.add_node("search_sources", search_sources_node)
    workflow.add_node("score_reliability", score_reliability_node)
    workflow.add_node("filter_results", filter_results_node)
    workflow.add_node("finalize", finalize_node)
    workflow.add_node("error_handler", error_handler_node)
    
    # Set workflow entry point
    workflow.set_entry_point("initialize")
    
    # Add conditional routing edges with error handling
    workflow.add_conditional_edges(
        "initialize",
        should_continue,
        {
            "generate_queries": "generate_queries",
            "error_handler": "error_handler"
        }
    )
    
    workflow.add_conditional_edges(
        "generate_queries",
        should_continue,
        {
            "search_sources": "search_sources",
            "error_handler": "error_handler"
        }
    )
    
    workflow.add_conditional_edges(
        "search_sources",
        should_continue,
        {
            "score_reliability": "score_reliability",
            "error_handler": "error_handler"
        }
    )
    
    workflow.add_conditional_edges(
        "score_reliability",
        should_continue,
        {
            "filter_results": "filter_results",
            "error_handler": "error_handler"
        }
    )
    
    workflow.add_conditional_edges(
        "filter_results",
        should_continue,
        {
            "finalize": "finalize"
        }
    )
    
    workflow.add_conditional_edges(
        "finalize",
        should_continue,
        {
            END: END
        }
    )
    
    workflow.add_conditional_edges(
        "error_handler",
        should_continue,
        {
            END: END
        }
    )
    
    return workflow


# MARK: - Main Workflow Runner

@traceable(name="run_source_collection_workflow")
async def run_source_collection_workflow(
    topic: str,
    search_limit: int = 5,
    reliability_threshold: float = 60.0,
    source_preferences: Optional[List[str]] = None,
    openai_api_key: str = "",
    tavily_api_key: str = ""
) -> Dict[str, Any]:
    """
    Run the complete source collection workflow
    
    Args:
        topic: Research topic
        search_limit: Maximum results per query
        reliability_threshold: Minimum reliability score
        source_preferences: List of source preference types
        openai_api_key: OpenAI API key
        tavily_api_key: Tavily API key
        
    Returns:
        Dict containing workflow results and metadata
    """
    print(f"🚀 Starting LangGraph source collection workflow")
    print(f"   Topic: {topic}")
    print(f"   Limit: {search_limit}, Threshold: {reliability_threshold}%")
    
    if not LANGGRAPH_AVAILABLE:
        raise ImportError("LangGraph is required but not available")
    
    # Create workflow
    workflow = create_source_collection_workflow()
    app = workflow.compile()
    
    # Prepare initial state
    initial_state = SourceCollectionState(
        topic=topic,
        search_limit=search_limit,
        reliability_threshold=reliability_threshold,
        source_preferences=source_preferences or ["reliable"],
        api_keys={
            "OPENAI_API_KEY": openai_api_key,
            "TAVILY_API_KEY": tavily_api_key
        },
        current_step="",
        progress=0.0,
        error_count=0,
        retry_count=0,
        search_queries=[],
        raw_results=[],
        scored_results=[],
        filtered_results=[],
        messages=[],
        run_id=None,
        start_time=None,
        step_timings={},
        success=False,
        final_results=[],
        error_message=None
    )
    
    try:
        # Run the workflow
        final_state = await app.ainvoke(initial_state)
        
        # Prepare results
        return {
            "success": final_state["success"],
            "results": final_state["final_results"],
            "error_message": final_state.get("error_message"),
            "metadata": {
                "total_queries": len(final_state["search_queries"]),
                "raw_results": len(final_state["raw_results"]),
                "scored_results": len(final_state["scored_results"]),
                "filtered_results": len(final_state["filtered_results"]),
                "error_count": final_state["error_count"],
                "retry_count": final_state["retry_count"],
                "step_timings": final_state["step_timings"],
                "messages": [msg.content for msg in final_state["messages"]]
            }
        }
        
    except Exception as e:
        print(f"💥 Workflow execution failed: {e}")
        return {
            "success": False,
            "results": [],
            "error_message": str(e),
            "metadata": {
                "error_count": 1,
                "messages": [f"Workflow execution failed: {str(e)}"]
            }
        }


# MARK: - Testing and Development

def test_workflow() -> None:
    """Test the LangGraph workflow with sample data and real API keys.
    
    This function provides a comprehensive test of the source collection workflow
    using real API keys from environment variables. It tests the complete pipeline
    from query generation through result filtering and provides detailed output
    about the workflow execution.
    
    Environment Variables Required:
        OPENAI_API_KEY: Valid OpenAI API key for LLM operations
        TAVILY_API_KEY: Valid Tavily API key for web search
        
    Test Parameters:
        - Topic: "artificial intelligence"
        - Search limit: 3 results
        - Reliability threshold: 60%
        - Source preferences: ["reliable"]
        
    Output:
        Prints detailed test results including success status, result count,
        error count, and sample result information.
        
    Note:
        This function will gracefully handle missing API keys by using fallback
        data, but real API keys are recommended for comprehensive testing.
    """
    print("🧪 Testing LangGraph Source Collection Workflow")
    print("=" * 50)
    
    if not LANGGRAPH_AVAILABLE:
        print("❌ LangGraph not available - cannot run workflow")
        return
    
    # Load environment variables
    from dotenv import load_dotenv
    load_dotenv()
    
    openai_key: str = os.getenv('OPENAI_API_KEY', '')
    tavily_key: str = os.getenv('TAVILY_API_KEY', '')
    
    print(f"OpenAI key: {'✅' if openai_key else '❌'}")
    print(f"Tavily key: {'✅' if tavily_key else '❌'}")
    
    async def run_test() -> None:
        """Execute the workflow test asynchronously."""
        result: Dict[str, Any] = await run_source_collection_workflow(
            topic="artificial intelligence",
            search_limit=3,
            reliability_threshold=60.0,
            source_preferences=["reliable"],
            openai_api_key=openai_key,
            tavily_api_key=tavily_key
        )
        
        print(f"\n✅ Workflow completed!")
        print(f"   Success: {result['success']}")
        print(f"   Results: {len(result['results'])}")
        print(f"   Errors: {result['metadata']['error_count']}")
        
        if result['results']:
            print(f"\n📊 Sample result:")
            sample: Dict[str, Any] = result['results'][0]
            print(f"   Title: {sample.get('title', '')[:50]}...")
            print(f"   Reliability: {sample.get('reliability_score', 'N/A')}%")
    
    # Execute the async test
    asyncio.run(run_test())


if __name__ == "__main__":
    test_workflow() 