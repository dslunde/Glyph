#!/usr/bin/env python3
"""
Real API implementations for Glyph
=================================

This module contains the actual API implementations for OpenAI and Tavily
that will be called from Swift through PythonKit.

Features:
- Real OpenAI API calls for query generation and reliability scoring
- Real Tavily API calls for web search
- LangSmith tracing for all operations
- Comprehensive error handling and graceful fallbacks
- Rate limiting and network issue handling
"""

import os
import sys
import json
import time
import asyncio
from typing import List, Dict, Any, Optional, Union
from datetime import datetime

# Set up environment for .env file loading
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Import required modules with fallback handling
try:
    from dotenv import load_dotenv
    load_dotenv()
    print("✅ Environment variables loaded")
except ImportError:
    print("⚠️ python-dotenv not available - using system environment only")

# LangSmith tracing
try:
    from langsmith import traceable  # type: ignore
    LANGSMITH_AVAILABLE = True
    print("✅ LangSmith tracing available")
except ImportError:
    print("⚠️ LangSmith not available - operations will not be traced")
    LANGSMITH_AVAILABLE = False
    def traceable(name: Optional[str] = None):  # type: ignore
        def decorator(func):
            return func
        return decorator

# OpenAI integration
try:
    import openai
    OPENAI_AVAILABLE = True
    print("✅ OpenAI module available")
except ImportError:
    print("❌ OpenAI module not available")
    OPENAI_AVAILABLE = False

# Tavily integration
try:
    from tavily import TavilyClient
    TAVILY_AVAILABLE = True
    print("✅ Tavily module available")
except ImportError:
    print("❌ Tavily module not available")
    TAVILY_AVAILABLE = False

# Requests for fallback HTTP calls
try:
    import requests
    REQUESTS_AVAILABLE = True
except ImportError:
    print("❌ Requests module not available")
    REQUESTS_AVAILABLE = False


class APIError(Exception):
    """Custom exception for API-related errors"""
    def __init__(self, service: str, message: str, status_code: Optional[int] = None):
        self.service = service
        self.message = message
        self.status_code = status_code
        super().__init__(f"{service} API Error: {message}")


class RateLimitError(APIError):
    """Exception for rate limiting issues"""
    def __init__(self, service: str, retry_after: Optional[int] = None):
        self.retry_after = retry_after
        message = f"Rate limit exceeded"
        if retry_after:
            message += f", retry after {retry_after} seconds"
        super().__init__(service, message, 429)


class NetworkError(APIError):
    """Exception for network-related issues"""
    pass


def setup_langsmith() -> bool:
    """Setup LangSmith tracing if available"""
    if not LANGSMITH_AVAILABLE:
        return False
    
    api_key = os.getenv("LANGCHAIN_API_KEY")
    tracing_enabled = os.getenv("LANGCHAIN_TRACING_V2", "false").lower() == "true"
    
    if not api_key or not tracing_enabled:
        return False
    
    print(f"🔍 LangSmith tracing enabled for project: {os.getenv('LANGCHAIN_PROJECT', 'Glyph')}")
    return True


def handle_api_error(service: str, error: Exception) -> APIError:
    """Convert various exceptions into standardized APIError"""
    if hasattr(error, 'status_code'):
        status_code = getattr(error, 'status_code')
        if status_code == 429:
            retry_after = getattr(error, 'retry_after', None)
            return RateLimitError(service, retry_after)
        else:
            return APIError(service, str(error), status_code)
    elif "network" in str(error).lower() or "connection" in str(error).lower():
        return NetworkError(service, f"Network error: {str(error)}")
    else:
        return APIError(service, str(error))


@traceable(name="generate_search_queries_real")
def generate_search_queries(topic: str, api_key: str) -> Dict[str, Union[List[str], str, bool]]:
    """
    Generate search queries using OpenAI API with comprehensive error handling
    
    Args:
        topic: The research topic
        api_key: OpenAI API key
        
    Returns:
        Dict with 'success', 'queries', and optionally 'error' keys
    """
    print(f"🤖 Generating search queries for topic: '{topic}'")
    
    if not OPENAI_AVAILABLE:
        print("❌ OpenAI module not available - using fallback")
        return {
            "success": False,
            "error": "OpenAI module not available",
            "queries": generate_fallback_queries(topic)
        }
    
    if not api_key or api_key == "demo-key":
        print("❌ Invalid OpenAI API key")
        return {
            "success": False,
            "error": "Invalid or missing OpenAI API key",
            "queries": generate_fallback_queries(topic)
        }
    
    try:
        client = openai.OpenAI(api_key=api_key)
        
        prompt = f"""Generate 5 specific, focused search queries for researching: {topic}

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
        
        print("📡 Making OpenAI API call...")
        response = client.chat.completions.create(
            model="gpt-4o-mini",  # Use cost-effective model
            messages=[{"role": "user", "content": prompt}],
            temperature=0.7,
            max_tokens=500,
            timeout=30  # 30 second timeout
        )
        
        content = response.choices[0].message.content or ""
        queries = [q.strip() for q in content.split('\n') if q.strip()]
        
        # Ensure we have exactly 5 queries
        if len(queries) < 5:
            queries.extend(generate_fallback_queries(topic)[len(queries):])
        elif len(queries) > 5:
            queries = queries[:5]
        
        print(f"✅ Generated {len(queries)} queries successfully")
        for i, query in enumerate(queries, 1):
            print(f"   {i}. {query}")
        
        return {
            "success": True,
            "queries": queries
        }
        
    except openai.RateLimitError as e:
        error = handle_api_error("OpenAI", e)
        print(f"🚫 {error}")
        return {
            "success": False,
            "error": str(error),
            "queries": generate_fallback_queries(topic)
        }
        
    except openai.APIError as e:
        error = handle_api_error("OpenAI", e)
        print(f"❌ {error}")
        return {
            "success": False,
            "error": str(error),
            "queries": generate_fallback_queries(topic)
        }
        
    except Exception as e:
        error = handle_api_error("OpenAI", e)
        print(f"💥 Unexpected error: {error}")
        return {
            "success": False,
            "error": str(error),
            "queries": generate_fallback_queries(topic)
        }


@traceable(name="search_with_tavily_real")
def search_with_tavily(queries: List[str], limit: int, api_key: str) -> Dict[str, Union[List[Dict[str, Any]], str, bool]]:
    """
    Search using Tavily API with comprehensive error handling
    
    Args:
        queries: List of search queries
        limit: Maximum results per query
        api_key: Tavily API key
        
    Returns:
        Dict with 'success', 'results', and optionally 'error' keys
    """
    print(f"🔍 Searching with {len(queries)} queries, limit: {limit}")
    
    if not TAVILY_AVAILABLE:
        print("❌ Tavily module not available - using fallback")
        return {
            "success": False,
            "error": "Tavily module not available",
            "results": generate_fallback_search_results(queries, limit)
        }
    
    if not api_key or api_key == "demo-key":
        print("❌ Invalid Tavily API key")
        return {
            "success": False,
            "error": "Invalid or missing Tavily API key",
            "results": generate_fallback_search_results(queries, limit)
        }
    
    try:
        client = TavilyClient(api_key=api_key)
        all_results = []
        
        for i, query in enumerate(queries):
            print(f"   🔍 Query {i+1}: {query}")
            
            try:
                # Add delay between requests to avoid rate limits
                if i > 0:
                    time.sleep(0.5)
                
                search_results = client.search(
                    query=query,
                    search_depth="advanced",
                    max_results=min(limit, 3),  # Limit per query to manage API usage
                    include_answer=True,
                    include_raw_content=True
                )
                
                # Process results
                for result in search_results.get("results", []):
                    processed_result = {
                        "title": result.get("title", ""),
                        "url": result.get("url", ""),
                        "content": result.get("content", "")[:1000],  # Limit content length
                        "score": float(result.get("score", 0.0)),
                        "published_date": result.get("published_date", ""),
                        "query": query
                    }
                    all_results.append(processed_result)
                
                print(f"     ✅ Found {len(search_results.get('results', []))} results")
                
            except Exception as query_error:
                print(f"     ❌ Query failed: {query_error}")
                continue  # Continue with other queries
        
        # Limit total results
        if len(all_results) > limit:
            all_results = all_results[:limit]
        
        print(f"✅ Total search results: {len(all_results)}")
        
        return {
            "success": True,
            "results": all_results
        }
        
    except Exception as e:
        error = handle_api_error("Tavily", e)
        print(f"❌ {error}")
        return {
            "success": False,
            "error": str(error),
            "results": generate_fallback_search_results(queries, limit)
        }


@traceable(name="score_reliability_real")
def score_reliability(results: List[Dict[str, Any]], source_preferences: List[str], api_key: str) -> Dict[str, Union[List[Dict[str, Any]], str, bool]]:
    """
    Score reliability using OpenAI API with comprehensive error handling
    
    Args:
        results: List of search results to score
        source_preferences: User's source preferences
        api_key: OpenAI API key
        
    Returns:
        Dict with 'success', 'results', and optionally 'error' keys
    """
    print(f"🎯 Scoring reliability for {len(results)} results")
    print(f"   Source preferences: {source_preferences}")
    
    if not OPENAI_AVAILABLE:
        print("❌ OpenAI module not available - using fallback")
        return {
            "success": False,
            "error": "OpenAI module not available",
            "results": generate_fallback_reliability_scores(results)
        }
    
    if not api_key or api_key == "demo-key":
        print("❌ Invalid OpenAI API key")
        return {
            "success": False,
            "error": "Invalid or missing OpenAI API key", 
            "results": generate_fallback_reliability_scores(results)
        }
    
    try:
        client = openai.OpenAI(api_key=api_key)
        scored_results = []
        
        for i, result in enumerate(results):
            try:
                # Add delay between requests
                if i > 0:
                    time.sleep(0.2)
                
                title = result.get("title", "")
                url = result.get("url", "")
                content = result.get("content", "")[:500]  # Limit for API
                
                prompt = f"""Rate the reliability of this source on a scale of 0-100.

Source Details:
Title: {title}
URL: {url}
Content: {content}

Consider:
- Domain authority (.edu, .gov, .org = higher scores)
- Content quality and depth
- Presence of citations or references
- Potential bias indicators
- Recency and relevance

User preferences: {', '.join(source_preferences)}

Return only a number between 0-100."""
                
                response = client.chat.completions.create(
                    model="gpt-4o-mini",
                    messages=[{"role": "user", "content": prompt}],
                    temperature=0.3,
                    max_tokens=10,
                    timeout=15
                )
                
                try:
                    content_response = response.choices[0].message.content or "50"
                    score = int(content_response.strip())
                    score = max(0, min(100, score))  # Clamp to 0-100
                except (ValueError, AttributeError):
                    score = generate_domain_score(url)  # Fallback to domain-based scoring
                
                result_copy = result.copy()
                result_copy["reliabilityScore"] = score
                scored_results.append(result_copy)
                
                print(f"   📊 '{title[:50]}...' → {score}%")
                
            except Exception as score_error:
                print(f"   ❌ Scoring failed for result {i+1}: {score_error}")
                # Use fallback scoring
                result_copy = result.copy()
                result_copy["reliabilityScore"] = generate_domain_score(result.get("url", ""))
                scored_results.append(result_copy)
        
        avg_score = sum(r.get("reliabilityScore", 50) for r in scored_results) / max(1, len(scored_results))
        print(f"✅ Reliability scoring complete - Average: {avg_score:.1f}%")
        
        return {
            "success": True,
            "results": scored_results
        }
        
    except Exception as e:
        error = handle_api_error("OpenAI", e)
        print(f"❌ {error}")
        return {
            "success": False,
            "error": str(error),
            "results": generate_fallback_reliability_scores(results)
        }


# Fallback functions for when APIs fail

def generate_fallback_queries(topic: str) -> List[str]:
    """Generate fallback queries when OpenAI API fails"""
    return [
        f"{topic} fundamentals and basic concepts",
        f"{topic} latest research and developments 2024",
        f"{topic} expert opinions and analysis", 
        f"{topic} practical applications and case studies",
        f"{topic} controversies and different perspectives"
    ]


def generate_fallback_search_results(queries: List[str], limit: int) -> List[Dict[str, Any]]:
    """Generate fallback search results when Tavily API fails"""
    results = []
    for i, query in enumerate(queries[:limit]):
        result = {
            "title": f"Research on {query}",
            "url": f"https://example.com/article{i + 1}",
            "content": f"Comprehensive analysis of {query} with detailed findings.",
            "score": 0.7 + (i * 0.05),
            "published_date": f"2024-01-{15 + i}",
            "query": query
        }
        results.append(result)
    return results


def generate_fallback_reliability_scores(results: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Generate fallback reliability scores when OpenAI API fails"""
    scored_results = []
    for result in results:
        result_copy = result.copy()
        result_copy["reliabilityScore"] = generate_domain_score(result.get("url", ""))
        scored_results.append(result_copy)
    return scored_results


def generate_domain_score(url: str) -> int:
    """Generate reliability score based on domain"""
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


# Test function for direct Python testing
def test_api_integration():
    """Test function to verify API integration"""
    print("🧪 Testing API Integration")
    print("=" * 40)
    
    # Setup
    setup_langsmith()
    
    # Test environment
    openai_key = os.getenv("OPENAI_API_KEY")
    tavily_key = os.getenv("TAVILY_API_KEY")
    
    print(f"OpenAI key: {'✅' if openai_key else '❌'}")
    print(f"Tavily key: {'✅' if tavily_key else '❌'}")
    
    # Test query generation
    print("\n🤖 Testing query generation...")
    query_result = generate_search_queries("machine learning", openai_key or "")
    print(f"Success: {query_result['success']}")
    if isinstance(query_result['queries'], list):
        print(f"Queries: {len(query_result['queries'])}")
    else:
        print("Queries: Error occurred")
    
    # Test search
    print("\n🔍 Testing search...")
    if isinstance(query_result['queries'], list):
        search_result = search_with_tavily(query_result['queries'][:2], 3, tavily_key or "")
        print(f"Success: {search_result['success']}")
        if isinstance(search_result['results'], list):
            print(f"Results: {len(search_result['results'])}")
            
            # Test scoring
            print("\n🎯 Testing reliability scoring...")
            score_result = score_reliability(search_result['results'], ["reliable"], openai_key or "")
            print(f"Success: {score_result['success']}")
            if isinstance(score_result['results'], list):
                print(f"Scored: {len(score_result['results'])}")
        else:
            print("Results: Error occurred")
    else:
        print("Query generation failed")
    
    print("\n✅ API integration test complete!")


if __name__ == "__main__":
    test_api_integration() 