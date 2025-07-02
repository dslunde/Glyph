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
from typing import List, Dict, Any, Optional, Tuple, Set
from pathlib import Path

try:
    import requests
    from bs4 import BeautifulSoup
    REQUESTS_AVAILABLE = True
except ImportError:
    REQUESTS_AVAILABLE = False
    print("⚠️ requests and beautifulsoup4 not available - URL processing disabled")

# Configuration - can be overridden by function parameters
DEFAULT_MAX_DISCOVERED_PAGES = 10
SUPPORTED_TEXT_EXTENSIONS = {
    '.txt', '.md', '.markdown', '.rst', '.py', '.js', '.html', 
    '.htm', '.css', '.json', '.xml', '.yaml', '.yml', '.csv', '.log'
}

class EnhancedSourceProcessor:
    """Main class for processing manual sources with intelligence."""
    
    def __init__(self):
        self.discovered_urls: Set[str] = set()
        self.processed_files: Set[str] = set()
        
    def process_manual_sources(
        self, 
        file_paths: List[str], 
        urls: List[str], 
        topic: str,
        max_pages: int = DEFAULT_MAX_DISCOVERED_PAGES
    ) -> Dict[str, Any]:
        """Process all manual sources into formatted source data."""
        print(f"🔄 Processing manual sources for topic: {topic}")
        
        processed_sources = []
        metadata = {
            'files_processed': 0,
            'folders_scanned': 0,
            'urls_expanded': 0,
            'total_discovered_pages': 0,
            'errors': []
        }
        
        # Process files and folders
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
        
        print(f"✅ Processed {len(processed_sources)} sources total")
        return {
            'sources': processed_sources,
            'metadata': metadata,
            'total_sources': len(processed_sources)
        }
    
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
            
            # Filter using simple heuristics (LangGraph placeholder)
            if len(discovered) > max_pages:
                discovered = self._filter_urls_by_relevance(discovered, topic, base_url, max_pages)
            
            discovered = discovered[:max_pages]
            print(f"🔍 Discovered {len(discovered)} related URLs")
            return discovered
            
        except Exception as e:
            print(f"❌ Error discovering URLs: {e}")
            return []
    
    def extract_url_content(self, url: str) -> Optional[Dict[str, Any]]:
        """Extract content from URL."""
        try:
            headers = {'User-Agent': 'Mozilla/5.0 (compatible; Glyph/1.0)'}
            response = requests.get(url, headers=headers, timeout=10)
            response.raise_for_status()
            
            soup = BeautifulSoup(response.content, 'html.parser')
            
            title = soup.find('title')
            title_text = title.get_text().strip() if title else self._generate_title_from_url(url)
            
            content = self._extract_main_content(soup)
            
            source = {
                'title': title_text,
                'content': content[:5000],
                'url': url,
                'score': 0.8,
                'published_date': '',
                'query': f"URL: {url}",
                'reliability_score': 75,
                'source_type': 'url',
                'word_count': len(content.split()),
                'domain': urllib.parse.urlparse(url).netloc
            }
            
            print(f"🌐 Extracted: {title_text}")
            return source
            
        except Exception as e:
            print(f"❌ Failed to extract {url}: {e}")
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
    
    def _filter_urls_by_relevance(self, urls: List[str], topic: str, base_url: str, max_pages: int) -> List[str]:
        """Filter URLs by relevance (LangGraph placeholder)."""
        scored_urls = []
        
        for url in urls:
            score = self._calculate_relevance_score(url, topic, base_url)
            scored_urls.append((url, score))
        
        scored_urls.sort(key=lambda x: x[1], reverse=True)
        selected = [url for url, score in scored_urls[:max_pages]]
        
        print(f"🤖 Selected {len(selected)} most relevant URLs")
        return selected
    
    def _calculate_relevance_score(self, url: str, topic: str, base_url: str) -> float:
        """Calculate relevance score for URL."""
        score = 0.0
        url_lower = url.lower()
        topic_words = topic.lower().split()
        
        # Topic keywords in URL
        for word in topic_words:
            if word in url_lower:
                score += 1.0
        
        # Closer to base URL
        if url.startswith(base_url.rstrip('/')):
            score += 2.0
        
        # Avoid certain patterns
        avoid = ['login', 'register', 'admin', 'cart', 'privacy', 'terms']
        for pattern in avoid:
            if pattern in url_lower:
                score -= 1.0
        
        # Prefer content patterns
        prefer = ['blog', 'article', 'post', 'guide', 'tutorial', 'docs']
        for pattern in prefer:
            if pattern in url_lower:
                score += 1.5
        
        return max(0.0, score)
    
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


def process_manual_sources_sync(file_paths: List[str], urls: List[str], topic: str, max_pages: int = 10) -> Dict[str, Any]:
    """Synchronous wrapper for processing manual sources."""
    processor = EnhancedSourceProcessor()
    return processor.process_manual_sources(file_paths, urls, topic, max_pages)


if __name__ == "__main__":
    print("🧪 Testing Enhanced Source Processing...")
    test_files = ["README.md"] if os.path.exists("README.md") else []
    test_urls = ["https://example.com"]
    result = process_manual_sources_sync(test_files, test_urls, "testing", 3)
    print(f"✅ Test: {result['total_sources']} sources processed") 