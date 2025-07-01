#!/usr/bin/env python3
"""
LangSmith Integration for Glyph
==============================

This script demonstrates how LangSmith tracing will be integrated
with the actual API calls when they're implemented.

Usage:
- This script shows the pattern for OpenAI and Tavily API integration
- LangSmith will automatically trace all LLM calls and API interactions
- Traces appear in the LangSmith dashboard at https://smith.langchain.com/

Configuration:
- Requires LANGCHAIN_API_KEY environment variable
- Requires LANGCHAIN_TRACING_V2=true environment variable
- Optionally set LANGCHAIN_PROJECT for custom project name
"""

import os
import sys
from typing import List, Dict, Any
from datetime import datetime

# Check if LangSmith is available
try:
    from langsmith import traceable
    from langchain_core.tracers.langchain import LangChainTracer
    LANGSMITH_AVAILABLE = True
    print("✅ LangSmith module available")
except ImportError:
    print("⚠️ LangSmith module not available - install with: pip install langsmith")
    LANGSMITH_AVAILABLE = False
    
    # Create a dummy decorator if LangSmith is not available
    def traceable(name=None):  # type: ignore
        def decorator(func):
            return func
        return decorator

# Check if OpenAI is available  
try:
    import openai
    OPENAI_AVAILABLE = True
    print("✅ OpenAI module available")
except ImportError:
    print("⚠️ OpenAI module not available - install with: pip install openai")
    OPENAI_AVAILABLE = False

# Check if Tavily is available
try:
    from tavily import TavilyClient
    TAVILY_AVAILABLE = True
    print("✅ Tavily module available")
except ImportError:
    print("⚠️ Tavily module not available - install with: pip install tavily-python")
    TAVILY_AVAILABLE = False


def setup_langsmith():
    """Setup LangSmith tracing configuration"""
    if not LANGSMITH_AVAILABLE:
        print("🚫 LangSmith not available - tracing disabled")
        return False
    
    api_key = os.getenv("LANGCHAIN_API_KEY")
    tracing_enabled = os.getenv("LANGCHAIN_TRACING_V2", "false").lower() == "true"
    project = os.getenv("LANGCHAIN_PROJECT", "Glyph")
    
    if not api_key:
        print("❌ LANGCHAIN_API_KEY not found - LangSmith tracing disabled")
        return False
    
    if not tracing_enabled:
        print("❌ LANGCHAIN_TRACING_V2 not enabled - LangSmith tracing disabled")
        return False
    
    print(f"🔍 LangSmith tracing enabled for project: {project}")
    return True


@traceable(name="generate_search_queries")
def generate_search_queries_real(topic: str, api_key: str) -> List[str]:
    """
    Generate search queries using OpenAI with LangSmith tracing
    
    This function will be automatically traced by LangSmith when implemented.
    All inputs, outputs, and intermediate steps will be logged.
    """
    if not OPENAI_AVAILABLE:
        print("🤖 OpenAI not available - using mock queries")
        return generate_mock_queries(topic)
    
    try:
        # This would be the real OpenAI integration
        client = openai.OpenAI(api_key=api_key)
        
        prompt = f"""
        Generate 5 specific search queries for researching the topic: {topic}
        
        The queries should cover:
        1. Fundamental concepts and definitions
        2. Recent developments and research (2024)
        3. Expert opinions and analysis
        4. Practical applications and case studies
        5. Controversies and different perspectives
        
        Return only the queries, one per line.
        """
        
        # LangSmith will automatically trace this API call
        response = client.chat.completions.create(
            model="gpt-4",
            messages=[{"role": "user", "content": prompt}],
            temperature=0.7,
            max_tokens=500
        )
        
        # Parse the response into individual queries
        content = response.choices[0].message.content or ""
        queries = [q.strip() for q in content.split('\n') if q.strip()]
        
        print(f"✅ Generated {len(queries)} queries using OpenAI")
        return queries
        
    except Exception as e:
        print(f"❌ OpenAI API error: {e}")
        print("🔄 Falling back to mock queries")
        return generate_mock_queries(topic)


@traceable(name="search_with_tavily")
def search_with_tavily_real(queries: List[str], limit: int, api_key: str) -> List[Dict[str, Any]]:
    """
    Search using Tavily API with LangSmith tracing
    
    This function will be automatically traced by LangSmith when implemented.
    All API calls, response processing, and results will be logged.
    """
    if not TAVILY_AVAILABLE:
        print("📡 Tavily not available - using mock results")
        return generate_mock_tavily_results(queries, limit)
    
    try:
        client = TavilyClient(api_key=api_key)
        all_results = []
        
        for query in queries:
            print(f"🔍 Searching: {query}")
            
            # LangSmith will automatically trace this API call
            search_results = client.search(
                query=query,
                search_depth="advanced",
                max_results=limit,
                include_answer=True,
                include_raw_content=True
            )
            
            # Process and standardize results
            for result in search_results.get("results", []):
                processed_result = {
                    "title": result.get("title", ""),
                    "url": result.get("url", ""),
                    "content": result.get("content", ""),
                    "score": result.get("score", 0.0),
                    "published_date": result.get("published_date", ""),
                    "query": query
                }
                all_results.append(processed_result)
        
        print(f"✅ Found {len(all_results)} results using Tavily")
        return all_results
        
    except Exception as e:
        print(f"❌ Tavily API error: {e}")
        print("🔄 Falling back to mock results")
        return generate_mock_tavily_results(queries, limit)


@traceable(name="score_reliability")
def score_reliability_real(results: List[Dict[str, Any]], source_preferences: List[str], api_key: str) -> List[Dict[str, Any]]:
    """
    Score reliability using OpenAI with LangSmith tracing
    
    This function will be automatically traced by LangSmith when implemented.
    The LLM analysis of each source will be logged for debugging.
    """
    if not OPENAI_AVAILABLE:
        print("🎯 OpenAI not available - using mock scoring")
        return score_reliability_mock(results)
    
    try:
        client = openai.OpenAI(api_key=api_key)
        scored_results = []
        
        for result in results:
            title = result.get("title", "")
            url = result.get("url", "")
            content = result.get("content", "")[:500]  # Limit content for API call
            
            prompt = f"""
            Score the reliability of this source on a scale of 0-100:
            
            Title: {title}
            URL: {url}
            Content preview: {content}
            
            Consider:
            - Domain authority (.edu, .gov, .org vs .com)
            - Content quality and depth
            - Presence of citations or references
            - Potential bias indicators
            - Recency and relevance
            
            Source preferences: {source_preferences}
            
            Return only a number between 0-100.
            """
            
            # LangSmith will automatically trace this API call
            response = client.chat.completions.create(
                model="gpt-4",
                messages=[{"role": "user", "content": prompt}],
                temperature=0.3,
                max_tokens=10
            )
            
            try:
                content = response.choices[0].message.content or "50"
                score = int(content.strip())
                score = max(0, min(100, score))  # Clamp to 0-100
            except (ValueError, AttributeError):
                score = 50  # Default score if parsing fails
            
            result_copy = result.copy()
            result_copy["reliabilityScore"] = score
            scored_results.append(result_copy)
            
            print(f"📊 '{title[:50]}...' → {score}% reliability")
        
        print(f"✅ Scored {len(scored_results)} results using OpenAI")
        return scored_results
        
    except Exception as e:
        print(f"❌ OpenAI API error: {e}")
        print("🔄 Falling back to mock scoring")
        return score_reliability_mock(results)


# Mock functions (current implementation)
def generate_mock_queries(topic: str) -> List[str]:
    """Generate mock search queries"""
    return [
        f"{topic} fundamentals and basic concepts",
        f"{topic} latest research and developments 2024",
        f"{topic} expert opinions and analysis",
        f"{topic} practical applications and case studies",
        f"{topic} controversies and different perspectives"
    ]


def generate_mock_tavily_results(queries: List[str], limit: int) -> List[Dict[str, Any]]:
    """Generate mock Tavily search results"""
    results = []
    for i, query in enumerate(queries[:limit]):
        result = {
            "title": f"Research on {query}",
            "url": f"https://example.com/article{i + 1}",
            "content": f"Comprehensive analysis of {query} with detailed findings and expert insights.",
            "score": 0.7 + (i * 0.05),
            "published_date": f"2024-01-{15 + i}",
            "query": query
        }
        results.append(result)
    return results


def score_reliability_mock(results: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Generate mock reliability scores"""
    import random
    
    scored_results = []
    for result in results:
        url = result.get("url", "").lower()
        
        # Simple domain-based scoring
        if "edu" in url or "gov" in url:
            score = random.randint(75, 90)
        elif "org" in url:
            score = random.randint(60, 80)
        else:
            score = random.randint(40, 70)
        
        result_copy = result.copy()
        result_copy["reliabilityScore"] = score
        scored_results.append(result_copy)
    
    return scored_results


def main():
    """Demo function showing LangSmith integration"""
    print("🔍 LangSmith Integration Demo for Glyph")
    print("=" * 50)
    
    # Load environment variables
    from dotenv import load_dotenv
    load_dotenv()
    
    # Get real API keys
    openai_key = os.getenv('OPENAI_API_KEY')
    tavily_key = os.getenv('TAVILY_API_KEY')
    
    if not openai_key:
        print("❌ OPENAI_API_KEY not found in environment")
        return
    if not tavily_key:
        print("❌ TAVILY_API_KEY not found in environment")
        return
    
    print(f"✅ OpenAI API key loaded (length: {len(openai_key)})")
    print(f"✅ Tavily API key loaded (length: {len(tavily_key)})")
    
    # Setup LangSmith
    langsmith_enabled = setup_langsmith()
    
    if langsmith_enabled:
        print("🎯 LangSmith tracing is active - check your dashboard!")
        print("   Dashboard: https://smith.langchain.com/")
    else:
        print("⚠️ LangSmith tracing is disabled")
    
    # Demo topic
    topic = "artificial intelligence"
    
    print(f"\n📝 Demo: Generating queries for '{topic}'")
    queries = generate_search_queries_real(topic, openai_key)
    
    print(f"\n🔍 Demo: Searching for results")
    results = search_with_tavily_real(queries, 3, tavily_key)
    
    print(f"\n🎯 Demo: Scoring reliability")
    scored_results = score_reliability_real(results, ["reliable"], openai_key)
    
    print(f"\n✅ Demo complete!")
    print(f"   Generated queries: {len(queries)}")
    print(f"   Search results: {len(results)}")
    print(f"   Scored results: {len(scored_results)}")
    
    if langsmith_enabled:
        print("🔍 Check your LangSmith dashboard to see the traced operations!")
        print("   Project: Glyph")


if __name__ == "__main__":
    main() 