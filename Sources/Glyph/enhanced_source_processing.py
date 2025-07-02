#!/usr/bin/env python3
"""
Enhanced Source Processing Module for Glyph

Provides intelligent processing of manual sources including:
- File content extraction with intelligent naming
- Folder recursive scanning for text files
- URL expansion with sitemap parsing and agent decisions
"""

import os
import re
import json
import urllib.parse
import xml.etree.ElementTree as ET
import hashlib
import pickle
import asyncio
import concurrent.futures
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional, Tuple, Set
from pathlib import Path

try:
    import requests
    from bs4 import BeautifulSoup
    REQUESTS_AVAILABLE = True
except ImportError:
    REQUESTS_AVAILABLE = False
    print("⚠️ requests and beautifulsoup4 not available - URL processing disabled")

try:
    from langchain_openai import ChatOpenAI  # type: ignore
    from langchain_core.messages import HumanMessage, SystemMessage  # type: ignore
    LANGCHAIN_AVAILABLE = True
except ImportError:
    LANGCHAIN_AVAILABLE = False
    print("⚠️ LangChain not available - using heuristic URL filtering")

# Configuration - can be overridden by function parameters
DEFAULT_MAX_DISCOVERED_PAGES = 10
CACHE_EXPIRY_HOURS = 24
MAX_CONCURRENT_REQUESTS = 5
MAX_FILE_SIZE_MB = 10
SUPPORTED_TEXT_EXTENSIONS = {
    '.txt', '.md', '.markdown', '.rst', '.py', '.js', '.html', 
    '.htm', '.css', '.json', '.xml', '.yaml', '.yml', '.csv', '.log'
}

# Performance optimization settings
ENABLE_CONCURRENT_PROCESSING = True
ENABLE_CACHING = True
CACHE_DIR = os.path.expanduser("~/.glyph_cache")

# Ensure cache directory exists
if ENABLE_CACHING:
    os.makedirs(CACHE_DIR, exist_ok=True)

class EnhancedSourceProcessor:
    """
    Enhanced source processor with performance optimizations and AI integration.
    
    Features:
    - File-based caching for processed sources
    - Concurrent processing for improved performance
    - AI-powered URL relevance filtering
    - Memory optimization and background processing
    - Robust error handling and retry logic
    """
    
    def __init__(self, openai_api_key: Optional[str] = None):
        """
        Initialize the enhanced source processor.
        
        Args:
            openai_api_key: OpenAI API key for AI-powered URL filtering (optional)
        """
        self.discovered_urls: Set[str] = set()
        self.processed_files: Set[str] = set()
        self.openai_api_key = openai_api_key
        
        # Initialize AI-powered URL filter if available
        self.ai_url_filter = None
        if openai_api_key and LANGCHAIN_AVAILABLE:
            try:
                self.ai_url_filter = ChatOpenAI(
                    api_key=openai_api_key,
                    model="gpt-4o-mini",
                    temperature=0.1,
                    max_tokens=1000
                )
                print("✅ AI-powered URL filtering enabled")
            except Exception as e:
                print(f"⚠️ Failed to initialize AI URL filter: {e}")
        
        # Performance tracking
        self.processing_stats = {
            "cache_hits": 0,
            "cache_misses": 0,
            "concurrent_requests": 0,
            "ai_url_analyses": 0,
            "total_processing_time": 0.0
        }
        
    def process_manual_sources(
        self, 
        file_paths: List[str], 
        urls: List[str], 
        topic: str,
        max_pages: int = DEFAULT_MAX_DISCOVERED_PAGES
    ) -> Dict[str, Any]:
        """
        Process all manual sources into formatted source data with performance optimizations.
        
        Args:
            file_paths: List of file or folder paths to process
            urls: List of URLs to process and expand  
            topic: Topic for context in URL expansion and filtering
            max_pages: Maximum pages to discover per URL
            
        Returns:
            Dictionary containing processed sources and metadata
        """
        start_time = datetime.now()
        print(f"🔄 Processing manual sources for topic: {topic}")
        print(f"   ⚡ Performance optimizations: Caching={'ON' if ENABLE_CACHING else 'OFF'}, "
              f"Concurrent={'ON' if ENABLE_CONCURRENT_PROCESSING else 'OFF'}, "
              f"AI_Filter={'ON' if self.ai_url_filter else 'OFF'}")
        
        # Check cache for entire request first
        cache_key = self._generate_cache_key(file_paths, urls, topic, max_pages)
        cached_result = self._load_from_cache(cache_key)
        
        if cached_result:
            self.processing_stats["cache_hits"] += 1
            print(f"📋 Using cached results ({self.processing_stats['cache_hits']} cache hits)")
            return cached_result
        
        self.processing_stats["cache_misses"] += 1
        processed_sources = []
        metadata = {
            'files_processed': 0,
            'folders_scanned': 0,
            'urls_expanded': 0,
            'total_discovered_pages': 0,
            'errors': [],
            'performance_stats': self.processing_stats.copy()
        }
        
        # Process files and folders with concurrent processing if enabled
        if ENABLE_CONCURRENT_PROCESSING and file_paths:
            processed_sources.extend(self._process_files_concurrent(file_paths, metadata))
        else:
            # Sequential processing fallback
            for file_path in file_paths:
                if not file_path.strip():
                    continue
                    
                try:
                    sources, meta = self.process_file_or_folder(file_path)
                    processed_sources.extend(sources)
                    
                    if meta['is_folder']:
                        metadata['folders_scanned'] += 1
                        metadata['files_processed'] += meta['files_count']
                    else:
                        metadata['files_processed'] += 1
                        
                except Exception as e:
                    error_msg = f"Error processing {file_path}: {str(e)}"
                    metadata['errors'].append(error_msg)
        
        # Process URLs
        if REQUESTS_AVAILABLE:
            for url in urls:
                if not url.strip():
                    continue
                    
                try:
                    sources, meta = self.process_url_with_expansion(url, topic, max_pages)
                    processed_sources.extend(sources)
                    
                    metadata['urls_expanded'] += 1
                    metadata['total_discovered_pages'] += meta['discovered_count']
                    
                except Exception as e:
                    error_msg = f"Error processing {url}: {str(e)}"
                    metadata['errors'].append(error_msg)
        else:
            for url in urls:
                if url.strip():
                    # Basic URL source without expansion
                    source = {
                        'title': self._generate_title_from_url(url),
                        'content': f"User-provided URL: {url}",
                        'url': url,
                        'score': 0.8,
                        'published_date': '',
                        'query': f"Manual URL: {url}",
                        'reliability_score': 75,
                        'source_type': 'url',
                        'word_count': 0
                    }
                    processed_sources.append(source)
                    metadata['urls_expanded'] += 1
        
        # Record total processing time
        end_time = datetime.now()
        processing_time = (end_time - start_time).total_seconds()
        self.processing_stats["total_processing_time"] += processing_time
        
        # Create final result
        result = {
            'sources': processed_sources,
            'metadata': metadata,
            'total_sources': len(processed_sources),
            'processing_time_seconds': processing_time,
            'performance_stats': self.get_processing_stats()
        }
        
        # Save to cache for future requests
        self._save_to_cache(cache_key, result)
        
        print(f"✅ Processed {len(processed_sources)} sources total in {processing_time:.2f}s")
        print(f"   📊 Performance: Cache hits: {self.processing_stats['cache_hits']}, "
              f"AI analyses: {self.processing_stats['ai_url_analyses']}, "
              f"Concurrent requests: {self.processing_stats['concurrent_requests']}")
        
        return result
    
    def process_file_or_folder(self, path: str) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
        """Process file or folder into source data."""
        sources = []
        metadata = {'is_folder': False, 'files_count': 0}
        
        path_obj = Path(path)
        
        if not path_obj.exists():
            raise FileNotFoundError(f"Path does not exist: {path}")
        
        if path_obj.is_file():
            source = self.extract_file_content(path)
            if source:
                sources.append(source)
                metadata['files_count'] = 1
        
        elif path_obj.is_dir():
            metadata['is_folder'] = True
            
            for file_path in self._scan_folder_for_text_files(path_obj):
                if str(file_path) not in self.processed_files:
                    source = self.extract_file_content(str(file_path))
                    if source:
                        sources.append(source)
                        metadata['files_count'] += 1
                        self.processed_files.add(str(file_path))
        
        return sources, metadata
    
    def extract_file_content(self, file_path: str) -> Optional[Dict[str, Any]]:
        """Extract content from a text file."""
        path_obj = Path(file_path)
        
        if path_obj.suffix.lower() not in SUPPORTED_TEXT_EXTENSIONS:
            return None
        
        try:
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            
            title = self.generate_intelligent_filename(path_obj.name)
            word_count = len(content.split())
            
            source = {
                'title': title,
                'content': content[:5000],  # Limit content
                'url': f"file://{file_path}",
                'score': 0.9,
                'published_date': self._get_file_date(file_path),
                'query': f"File: {path_obj.name}",
                'reliability_score': 90,
                'source_type': 'file',
                'word_count': word_count,
                'file_extension': path_obj.suffix
            }
            
            print(f"📄 Extracted: {title} ({word_count} words)")
            return source
            
        except Exception as e:
            print(f"❌ Failed to extract {file_path}: {e}")
            return None
    
    def process_url_with_expansion(self, base_url: str, topic: str, max_pages: int) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
        """Process URL with intelligent expansion."""
        sources = []
        metadata = {'discovered_count': 0}
        
        # Process base URL
        base_source = self.extract_url_content(base_url)
        if base_source:
            sources.append(base_source)
            self.discovered_urls.add(base_url)
        
        # Discover related URLs
        discovered_urls = self.discover_related_urls(base_url, topic, max_pages)
        metadata['discovered_count'] = len(discovered_urls)
        
        # Process discovered URLs
        for url in discovered_urls:
            if url not in self.discovered_urls:
                url_source = self.extract_url_content(url)
                if url_source:
                    sources.append(url_source)
                    self.discovered_urls.add(url)
        
        return sources, metadata
    
    def discover_related_urls(self, base_url: str, topic: str, max_pages: int) -> List[str]:
        """Discover related URLs using sitemap and same-domain scanning."""
        discovered = []
        
        try:
            parsed_url = urllib.parse.urlparse(base_url)
            base_domain = f"{parsed_url.scheme}://{parsed_url.netloc}"
            
            # Try sitemap first
            sitemap_urls = self._discover_from_sitemap(base_domain, base_url)
            discovered.extend(sitemap_urls)
            
            # Scan same-domain pages
            if len(discovered) < max_pages:
                same_domain_urls = self._discover_from_same_domain(base_url, base_domain, base_url)
                discovered.extend(same_domain_urls)
            
            # Filter using AI-powered relevance analysis
            if len(discovered) > max_pages:
                discovered = self._ai_filter_urls(discovered, topic, max_pages)
            
            discovered = discovered[:max_pages]
            print(f"🔍 Discovered {len(discovered)} related URLs")
            return discovered
            
        except Exception as e:
            print(f"❌ Error discovering URLs: {e}")
            return []
    
    def extract_url_content(self, url: str) -> Optional[Dict[str, Any]]:
        """Extract content from a single URL."""
        print(f"🔍 DEBUG: extract_url_content called with URL: {url}")
        
        if not REQUESTS_AVAILABLE:
            print("❌ DEBUG: requests library not available")
            return None
            
        try:
            print(f"🔄 DEBUG: Making HTTP request to {url}")
            # Use requests with timeout and user agent
            headers = {
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
            }
            
            response = requests.get(url, timeout=10, headers=headers)
            response.raise_for_status()
            
            print(f"✅ DEBUG: HTTP request successful, status code: {response.status_code}")
            print(f"📄 DEBUG: Content length: {len(response.text)} characters")
            
            # Parse with BeautifulSoup
            print("🔄 DEBUG: Parsing content with BeautifulSoup")
            soup = BeautifulSoup(response.text, 'html.parser')
            
            # Remove script and style elements
            for script in soup(["script", "style", "nav", "footer", "header", "aside"]):
                script.decompose()
            
            # Extract title
            title_elem = soup.find('title')
            title = title_elem.get_text().strip() if title_elem else self._generate_title_from_url(url)
            print(f"📝 DEBUG: Extracted title: {title}")
            
            # Extract main content
            content_selectors = [
                'article', 'main', '[role="main"]', '.content', '.post-content', 
                '.entry-content', '.article-content', '.post-body', '.content-body',
                '#content', '#main-content', '.main-content'
            ]
            
            content_text = ""
            for selector in content_selectors:
                content_elem = soup.select_one(selector)
                if content_elem:
                    content_text = content_elem.get_text(separator=' ', strip=True)
                    print(f"✅ DEBUG: Found content using selector '{selector}', length: {len(content_text)}")
                    break
            
            # Fallback to body if no content found
            if not content_text:
                print("🔄 DEBUG: No content found with selectors, falling back to body")
                body = soup.find('body')
                if body:
                    content_text = body.get_text(separator=' ', strip=True)
                    print(f"📄 DEBUG: Body content length: {len(content_text)}")
                else:
                    print("❌ DEBUG: No body element found")
                    content_text = response.text[:2000]
            
            # Clean and limit content
            content_text = ' '.join(content_text.split())  # Clean whitespace
            if len(content_text) > 5000:
                content_text = content_text[:5000] + "..."
                print(f"✂️ DEBUG: Content truncated to 5000 characters")
            
            word_count = len(content_text.split())
            print(f"📊 DEBUG: Final word count: {word_count}")
            
            if word_count < 10:
                print(f"⚠️ DEBUG: Content too short ({word_count} words), might indicate extraction failure")
                print(f"🔍 DEBUG: Content preview: '{content_text[:200]}...'")
            
            result = {
                'title': title,
                'content': content_text,
                'url': url,
                'score': 0.8,
                'published_date': '',
                'query': f"URL content: {url}",
                'reliability_score': 75,
                'source_type': 'url',
                'word_count': word_count
            }
            
            print(f"✅ DEBUG: Returning source: title='{title}', content_length={len(content_text)}, word_count={word_count}")
            return result
            
        except requests.exceptions.RequestException as e:
            print(f"❌ DEBUG: Request failed for {url}: {e}")
            return None
        except Exception as e:
            print(f"❌ DEBUG: Unexpected error processing {url}: {e}")
            return None
    
    def generate_intelligent_filename(self, filename: str) -> str:
        """Generate intelligent title from filename."""
        name = Path(filename).stem
        name = re.sub(r'[_-]+', ' ', name)
        name = re.sub(r'([a-z])([A-Z])', r'\1 \2', name)
        name = re.sub(r'\s+', ' ', name).strip()
        return name.title()
    
    def _scan_folder_for_text_files(self, folder_path: Path) -> List[Path]:
        """Recursively scan folder for text files."""
        text_files = []
        try:
            for file_path in folder_path.rglob('*'):
                if (file_path.is_file() and 
                    file_path.suffix.lower() in SUPPORTED_TEXT_EXTENSIONS and
                    not any(part.startswith('.') for part in file_path.parts)):
                    text_files.append(file_path)
        except PermissionError:
            print(f"⚠️ Permission denied: {folder_path}")
        return text_files
    
    def _get_file_date(self, file_path: str) -> str:
        """Get file modification date."""
        try:
            import datetime
            mtime = os.path.getmtime(file_path)
            return datetime.datetime.fromtimestamp(mtime).strftime('%Y-%m-%d')
        except:
            return ''
    
    def _discover_from_sitemap(self, base_domain: str, base_url: str) -> List[str]:
        """Discover URLs from sitemap.xml."""
        sitemap_urls = []
        try:
            response = requests.get(f"{base_domain}/sitemap.xml", timeout=5)
            if response.status_code == 200:
                root = ET.fromstring(response.content)
                for url_elem in root.findall('.//{http://www.sitemaps.org/schemas/sitemap/0.9}url'):
                    loc_elem = url_elem.find('{http://www.sitemaps.org/schemas/sitemap/0.9}loc')
                    if loc_elem is not None:
                        url = loc_elem.text
                        if url and self._is_url_related_to_base(url, base_url):
                            sitemap_urls.append(url)
                print(f"📍 Found {len(sitemap_urls)} sitemap URLs")
        except Exception as e:
            print(f"⚠️ Sitemap not accessible: {e}")
        return sitemap_urls
    
    def _discover_from_same_domain(self, page_url: str, base_domain: str, base_url: str) -> List[str]:
        """Discover URLs by scanning page links."""
        discovered_urls = []
        try:
            headers = {'User-Agent': 'Mozilla/5.0 (compatible; Glyph/1.0)'}
            response = requests.get(page_url, headers=headers, timeout=10)
            soup = BeautifulSoup(response.content, 'html.parser')
            
            for link in soup.find_all('a', href=True):
                href = link['href']
                
                if href.startswith('/'):
                    full_url = base_domain + href
                elif href.startswith('http'):
                    full_url = href
                else:
                    continue
                
                if (urllib.parse.urlparse(full_url).netloc == urllib.parse.urlparse(base_domain).netloc and
                    self._is_url_related_to_base(full_url, base_url)):
                    discovered_urls.append(full_url)
            
            discovered_urls = list(set(discovered_urls))[:20]
            print(f"🔗 Found {len(discovered_urls)} same-domain links")
            
        except Exception as e:
            print(f"⚠️ Error scanning links: {e}")
        
        return discovered_urls
    
    def _is_url_related_to_base(self, url: str, base_url: str) -> bool:
        """Check if URL is related to base URL."""
        try:
            parsed_url = urllib.parse.urlparse(url)
            parsed_base = urllib.parse.urlparse(base_url)
            
            if parsed_url.netloc != parsed_base.netloc:
                return False
            
            base_path = parsed_base.path.rstrip('/')
            url_path = parsed_url.path
            
            return base_path == '' or url_path.startswith(base_path) or base_path.startswith(url_path.rstrip('/'))
        except:
            return False
    
    def _generate_title_from_url(self, url: str) -> str:
        """Generate title from URL."""
        parsed = urllib.parse.urlparse(url)
        path = parsed.path.strip('/')
        
        if path:
            title = path.split('/')[-1]
            title = re.sub(r'\.[^.]+$', '', title)
            title = re.sub(r'[_-]+', ' ', title)
            return title.title()
        return parsed.netloc
    
    def _extract_main_content(self, soup) -> str:
        """Extract main content from HTML."""
        # Remove scripts and styles
        for script in soup(["script", "style"]):
            script.decompose()
        
        # Try content selectors
        selectors = ['main', 'article', '.content', '#content', '.post']
        for selector in selectors:
            element = soup.select_one(selector)
            if element:
                content = element.get_text()
                return re.sub(r'\s+', ' ', content).strip()
        
        # Fallback to body
        body = soup.find('body')
        if body:
            content = body.get_text()
            return re.sub(r'\s+', ' ', content).strip()
        
        return ""
    
    # MARK: - Performance Optimization Methods
    
    def _generate_cache_key(self, file_paths: List[str], urls: List[str], topic: str, max_pages: int) -> str:
        """Generate a cache key for the processing request."""
        content = f"{topic}:{max_pages}:{':'.join(sorted(file_paths))}:{':'.join(sorted(urls))}"
        return hashlib.md5(content.encode()).hexdigest()
    
    def _load_from_cache(self, cache_key: str) -> Optional[Dict[str, Any]]:
        """Load results from cache if available and valid."""
        if not ENABLE_CACHING:
            return None
            
        cache_file = os.path.join(CACHE_DIR, f"{cache_key}.pkl")
        
        try:
            if os.path.exists(cache_file):
                # Check if cache is still valid
                cache_time = datetime.fromtimestamp(os.path.getmtime(cache_file))
                if datetime.now() - cache_time < timedelta(hours=CACHE_EXPIRY_HOURS):
                    with open(cache_file, 'rb') as f:
                        return pickle.load(f)
                else:
                    # Remove expired cache
                    os.remove(cache_file)
        except Exception as e:
            print(f"⚠️ Cache loading failed: {e}")
            
        return None
    
    def _save_to_cache(self, cache_key: str, data: Dict[str, Any]) -> None:
        """Save results to cache."""
        if not ENABLE_CACHING:
            return
            
        cache_file = os.path.join(CACHE_DIR, f"{cache_key}.pkl")
        
        try:
            with open(cache_file, 'wb') as f:
                pickle.dump(data, f)
        except Exception as e:
            print(f"⚠️ Cache saving failed: {e}")
    
    def _process_files_concurrent(self, file_paths: List[str], metadata: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Process files concurrently for improved performance."""
        processed_sources = []
        
        valid_paths = [path for path in file_paths if path.strip()]
        if not valid_paths:
            return processed_sources
        
        try:
            with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_CONCURRENT_REQUESTS) as executor:
                # Submit all file processing tasks
                future_to_path = {
                    executor.submit(self.process_file_or_folder, path): path 
                    for path in valid_paths
                }
                
                # Collect results as they complete
                for future in concurrent.futures.as_completed(future_to_path):
                    path = future_to_path[future]
                    try:
                        sources, meta = future.result()
                        processed_sources.extend(sources)
                        
                        if meta['is_folder']:
                            metadata['folders_scanned'] += 1
                            metadata['files_processed'] += meta['files_count']
                        else:
                            metadata['files_processed'] += 1
                            
                    except Exception as e:
                        error_msg = f"Error processing {path}: {str(e)}"
                        metadata['errors'].append(error_msg)
                        
        except Exception as e:
            print(f"⚠️ Concurrent processing failed, falling back to sequential: {e}")
            # Fallback to sequential processing
            for path in valid_paths:
                try:
                    sources, meta = self.process_file_or_folder(path)
                    processed_sources.extend(sources)
                    
                    if meta['is_folder']:
                        metadata['folders_scanned'] += 1
                        metadata['files_processed'] += meta['files_count']
                    else:
                        metadata['files_processed'] += 1
                        
                except Exception as e:
                    error_msg = f"Error processing {path}: {str(e)}"
                    metadata['errors'].append(error_msg)
        
        return processed_sources
    
    def _ai_filter_urls(self, urls: List[str], topic: str, max_urls: int) -> List[str]:
        """Use AI to filter URLs by relevance to the topic."""
        if not self.ai_url_filter or not urls:
            return self._fallback_heuristic_filter(urls, topic, max_urls)
        
        try:
            self.processing_stats["ai_url_analyses"] += 1
            print(f"🤖 AI analyzing {len(urls)} URLs for relevance to '{topic}'")
            
            # Prepare URLs for analysis (limit to avoid token overload)
            urls_to_analyze = urls[:20]  # Limit for token efficiency
            url_list = "\n".join([f"{i+1}. {url}" for i, url in enumerate(urls_to_analyze)])
            
            # Create analysis prompt
            system_message = SystemMessage(content=f"""
            You are an expert web content analyst. Analyze the following URLs for their relevance 
            to the topic "{topic}". 
            
            Rate each URL's relevance as:
            - HIGH: Directly addresses the topic (score 0.8-1.0)
            - MEDIUM: Related to the topic (score 0.5-0.7) 
            - LOW: Tangentially related (score 0.2-0.4)
            - NONE: Unrelated (score 0.0-0.1)
            
            Consider URL structure, keywords, and likely content type.
            """)
            
            human_message = HumanMessage(content=f"""
            Analyze these URLs for relevance to "{topic}":
            
            {url_list}
            
            Return only the URLs with HIGH or MEDIUM relevance, one per line, in order of relevance.
            Maximum {max_urls} URLs.
            """)
            
            response = self.ai_url_filter.invoke([system_message, human_message])
            
            # Parse response to extract URLs
            relevant_urls = []
            for line in response.content.split('\n'):
                line = line.strip()
                if line and ('http://' in line or 'https://' in line):
                    # Extract URL from the line
                    for url in urls_to_analyze:
                        if url in line:
                            relevant_urls.append(url)
                            break
            
            # Remove duplicates while preserving order
            seen = set()
            filtered_urls = []
            for url in relevant_urls:
                if url not in seen:
                    seen.add(url)
                    filtered_urls.append(url)
            
            result = filtered_urls[:max_urls]
            print(f"✅ AI selected {len(result)} relevant URLs")
            return result
            
        except Exception as e:
            print(f"⚠️ AI URL filtering failed: {e}, using heuristic fallback")
            return self._fallback_heuristic_filter(urls, topic, max_urls)
    
    def _fallback_heuristic_filter(self, urls: List[str], topic: str, max_urls: int) -> List[str]:
        """Fallback heuristic URL filtering when AI is unavailable."""
        scored_urls = []
        topic_words = topic.lower().split()
        
        for url in urls:
            score = 0.0
            url_lower = url.lower()
            
            # Topic keywords in URL
            for word in topic_words:
                if word in url_lower:
                    score += 1.0
            
            # Prefer content patterns
            prefer_patterns = ['blog', 'article', 'post', 'guide', 'tutorial', 'docs', 'learn']
            for pattern in prefer_patterns:
                if pattern in url_lower:
                    score += 1.5
            
            # Avoid unwanted patterns
            avoid_patterns = ['login', 'register', 'admin', 'cart', 'privacy', 'terms', 'contact']
            for pattern in avoid_patterns:
                if pattern in url_lower:
                    score -= 1.0
            
            scored_urls.append((url, max(0.0, score)))
        
        # Sort by score and return top URLs
        scored_urls.sort(key=lambda x: x[1], reverse=True)
        return [url for url, score in scored_urls[:max_urls]]
    
    def get_processing_stats(self) -> Dict[str, Any]:
        """Get performance statistics for the processor."""
        return {
            **self.processing_stats,
            "cache_hit_rate": (
                self.processing_stats["cache_hits"] / 
                max(1, self.processing_stats["cache_hits"] + self.processing_stats["cache_misses"])
            ),
            "total_cache_operations": self.processing_stats["cache_hits"] + self.processing_stats["cache_misses"],
            "ai_filter_enabled": self.ai_url_filter is not None
        }
    
    def clear_cache(self) -> None:
        """Clear the processing cache."""
        if not ENABLE_CACHING:
            return
            
        try:
            for file in os.listdir(CACHE_DIR):
                if file.endswith('.pkl'):
                    os.remove(os.path.join(CACHE_DIR, file))
            print("🗑️ Processing cache cleared")
        except Exception as e:
            print(f"⚠️ Failed to clear cache: {e}")


def process_manual_sources_sync(
    file_paths: List[str], 
    urls: List[str], 
    topic: str, 
    max_pages: int = 10,
    openai_api_key: Optional[str] = None
) -> Dict[str, Any]:
    """
    Synchronous wrapper for processing manual sources with performance optimizations.
    
    Args:
        file_paths: List of file or folder paths to process
        urls: List of URLs to process and expand
        topic: Topic for context in URL expansion and filtering
        max_pages: Maximum pages to discover per URL
        openai_api_key: Optional OpenAI API key for AI-powered URL filtering
        
    Returns:
        Dictionary containing processed sources, metadata, and performance stats
    """
    print(f"🔧 Enhanced source processing called:")
    print(f"   📁 Files/folders: {len(file_paths)}")
    print(f"   🌐 URLs: {len(urls)}")
    print(f"   📝 Topic: {topic}")
    print(f"   🔑 AI filtering: {'enabled' if openai_api_key else 'disabled'}")
    print(f"   📚 Dependencies: requests={REQUESTS_AVAILABLE}, langchain={LANGCHAIN_AVAILABLE}")
    
    try:
        processor = EnhancedSourceProcessor(openai_api_key=openai_api_key)
        result = processor.process_manual_sources(file_paths, urls, topic, max_pages)
        print(f"✅ Enhanced processing completed successfully:")
        print(f"   📊 Total sources: {result.get('total_sources', 0)}")
        print(f"   ⏱️  Processing time: {result.get('processing_time_seconds', 0):.2f}s")
        if result.get('metadata', {}).get('errors'):
            print(f"   ⚠️  Errors: {len(result['metadata']['errors'])}")
        return result
    except Exception as e:
        print(f"❌ Enhanced processing failed: {str(e)}")
        if 'requests' in str(e).lower() or 'beautifulsoup' in str(e).lower():
            print("   💡 Missing web scraping dependencies - URL processing disabled")
        elif 'langchain' in str(e).lower():
            print("   💡 Missing AI dependencies - using heuristic URL filtering")
        
        # Return error result instead of crashing
        return {
            'sources': [],
            'metadata': {
                'files_processed': 0,
                'folders_scanned': 0,
                'urls_expanded': 0,
                'total_discovered_pages': 0,
                'errors': [f"Processing failed: {str(e)}"],
                'performance_stats': {}
            },
            'total_sources': 0,
            'processing_time_seconds': 0.0,
            'performance_stats': {}
        }


if __name__ == "__main__":
    print("🧪 Testing Enhanced Source Processing...")
    test_files = ["README.md"] if os.path.exists("README.md") else []
    test_urls = ["https://example.com"]
    result = process_manual_sources_sync(test_files, test_urls, "testing", 3)
    print(f"✅ Test: {result['total_sources']} sources processed") 