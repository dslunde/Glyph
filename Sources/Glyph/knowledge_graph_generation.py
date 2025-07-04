#!/usr/bin/env python3
"""
Knowledge Graph Generation for Glyph
===================================

This module implements knowledge graph generation from collected sources using:
- NLP processing to extract concepts, entities, and relationships
- NetworkX for graph construction and analysis
- Centrality metrics (PageRank, Eigenvector, Betweenness, Closeness)
- Minimal subgraph extraction with topological sorting
- Optimized storage and retrieval

Performance targets: 1,000-1,000,000 nodes, max 10GB RAM
"""

import os
import sys
import json
import pickle
import gzip
import hashlib
import tempfile
import uuid
from typing import List, Dict, Any, Optional, Tuple, Set, Callable
from datetime import datetime
from collections import defaultdict, Counter
import re

# Core libraries
import numpy as np
try:
    from scipy.sparse import csr_matrix, save_npz, load_npz
    SCIPY_AVAILABLE = True
except ImportError:
    SCIPY_AVAILABLE = False

import networkx as nx

# NLP libraries
try:
    import nltk
    from nltk.corpus import stopwords
    from nltk.tokenize import word_tokenize, sent_tokenize
    from nltk.chunk import ne_chunk
    from nltk.tag import pos_tag
    NLTK_AVAILABLE = True
    
    # Download required NLTK data (Python 3.13+ compatibility)
    try:
        nltk.data.find('tokenizers/punkt')
        nltk.data.find('corpora/stopwords')
        # Try new format first, then fall back to old format
        try:
            nltk.data.find('taggers/averaged_perceptron_tagger_eng')
        except LookupError:
            nltk.data.find('taggers/averaged_perceptron_tagger')
        nltk.data.find('chunkers/maxent_ne_chunker')
        nltk.data.find('corpora/words')
    except LookupError:
        print("📦 Downloading required NLTK data...")
        nltk.download('punkt', quiet=True)
        nltk.download('stopwords', quiet=True)
        # Download both formats for maximum compatibility
        nltk.download('averaged_perceptron_tagger', quiet=True)
        nltk.download('averaged_perceptron_tagger_eng', quiet=True)
        nltk.download('maxent_ne_chunker', quiet=True)
        nltk.download('words', quiet=True)
        
except ImportError:
    print("❌ NLTK not available - using basic text processing")
    NLTK_AVAILABLE = False

try:
    from sentence_transformers import SentenceTransformer
    SENTENCE_TRANSFORMERS_AVAILABLE = True
    print("✅ Sentence Transformers available")
except ImportError:
    print("❌ Sentence Transformers not available")
    SENTENCE_TRANSFORMERS_AVAILABLE = False

try:
    from sklearn.metrics.pairwise import cosine_similarity
    SKLEARN_AVAILABLE = True
    print("✅ Scikit-learn available for similarity calculations")
except ImportError:
    print("❌ Scikit-learn not available - topic relevance filtering will be limited")
    SKLEARN_AVAILABLE = False

try:
    from transformers import pipeline  # type: ignore
    TRANSFORMERS_AVAILABLE = True
    print("✅ Transformers available")
except ImportError:
    print("❌ Transformers not available")
    TRANSFORMERS_AVAILABLE = False

# LangSmith tracing
try:
    from langsmith import traceable  # type: ignore
    LANGSMITH_AVAILABLE = True
except ImportError:
    LANGSMITH_AVAILABLE = False
    
    def traceable(name: Optional[str] = None):  # type: ignore
        def decorator(func):  # type: ignore
            return func
        return decorator


class TopicRelevanceConfig:
    """Configuration for topic relevance and source connectivity filtering in knowledge graph generation.
    
    This class defines the parameters used to filter nodes based on their relevance
    to the main topic of study and their connections to original sources, helping to 
    create more focused and trustworthy knowledge graphs.
    
    Attributes:
        relevance_threshold: Minimum semantic similarity score for nodes to be retained.
        enable_semantic_filtering: Whether to use semantic similarity filtering.
        enable_context_filtering: Whether to use context-based filtering as fallback.
        max_nodes_before_filtering: Maximum number of nodes before applying filtering.
        similarity_batch_size: Batch size for similarity calculations to manage memory.
        enable_source_connectivity_filtering: Whether to filter concepts without source connections.
        require_verified_sources: Whether source references must match original source titles.
        enable_deduplication: Whether to deduplicate similar concepts in learning plans.
        deduplication_similarity_threshold: Threshold for fuzzy concept matching (0.0-1.0).
    """
    
    def __init__(
        self,
        relevance_threshold: float = 0.3,
        enable_semantic_filtering: bool = True,
        enable_context_filtering: bool = True,
        max_nodes_before_filtering: int = 1000,
        similarity_batch_size: int = 32,
        enable_source_connectivity_filtering: bool = True,
        require_verified_sources: bool = True,
        enable_deduplication: bool = True,
        deduplication_similarity_threshold: float = 0.75
    ) -> None:
        """Initialize topic relevance configuration.
        
        Args:
            relevance_threshold: Minimum similarity score (0.0-1.0) for node retention.
            enable_semantic_filtering: Enable semantic similarity filtering.
            enable_context_filtering: Enable context-based filtering fallback.
            max_nodes_before_filtering: Apply filtering only if nodes exceed this count.
            similarity_batch_size: Batch size for similarity calculations.
            enable_source_connectivity_filtering: Filter concepts without source connections.
            require_verified_sources: Require source references to match original sources.
            enable_deduplication: Whether to deduplicate similar concepts in learning plans.
            deduplication_similarity_threshold: Threshold for fuzzy concept matching (0.0-1.0).
        """
        self.relevance_threshold = relevance_threshold
        self.enable_semantic_filtering = enable_semantic_filtering
        self.enable_context_filtering = enable_context_filtering
        self.max_nodes_before_filtering = max_nodes_before_filtering
        self.similarity_batch_size = similarity_batch_size
        self.enable_source_connectivity_filtering = enable_source_connectivity_filtering
        self.require_verified_sources = require_verified_sources
        self.enable_deduplication = enable_deduplication
        self.deduplication_similarity_threshold = deduplication_similarity_threshold


class KnowledgeGraphBuilder:
    """Main class for building knowledge graphs from source collections."""
    
    def __init__(
        self, 
        cache_dir: Optional[str] = None,
        topic_config: Optional[TopicRelevanceConfig] = None
    ) -> None:
        """Initialize the knowledge graph builder.
        
        Args:
            cache_dir: Directory for caching models and intermediate results.
            topic_config: Configuration for topic relevance filtering.
        """
        if cache_dir is None:
            # Debug environment variable detection
            app_bundle_mode = os.getenv('APP_BUNDLE_MODE')
            print(f"🔍 Environment check: APP_BUNDLE_MODE = {app_bundle_mode}")
            
            # Use appropriate cache directory for macOS app bundles
            if app_bundle_mode == '1':
                # Running in app bundle - use user cache directory
                home_dir = os.path.expanduser("~")
                self.cache_dir = os.path.join(home_dir, "Library", "Caches", "com.glyph.knowledge-graph-explorer")
                print(f"📁 App bundle mode detected - using cache directory: {self.cache_dir}")
            else:
                # Development mode - use local cache
                self.cache_dir = "./graph_cache"
                print(f"📁 Development mode - using cache directory: {self.cache_dir}")
        else:
            self.cache_dir = cache_dir
            print(f"📁 Custom cache directory: {self.cache_dir}")
            
        # Create cache directory with proper error handling
        try:
            os.makedirs(self.cache_dir, exist_ok=True)
            print(f"✅ Cache directory ready: {self.cache_dir}")
        except OSError as e:
            print(f"⚠️ Failed to create cache directory {self.cache_dir}: {e}")
            # Fallback to temp directory with clear reason
            self.cache_dir = tempfile.mkdtemp(prefix="glyph_cache_")
            print(f"🔄 FALLBACK: Using temporary cache directory due to permissions issue: {self.cache_dir}")
            print(f"   Reason: Could not create/access intended cache directory")
        
        # Status file for Swift communication
        self.status_file = os.path.join(self.cache_dir, "kg_status.json")
        self.run_id = str(uuid.uuid4())[:8]  # Short run ID for this session
        
        # Initialize NLP components
        self.sentence_transformer = None
        self.ner_pipeline = None
        self.stopwords_set = set()
        
        # Graph storage
        self.graph = nx.DiGraph()
        self.node_embeddings = {}
        self.edge_weights = {}
        
        # Analysis results
        self.centrality_scores = {}
        self.minimal_subgraph = None
        
        # Progress tracking
        self.progress_callback = None
        self.current_progress = 0.0
        
        # Topic relevance configuration
        self.topic_config = topic_config or TopicRelevanceConfig()
        
        self._initialize_nlp_components()
    
    def _initialize_nlp_components(self):
        """Initialize NLP components with fallbacks."""
        print("🧠 Initializing NLP components...")
        
        # Initialize sentence transformer for embeddings
        if SENTENCE_TRANSFORMERS_AVAILABLE:
            try:
                model_path = os.path.join(self.cache_dir, "sentence_transformer")
                if os.path.exists(model_path):
                    self.sentence_transformer = SentenceTransformer(model_path)
                else:
                    # Use a lightweight model for fast initialization
                    self.sentence_transformer = SentenceTransformer('all-MiniLM-L6-v2')
                    self.sentence_transformer.save(model_path)
                print("✅ Sentence transformer loaded")
            except Exception as e:
                print(f"⚠️ Sentence transformer failed: {e}")
        
        # Initialize NER pipeline
        if TRANSFORMERS_AVAILABLE:
            try:
                # Use a simpler approach for NER pipeline initialization
                self.ner_pipeline = pipeline("ner", aggregation_strategy="simple")  # type: ignore
                print("✅ NER pipeline loaded")
            except Exception as e:
                print(f"⚠️ NER pipeline failed: {e}")
        
        # Initialize stopwords
        if NLTK_AVAILABLE:
            try:
                self.stopwords_set = set(stopwords.words('english'))
                print("✅ Stopwords loaded")
            except:
                pass
        
        # Fallback stopwords
        if not self.stopwords_set:
            self.stopwords_set = {
                'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 
                'of', 'with', 'by', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
                'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could',
                'should', 'may', 'might', 'must', 'can', 'this', 'that', 'these', 'those'
            }
    
    def set_progress_callback(self, callback):
        """Set callback function for progress updates."""
        self.progress_callback = callback
    
    def _update_progress(self, progress: float, message: str = ""):
        """Update progress and call callback if set."""
        self.current_progress = progress
        if self.progress_callback:
            self.progress_callback(progress, message)
        if message:
            print(f"📊 {progress:.1%}: {message}")
        
        # Write status checkpoint for Swift to read
        self._write_status_checkpoint(progress, message)
    
    def _write_status_checkpoint(self, progress: float, message: str, error: Optional[str] = None):
        """Write status checkpoint to file for Swift communication."""
        try:
            status = {
                "run_id": self.run_id,
                "timestamp": datetime.now().isoformat(),
                "progress": progress,
                "message": message,
                "current_step": message.split(":")[1].strip() if ":" in message else message,
                "completed": progress >= 1.0,
                "error": error,
                "nodes_count": self.graph.number_of_nodes() if hasattr(self, 'graph') else 0,
                "edges_count": self.graph.number_of_edges() if hasattr(self, 'graph') else 0
            }
            
            with open(self.status_file, 'w') as f:
                json.dump(status, f)
            
            # Debug: Confirm file was written
            if progress in [0.0, 0.3, 0.7, 1.0]:  # Log key milestones
                print(f"📝 Status written to {self.status_file}: {progress:.1%} - {message}")
                
        except Exception as e:
            # Don't let status writing break the main process
            print(f"⚠️ Failed to write status checkpoint to {self.status_file}: {e}")
            print(f"   Cache dir exists: {os.path.exists(self.cache_dir)}")
            print(f"   Cache dir writable: {os.access(self.cache_dir, os.W_OK) if os.path.exists(self.cache_dir) else 'N/A'}")
    
    def _clear_status_file(self):
        """Clear status file at start of process."""
        try:
            if os.path.exists(self.status_file):
                os.remove(self.status_file)
        except Exception as e:
            print(f"⚠️ Failed to clear status file: {e}")
    
    @traceable(name="build_knowledge_graph")
    def build_graph_from_sources(
        self, 
        sources: List[Dict[str, Any]], 
        topic: str = ""
    ) -> Dict[str, Any]:
        """Build knowledge graph from collected sources with topic relevance filtering.
        
        Args:
            sources: List of source documents to process.
            topic: Main topic/subject for relevance filtering.
            
        Returns:
            Dictionary containing the generated knowledge graph data.
        """
        print(f"🏗️ Building knowledge graph from {len(sources)} sources...")
        if topic.strip():
            print(f"🎯 Topic focus: '{topic}' (filtering enabled)")
        else:
            print("🎯 No specific topic focus (filtering disabled)")
        
        # Clear status file from any previous runs
        self._clear_status_file()
        
        self._update_progress(0.0, "Starting knowledge graph construction")
        
        # Clear previous data
        self.graph.clear()
        self.node_embeddings.clear()
        self.edge_weights.clear()
        self.centrality_scores.clear()
        
        try:
            # Step 1: Extract concepts and entities (25%)
            self._update_progress(0.1, "Extracting concepts and entities")
            concepts, entities = self._extract_concepts_and_entities(sources)
            
            # Step 2: Build initial graph (40%)
            self._update_progress(0.25, "Building initial graph structure")
            self._build_graph_structure(concepts, entities, sources)
            
            # Step 3: Filter by topic relevance (50%) - NEW STEP
            if topic.strip():
                self._update_progress(0.4, "Filtering nodes by topic relevance")
                self._filter_nodes_by_topic_relevance(topic, sources)
            
            # Step 4: Calculate centrality metrics (65%)
            self._update_progress(0.5, "Calculating centrality metrics")
            self._calculate_centrality_metrics()
            
            # Step 5: Find minimal subgraph (80%)
            self._update_progress(0.65, "Finding minimal subgraph")
            self._find_minimal_subgraph()
            
            # Step 6: Generate embeddings (90%)
            self._update_progress(0.8, "Generating node embeddings")
            self._generate_node_embeddings()
            
            # Step 7: Finalize results (100%)
            self._update_progress(0.9, "Finalizing results")
            result = self._finalize_graph_data()
            
            self._update_progress(1.0, "Knowledge graph construction complete")
            
            print(f"✅ Graph built: {self.graph.number_of_nodes()} nodes, {self.graph.number_of_edges()} edges")
            return result
            
        except Exception as e:
            error_msg = f"Graph construction failed: {e}"
            print(f"❌ {error_msg}")
            
            # Write error status for Swift to read
            self._write_status_checkpoint(0.0, "Error occurred", error=error_msg)
            
            return {
                "success": False,
                "error": str(e),
                "nodes": [],
                "edges": [],
                "metadata": {}
            }
    
    def _extract_concepts_and_entities(
        self, 
        sources: List[Dict[str, Any]]
    ) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
        """Extract concepts and entities from source content."""
        concepts = []
        entities = []
        concept_counts = Counter()
        entity_counts = Counter()
        
        # Track which sources contributed to each concept/entity
        concept_sources = defaultdict(list)
        entity_sources = defaultdict(list)
        
        for i, source in enumerate(sources):
            progress = 0.1 + (i / len(sources)) * 0.2
            self._update_progress(progress, f"Processing source {i+1}/{len(sources)}")
            
            content = source.get('content', '')
            title = source.get('title', '')
            url = source.get('url', '')
            source_title = title if title else f"Source {i+1}"
            
            # Extract text concepts
            text_concepts = self._extract_text_concepts(content + ' ' + title)
            for concept in text_concepts:
                concept_counts[concept] += 1
                concept_sources[concept].append({
                    'title': source_title,
                    'url': url,
                    'type': source.get('source_type', 'web')
                })
            
            # Extract named entities
            text_entities = self._extract_named_entities(content)
            for entity in text_entities:
                entity_counts[entity] += 1
                entity_sources[entity].append({
                    'title': source_title,
                    'url': url,
                    'type': source.get('source_type', 'web')
                })
        
        # Convert to graph nodes with frequency-based importance and source references
        for concept, count in concept_counts.most_common(500):  # Limit to top 500
            concepts.append({
                'id': f"concept_{hashlib.md5(concept.encode()).hexdigest()[:8]}",
                'label': concept,
                'type': 'concept',
                'frequency': count,
                'importance': min(count / len(sources), 1.0),
                'source_references': list({
                    f"{ref['title']} ({ref['type']})" for ref in concept_sources[concept]
                })[:5]  # Limit to top 5 source references
            })
        
        for entity, count in entity_counts.most_common(300):  # Limit to top 300
            entities.append({
                'id': f"entity_{hashlib.md5(entity.encode()).hexdigest()[:8]}",
                'label': entity,
                'type': 'entity',
                'frequency': count,
                'importance': min(count / len(sources), 1.0),
                'source_references': list({
                    f"{ref['title']} ({ref['type']})" for ref in entity_sources[entity]
                })[:5]  # Limit to top 5 source references
            })
        
        print(f"📝 Extracted {len(concepts)} concepts and {len(entities)} entities")
        return concepts, entities
    
    def _extract_text_concepts(self, text: str) -> List[str]:
        """Extract key concepts from text using NLP."""
        concepts = []
        
        if not text.strip():
            return concepts
        
        # Clean and tokenize text
        text = re.sub(r'[^\w\s]', ' ', text.lower())
        
        if NLTK_AVAILABLE:
            try:
                # Use NLTK for better tokenization and POS tagging
                tokens = word_tokenize(text)
                pos_tags = pos_tag(tokens)
                
                # Extract nouns and noun phrases as concepts
                current_phrase = []
                for word, pos in pos_tags:
                    if pos.startswith('NN') and word not in self.stopwords_set and len(word) > 2:
                        current_phrase.append(word)
                    else:
                        if current_phrase:
                            phrase = ' '.join(current_phrase)
                            if len(phrase.split()) <= 3:  # Limit phrase length
                                concepts.append(phrase)
                            current_phrase = []
                
                # Add final phrase if exists
                if current_phrase:
                    phrase = ' '.join(current_phrase)
                    if len(phrase.split()) <= 3:
                        concepts.append(phrase)
                        
            except Exception as e:
                print(f"⚠️ NLTK processing failed: {e}")
                # Fallback to simple extraction
                concepts = self._simple_concept_extraction(text)
        else:
            concepts = self._simple_concept_extraction(text)
        
        return list(set(concepts))  # Remove duplicates
    
    def _simple_concept_extraction(self, text: str) -> List[str]:
        """Simple concept extraction fallback."""
        words = text.split()
        concepts = []
        
        # Extract 1-3 word phrases that aren't stopwords
        for i in range(len(words)):
            for phrase_len in [1, 2, 3]:
                if i + phrase_len <= len(words):
                    phrase_words = words[i:i + phrase_len]
                    if all(word not in self.stopwords_set and len(word) > 2 for word in phrase_words):
                        concepts.append(' '.join(phrase_words))
        
        return concepts
    
    def _extract_named_entities(self, text: str) -> List[str]:
        """Extract named entities from text."""
        entities = []
        
        if not text.strip():
            return entities
        
        if self.ner_pipeline:
            try:
                # Use transformer-based NER
                ner_results = self.ner_pipeline(text[:1000])  # Limit text length
                for entity in ner_results:
                    if entity['score'] > 0.9:  # High confidence only
                        entities.append(entity['word'].strip('#'))
            except Exception as e:
                print(f"⚠️ NER pipeline failed: {e}")
        
        elif NLTK_AVAILABLE:
            try:
                # Use NLTK NER as fallback
                tokens = word_tokenize(text)
                pos_tags = pos_tag(tokens)
                chunks = ne_chunk(pos_tags)
                
                for chunk in chunks:
                    if hasattr(chunk, 'label') and callable(getattr(chunk, 'label', None)):  # type: ignore
                        entity = ' '.join([token for token, pos in chunk])
                        entities.append(entity)
            except Exception as e:
                print(f"⚠️ NLTK NER failed: {e}")
        
        return list(set(entities))  # Remove duplicates
    
    def _build_graph_structure(
        self, 
        concepts: List[Dict[str, Any]], 
        entities: List[Dict[str, Any]], 
        sources: List[Dict[str, Any]]
    ):
        """Build the graph structure with nodes and edges."""
        
        # Add nodes to graph
        all_nodes = concepts + entities
        for node in all_nodes:
            self.graph.add_node(
                node['id'], 
                label=node['label'],
                type=node['type'],
                frequency=node['frequency'],
                importance=node['importance'],
                source_references=node.get('source_references', [])
            )
        
        # Create co-occurrence matrix for edge weights
        node_labels = {node['id']: node['label'] for node in all_nodes}
        cooccurrence = defaultdict(lambda: defaultdict(int))
        
        # Calculate co-occurrence in sources
        for source in sources:
            content = (source.get('content', '') + ' ' + source.get('title', '')).lower()
            
            # Find which nodes appear in this source
            appearing_nodes = []
            for node_id, label in node_labels.items():
                if label.lower() in content:
                    appearing_nodes.append(node_id)
            
            # Create edges between co-occurring nodes
            for i, node1 in enumerate(appearing_nodes):
                for node2 in appearing_nodes[i+1:]:
                    cooccurrence[node1][node2] += 1
                    cooccurrence[node2][node1] += 1
        
        # Add edges to graph with weights
        edge_count = 0
        for node1, connections in cooccurrence.items():
            for node2, weight in connections.items():
                if weight >= 2:  # Minimum co-occurrence threshold
                    self.graph.add_edge(node1, node2, weight=weight)
                    edge_count += 1
        
        print(f"🔗 Added {edge_count} weighted edges based on co-occurrence")
    
    def _calculate_centrality_metrics(self):
        """Calculate various centrality metrics for graph analysis."""
        print("📊 Calculating centrality metrics...")
        
        if self.graph.number_of_nodes() == 0:
            print("⚠️ Empty graph - skipping centrality calculations")
            return
        
        try:
            # PageRank (most important for finding core concepts)
            self.centrality_scores['pagerank'] = nx.pagerank(
                self.graph, 
                weight='weight',
                max_iter=100,
                tol=1e-6
            )
            
            # Eigenvector centrality (influence in network)
            try:
                self.centrality_scores['eigenvector'] = nx.eigenvector_centrality(
                    self.graph,
                    weight='weight',
                    max_iter=1000,
                    tol=1e-6
                )
            except nx.PowerIterationFailedConvergence:
                print("⚠️ Eigenvector centrality failed - using degree centrality")
                self.centrality_scores['eigenvector'] = nx.degree_centrality(self.graph)
            
            # Betweenness centrality (bridges between concepts)
            self.centrality_scores['betweenness'] = nx.betweenness_centrality(
                self.graph,
                weight='weight',
                normalized=True
            )
            
            # Closeness centrality (accessibility to other concepts)
            if nx.is_connected(self.graph.to_undirected()):
                self.centrality_scores['closeness'] = nx.closeness_centrality(
                    self.graph,
                    distance='weight'
                )
            else:
                # For disconnected graphs, use harmonic centrality
                self.centrality_scores['closeness'] = nx.harmonic_centrality(
                    self.graph,
                    distance='weight'
                )
            
            print("✅ Centrality metrics calculated successfully")
            
        except Exception as e:
            print(f"❌ Centrality calculation failed: {e}")
            # Fallback to degree centrality
            self.centrality_scores['pagerank'] = nx.degree_centrality(self.graph)
            self.centrality_scores['eigenvector'] = nx.degree_centrality(self.graph)
            self.centrality_scores['betweenness'] = nx.degree_centrality(self.graph)
            self.centrality_scores['closeness'] = nx.degree_centrality(self.graph)
    
    def _find_minimal_subgraph(self):
        """Find minimal subgraph using Minimum Spanning Tree algorithm for cyclical graphs."""
        if not self.centrality_scores or self.graph.number_of_nodes() == 0:
            print("⚠️ No centrality scores available - skipping minimal subgraph")
            return
        
        print(f"🎯 Finding minimal subgraph using MST for {self.graph.number_of_nodes()} nodes...")
        step_start = datetime.now()
        
        # Step 1: Combine centrality scores to create node importance weights
        print("   📊 Computing node importance scores...")
        combined_scores = {}
        for node in self.graph.nodes():
            # Weighted combination of centrality measures
            score = (
                0.4 * self.centrality_scores['pagerank'].get(node, 0) +
                0.3 * self.centrality_scores['eigenvector'].get(node, 0) +
                0.2 * self.centrality_scores['betweenness'].get(node, 0) +
                0.1 * self.centrality_scores['closeness'].get(node, 0)
            )
            combined_scores[node] = score
        print(f"   ✅ Computed importance scores for {len(combined_scores)} nodes")
        
        # Step 2: Create undirected graph with reciprocal edge weights for MST
        print("   🔄 Preparing graph for MST with reciprocal weights...")
        
        # Convert to undirected graph for MST
        undirected_graph = self.graph.to_undirected()
        
        # Create new graph with reciprocal weights
        # High importance edges (high weight) become low cost edges (preferred by MST)
        mst_graph = nx.Graph()
        for node in undirected_graph.nodes():
            mst_graph.add_node(node, **undirected_graph.nodes[node])
        
        for u, v, data in undirected_graph.edges(data=True):
            original_weight = data.get('weight', 1.0)
            # Convert to reciprocal weight (high importance = low cost)
            # Add small epsilon to avoid division by zero
            reciprocal_weight = 1.0 / (original_weight + 1e-6)
            mst_graph.add_edge(u, v, weight=reciprocal_weight, original_weight=original_weight)
        
        print(f"   ✅ Created MST graph with {mst_graph.number_of_nodes()} nodes, {mst_graph.number_of_edges()} edges")
        
        # Step 3: Handle connected vs disconnected graphs
        print("   🔍 Analyzing graph connectivity...")
        components = list(nx.connected_components(mst_graph))
        print(f"   📊 Found {len(components)} connected component(s)")
        
        if len(components) == 1:
            # Single connected component - standard MST
            print("   🌲 Computing single Minimum Spanning Tree...")
            mst_edges = nx.minimum_spanning_tree(mst_graph, weight='weight', algorithm='kruskal')
            print(f"   ✅ MST computed with {mst_edges.number_of_nodes()} nodes, {mst_edges.number_of_edges()} edges")
            
        else:
            # Multiple components - hybrid approach
            print(f"   🔗 Multiple components detected - using hybrid MST approach...")
            
            # Step 3a: Create MST for each component
            component_msts = []
            for i, component in enumerate(components):
                if len(component) > 1:  # Skip single-node components
                    component_graph = mst_graph.subgraph(component)
                    component_mst = nx.minimum_spanning_tree(component_graph, weight='weight', algorithm='kruskal')
                    component_msts.append(component_mst)
                    print(f"      🌲 Component {i+1}: MST with {component_mst.number_of_nodes()} nodes, {component_mst.number_of_edges()} edges")
                else:
                    # Single node component - create a graph with just that node
                    single_node = list(component)[0]
                    single_mst = nx.Graph()
                    single_mst.add_node(single_node, **mst_graph.nodes[single_node])
                    component_msts.append(single_mst)
                    print(f"      🔸 Component {i+1}: Single node {single_node}")
            
            # Step 3b: Connect components using highest centrality nodes
            print(f"   🔗 Connecting {len(component_msts)} components using degree centrality...")
            
            # Create combined graph from all MSTs
            mst_edges = nx.Graph()
            for component_mst in component_msts:
                mst_edges = nx.union(mst_edges, component_mst)
            
            # Find highest degree centrality node in each component MST
            component_connectors = []
            for i, component_mst in enumerate(component_msts):
                if component_mst.number_of_nodes() > 0:
                    # Calculate degree centrality within this component
                    centrality = nx.degree_centrality(component_mst)
                    if centrality:
                        best_node = max(centrality.items(), key=lambda x: x[1])[0]
                        component_connectors.append((best_node, centrality[best_node], i))
                        print(f"      🎯 Component {i+1} connector: {best_node} (centrality: {centrality[best_node]:.3f})")
            
            # Connect components by adding edges between connectors
            # Use a minimum spanning tree approach on the connectors themselves
            if len(component_connectors) > 1:
                print(f"   🔗 Adding {len(component_connectors)-1} inter-component connections...")
                
                # Sort connectors by centrality (highest first)
                component_connectors.sort(key=lambda x: x[1], reverse=True)
                
                # Connect each component to the highest centrality component in a star pattern
                main_connector = component_connectors[0][0]
                
                for connector_node, centrality, comp_idx in component_connectors[1:]:
                    # Add connecting edge with high weight (low reciprocal cost)
                    connection_weight = 0.1  # High importance connection
                    mst_edges.add_edge(main_connector, connector_node, 
                                     weight=connection_weight, 
                                     original_weight=1.0/connection_weight,  # Very high original weight
                                     connection_type='inter_component')
                    print(f"      ➡️  Connected {main_connector} ↔ {connector_node}")
            
            print(f"   ✅ Hybrid MST completed: {mst_edges.number_of_nodes()} nodes, {mst_edges.number_of_edges()} edges")
        
        try:
            # Step 4: Convert back to directed graph with original weights
            print("   🔄 Converting MST back to directed graph...")
            self.minimal_subgraph = nx.DiGraph()
            
            # Add all nodes from MST
            for node in mst_edges.nodes():
                self.minimal_subgraph.add_node(node, **mst_graph.nodes[node])
            
            # Add edges with original weights restored
            for u, v, data in mst_edges.edges(data=True):
                original_weight = data.get('original_weight', 1.0)
                connection_type = data.get('connection_type', 'intra_component')
                
                # For directed graph, we need to determine edge direction
                # Use the original graph to find the correct direction
                if self.graph.has_edge(u, v):
                    self.minimal_subgraph.add_edge(u, v, weight=original_weight, connection_type=connection_type)
                elif self.graph.has_edge(v, u):
                    self.minimal_subgraph.add_edge(v, u, weight=original_weight, connection_type=connection_type)
                else:
                    # For inter-component connections, add both directions
                    self.minimal_subgraph.add_edge(u, v, weight=original_weight, connection_type=connection_type)
                    self.minimal_subgraph.add_edge(v, u, weight=original_weight, connection_type=connection_type)
            
            print(f"   ✅ Minimal subgraph created: {self.minimal_subgraph.number_of_nodes()} nodes, {self.minimal_subgraph.number_of_edges()} edges")
            
            # Step 5: Verify the result
            final_components = nx.number_weakly_connected_components(self.minimal_subgraph)
            print(f"   🔗 Final result has {final_components} connected component(s)")
            
            # Check connectivity
            is_connected = nx.is_weakly_connected(self.minimal_subgraph)
            print(f"   📊 Graph connectivity: {'✅ Connected' if is_connected else '⚠️ Multiple components'}")
            
            # Check if we can now do topological sort
            if nx.is_directed_acyclic_graph(self.minimal_subgraph):
                topo_order = list(nx.topological_sort(self.minimal_subgraph))
                print(f"   📋 ✅ Topological ordering available with {len(topo_order)} nodes")
            else:
                print(f"   📋 ⚠️ Graph still contains cycles (may be due to bidirectional inter-component edges)")
                
        except Exception as e:
            print(f"   ❌ MST computation failed: {e}")
            print("   🔄 Falling back to simple node selection...")
            
            # Fallback: select top nodes by importance
            total_nodes = self.graph.number_of_nodes()
            target_size = min(50, max(10, int(total_nodes * 0.3)))
            top_nodes = sorted(combined_scores.items(), key=lambda x: x[1], reverse=True)
            selected_nodes = [node for node, score in top_nodes[:target_size]]
            
            self.minimal_subgraph = self.graph.subgraph(selected_nodes).copy()
            print(f"   📋 Fallback subgraph: {self.minimal_subgraph.number_of_nodes()} nodes, {self.minimal_subgraph.number_of_edges()} edges")
        
        elapsed = (datetime.now() - step_start).total_seconds()
        print(f"🎯 Minimal subgraph computation completed in {elapsed:.2f}s")
    
    def _generate_node_embeddings(self):
        """Generate embeddings for nodes using sentence transformers."""
        if not self.sentence_transformer:
            print("⚠️ No sentence transformer available - skipping embeddings")
            return
        
        print("🔢 Generating node embeddings...")
        
        try:
            node_texts = []
            node_ids = []
            
            for node_id in self.graph.nodes():
                node_data = self.graph.nodes[node_id]
                text = f"{node_data.get('label', '')} {node_data.get('type', '')}"
                node_texts.append(text)
                node_ids.append(node_id)
            
            if node_texts:
                # Generate embeddings in batches to manage memory
                batch_size = 32
                embeddings = []
                
                for i in range(0, len(node_texts), batch_size):
                    batch = node_texts[i:i + batch_size]
                    batch_embeddings = self.sentence_transformer.encode(batch)
                    embeddings.extend(batch_embeddings)
                
                # Store embeddings
                for node_id, embedding in zip(node_ids, embeddings):
                    self.node_embeddings[node_id] = embedding.tolist()
                
                print(f"✅ Generated embeddings for {len(node_ids)} nodes")
                
        except Exception as e:
            print(f"❌ Embedding generation failed: {e}")
    
    def _calculate_topic_relevance_scores(self, topic: str) -> Dict[str, float]:
        """Calculate semantic similarity scores between nodes and the main topic.
        
        Uses sentence transformers to compute cosine similarity between node labels
        and the main topic, providing a relevance score for each node.
        
        Args:
            topic: The main topic/subject for relevance scoring.
            
        Returns:
            Dictionary mapping node IDs to their relevance scores (0.0-1.0).
            
        Raises:
            Exception: If similarity calculation fails, returns empty dictionary.
        """
        if not self.sentence_transformer or not topic.strip():
            print("⚠️ No sentence transformer or topic available - skipping relevance scoring")
            return {}
        
        if not SKLEARN_AVAILABLE:
            print("⚠️ Scikit-learn not available - using fallback relevance scoring")
            return self._calculate_context_relevance_scores(topic)
        
        print(f"🎯 Calculating topic relevance scores for '{topic}'...")
        
        try:
            # Generate topic embedding
            topic_embedding = self.sentence_transformer.encode([topic])
            
            # Collect node texts and IDs
            node_texts = []
            node_ids = []
            
            for node_id in self.graph.nodes():
                node_data = self.graph.nodes[node_id]
                # Combine label with type for better context
                label = node_data.get('label', '')
                node_type = node_data.get('type', '')
                text = f"{label} {node_type}".strip()
                node_texts.append(text)
                node_ids.append(node_id)
            
            if not node_texts:
                print("⚠️ No nodes found for relevance scoring")
                return {}
            
            # Generate node embeddings in batches to manage memory
            batch_size = self.topic_config.similarity_batch_size
            all_embeddings = []
            
            for i in range(0, len(node_texts), batch_size):
                batch_texts = node_texts[i:i + batch_size]
                batch_embeddings = self.sentence_transformer.encode(batch_texts)
                all_embeddings.extend(batch_embeddings)
            
            # Calculate cosine similarity scores
            node_embeddings = np.array(all_embeddings)
            similarity_scores = cosine_similarity(node_embeddings, topic_embedding).flatten()
            
            # Create relevance score dictionary
            relevance_scores = {}
            for node_id, score in zip(node_ids, similarity_scores):
                relevance_scores[node_id] = float(score)
            
            # Log statistics
            avg_score = np.mean(similarity_scores)
            max_score = np.max(similarity_scores)
            min_score = np.min(similarity_scores)
            
            print(f"✅ Relevance scores calculated for {len(relevance_scores)} nodes")
            print(f"📊 Score statistics - Avg: {avg_score:.3f}, Max: {max_score:.3f}, Min: {min_score:.3f}")
            
            return relevance_scores
            
        except Exception as e:
            print(f"❌ Topic relevance calculation failed: {e}")
            # Fall back to context-based scoring
            return self._calculate_context_relevance_scores(topic)
    
    def _calculate_context_relevance_scores(self, topic: str) -> Dict[str, float]:
        """Calculate relevance scores using context analysis when embeddings aren't available.
        
        This method serves as a fallback when semantic similarity cannot be computed,
        using keyword matching and context analysis instead.
        
        Args:
            topic: The main topic/subject for relevance scoring.
            
        Returns:
            Dictionary mapping node IDs to their relevance scores (0.0-1.0).
        """
        print(f"🔄 Using context-based relevance scoring for '{topic}'")
        
        topic_words = set(topic.lower().split())
        relevance_scores = {}
        
        for node_id in self.graph.nodes():
            node_data = self.graph.nodes[node_id]
            node_label = node_data.get('label', '').lower()
            
            # Calculate relevance score based on:
            # 1. Direct word overlap with topic
            node_words = set(node_label.split())
            word_overlap = len(topic_words & node_words) / max(len(topic_words), 1)
            
            # 2. Frequency-based importance (higher frequency = more relevant)
            frequency_score = min(node_data.get('frequency', 1) / 10.0, 1.0)
            
            # 3. Node type bonus (concepts generally more relevant than entities)
            type_bonus = 0.1 if node_data.get('type') == 'concept' else 0.0
            
            # Combine scores with weights
            final_score = (word_overlap * 0.6) + (frequency_score * 0.3) + type_bonus
            relevance_scores[node_id] = min(final_score, 1.0)
        
        return relevance_scores
    
    def _filter_nodes_by_topic_relevance(self, topic: str, sources: List[Dict[str, Any]]) -> None:
        """Filter out nodes that don't meet the topic relevance threshold.
        
        Removes nodes from the graph that have low semantic similarity to the main topic,
        helping to create more focused knowledge graphs.
        
        Args:
            topic: The main topic/subject for filtering.
            sources: List of source documents (used for context-based filtering).
            
        Raises:
            Exception: Logs errors but continues processing with all nodes.
        """
        if not topic.strip():
            print("⚠️ No topic provided - skipping relevance filtering")
            return
        
        # Check if we should apply filtering
        current_node_count = self.graph.number_of_nodes()
        if current_node_count < self.topic_config.max_nodes_before_filtering:
            print(f"📊 Node count ({current_node_count}) below threshold "
                  f"({self.topic_config.max_nodes_before_filtering}) - skipping filtering")
            return
        
        if not self.topic_config.enable_semantic_filtering:
            print("🔄 Semantic filtering disabled - skipping relevance filtering")
            return
        
        print(f"🔍 Filtering nodes by topic relevance (threshold: {self.topic_config.relevance_threshold})")
        
        try:
            # Calculate relevance scores
            relevance_scores = self._calculate_topic_relevance_scores(topic)
            
            if not relevance_scores:
                print("⚠️ No relevance scores calculated - keeping all nodes")
                return
            
            # Identify nodes to remove
            nodes_to_remove = []
            nodes_to_keep = []
            
            for node_id, score in relevance_scores.items():
                if score < self.topic_config.relevance_threshold:
                    nodes_to_remove.append(node_id)
                else:
                    nodes_to_keep.append(node_id)
            
            # Ensure we don't remove too many nodes (keep at least 10% of original)
            min_nodes_to_keep = max(10, int(current_node_count * 0.1))
            
            if len(nodes_to_keep) < min_nodes_to_keep:
                print(f"⚠️ Would remove too many nodes ({len(nodes_to_remove)}/{current_node_count})")
                print(f"🔄 Keeping top {min_nodes_to_keep} nodes instead")
                
                # Keep the highest scoring nodes
                sorted_nodes = sorted(relevance_scores.items(), key=lambda x: x[1], reverse=True)
                nodes_to_keep = [node_id for node_id, _ in sorted_nodes[:min_nodes_to_keep]]
                nodes_to_remove = [node_id for node_id, _ in sorted_nodes[min_nodes_to_keep:]]
            
            # Remove irrelevant nodes
            if nodes_to_remove:
                self.graph.remove_nodes_from(nodes_to_remove)
                removed_count = len(nodes_to_remove)
                remaining_count = self.graph.number_of_nodes()
                
                print(f"🧹 Removed {removed_count} irrelevant nodes "
                      f"({removed_count/current_node_count:.1%} of original)")
                print(f"📊 Remaining: {remaining_count} nodes "
                      f"({remaining_count/current_node_count:.1%} of original)")
                
                # Store relevance scores in node properties for later use
                for node_id in self.graph.nodes():
                    if node_id in relevance_scores:
                        self.graph.nodes[node_id]['topic_relevance'] = relevance_scores[node_id]
                
                # Log some examples of removed vs kept nodes
                if removed_count > 0:
                    removed_examples = [(node_id, relevance_scores[node_id]) 
                                      for node_id in nodes_to_remove[:3]]
                    kept_examples = [(node_id, relevance_scores[node_id]) 
                                   for node_id in nodes_to_keep[:3]]
                    
                    print("🗑️  Examples of removed nodes:")
                    for node_id, score in removed_examples:
                        label = self.graph.nodes.get(node_id, {}).get('label', node_id)
                        print(f"   - {label} (score: {score:.3f})")
                    
                    print("✅ Examples of kept nodes:")
                    for node_id, score in kept_examples:
                        label = self.graph.nodes[node_id].get('label', node_id)
                        print(f"   - {label} (score: {score:.3f})")
                        
            else:
                print("✅ All nodes meet relevance threshold - no filtering needed")
                
        except Exception as e:
            print(f"❌ Topic relevance filtering failed: {e}")
            print("🔄 Continuing with all nodes")
    
    def _finalize_graph_data(self) -> Dict[str, Any]:
        """Finalize and format graph data for Swift consumption."""
        
        # Convert nodes to Swift-compatible format
        nodes = []
        for node_id in self.graph.nodes():
            node_data = self.graph.nodes[node_id]
            node = {
                'id': node_id,
                'label': node_data.get('label', ''),
                'type': node_data.get('type', 'concept'),
                'properties': {
                    'frequency': str(node_data.get('frequency', 0)),
                    'importance': str(node_data.get('importance', 0.0)),
                    'pagerank': str(self.centrality_scores.get('pagerank', {}).get(node_id, 0.0)),
                    'eigenvector': str(self.centrality_scores.get('eigenvector', {}).get(node_id, 0.0)),
                    'betweenness': str(self.centrality_scores.get('betweenness', {}).get(node_id, 0.0)),
                    'closeness': str(self.centrality_scores.get('closeness', {}).get(node_id, 0.0)),
                    'topic_relevance': str(node_data.get('topic_relevance', 0.0)),
                    'source_references': ','.join(node_data.get('source_references', []))
                },
                'position': {'x': 0.0, 'y': 0.0}  # Will be set by Swift UI
            }
            nodes.append(node)
        
        # Convert edges to Swift-compatible format
        edges = []
        for source, target, edge_data in self.graph.edges(data=True):
            edge = {
                'source_id': source,
                'target_id': target,
                'label': edge_data.get('label', ''),
                'weight': edge_data.get('weight', 1.0),
                'properties': {}
            }
            edges.append(edge)
        
        # Convert minimal subgraph
        minimal_nodes = []
        minimal_edges = []
        
        if self.minimal_subgraph and self.minimal_subgraph.number_of_nodes() > 0:
            print(f"🔄 Converting minimal subgraph: {self.minimal_subgraph.number_of_nodes()} nodes, {self.minimal_subgraph.number_of_edges()} edges")
            
            # Create a mapping of node IDs for faster lookup
            node_lookup = {node['id']: node for node in nodes}
            
            for node_id in self.minimal_subgraph.nodes():
                if node_id in node_lookup:
                    node_copy = node_lookup[node_id].copy()
                    # Add minimal subgraph specific properties
                    node_copy['properties']['in_minimal_subgraph'] = 'true'
                    minimal_nodes.append(node_copy)
                else:
                    print(f"⚠️ Node {node_id} not found in main graph nodes")
            
            for source, target, edge_data in self.minimal_subgraph.edges(data=True):
                edge = {
                    'source_id': source,
                    'target_id': target,
                    'label': edge_data.get('label', ''),
                    'weight': edge_data.get('weight', 1.0),
                    'properties': {
                        'connection_type': edge_data.get('connection_type', 'intra_component')
                    }
                }
                minimal_edges.append(edge)
            
            print(f"✅ Converted minimal subgraph: {len(minimal_nodes)} nodes, {len(minimal_edges)} edges")
        else:
            print("⚠️ No minimal subgraph available for conversion")
        
        # Prepare metadata
        metadata = {
            'total_nodes': len(nodes),
            'total_edges': len(edges),
            'minimal_nodes': len(minimal_nodes),
            'minimal_edges': len(minimal_edges),
            'algorithms': ['pagerank', 'eigenvector', 'betweenness', 'closeness', 'hybrid_mst', 'topic_relevance'],
            'last_analysis': datetime.now().isoformat(),
            'has_embeddings': len(self.node_embeddings) > 0,
            'connected_components': nx.number_weakly_connected_components(self.graph),
            'minimal_connected_components': nx.number_weakly_connected_components(self.minimal_subgraph) if self.minimal_subgraph else 0,
            'graph_density': nx.density(self.graph),
            'minimal_graph_created': self.minimal_subgraph is not None and self.minimal_subgraph.number_of_nodes() > 0,
            'topic_relevance_enabled': self.topic_config.enable_semantic_filtering,
            'topic_relevance_threshold': self.topic_config.relevance_threshold,
            'run_id': self.run_id,
            'cache_directory': self.cache_dir
        }
        
        return {
            'success': True,
            'nodes': nodes,
            'edges': edges,
            'minimal_subgraph': {
                'nodes': minimal_nodes,
                'edges': minimal_edges
            },
            'metadata': metadata,
            'embeddings': self.node_embeddings  # For potential future use
        }


# MARK: - Main API Functions for Swift Integration

@traceable(name="generate_knowledge_graph")
def generate_knowledge_graph_from_sources(
    sources: List[Dict[str, Any]], 
    topic: str = "",
    progress_callback: Optional[Callable] = None,
    topic_config: Optional[TopicRelevanceConfig] = None
) -> Dict[str, Any]:
    """Main function for generating knowledge graph from sources with topic relevance filtering.
    
    Args:
        sources: List of source documents to process.
        topic: Main topic/subject for relevance filtering.
        progress_callback: Optional callback function for progress updates.
        topic_config: Configuration for topic relevance filtering.
        
    Returns:
        Dictionary containing the generated knowledge graph data.
        
    Raises:
        Exception: Returns error dictionary if generation fails.
    """
    if not sources:
        return {
            'success': False,
            'error': 'No sources provided',
            'nodes': [],
            'edges': [],
            'metadata': {}
        }
    
    try:
        builder = KnowledgeGraphBuilder(topic_config=topic_config)
        if progress_callback:
            builder.set_progress_callback(progress_callback)
        
        result = builder.build_graph_from_sources(sources, topic)
        return result
        
    except Exception as e:
        print(f"❌ Knowledge graph generation failed: {e}")
        return {
            'success': False,
            'error': str(e),
            'nodes': [],
            'edges': [],
            'metadata': {}
        }


def create_topic_relevance_config(
    relevance_threshold: float = 0.3,
    enable_filtering: bool = True,
    max_nodes_before_filtering: int = 1000,
    enable_source_connectivity_filtering: bool = True,
    require_verified_sources: bool = True,
    enable_deduplication: bool = True,
    deduplication_similarity_threshold: float = 0.75
) -> TopicRelevanceConfig:
    """Create a topic relevance configuration with common settings.
    
    Args:
        relevance_threshold: Minimum similarity score for node retention (0.0-1.0).
        enable_filtering: Whether to enable topic relevance filtering.
        max_nodes_before_filtering: Apply filtering only if nodes exceed this count.
        enable_source_connectivity_filtering: Whether to filter concepts without source connections.
        require_verified_sources: Whether source references must match original sources.
        enable_deduplication: Whether to deduplicate similar concepts in learning plans.
        deduplication_similarity_threshold: Threshold for fuzzy concept matching (0.0-1.0).
        
    Returns:
        TopicRelevanceConfig instance with specified settings.
        
    Examples:
        >>> # Conservative filtering (keeps more nodes, lenient source requirements)
        >>> config = create_topic_relevance_config(
        ...     relevance_threshold=0.2, 
        ...     require_verified_sources=False
        ... )
        >>> 
        >>> # Aggressive filtering (strict topic and source requirements)
        >>> config = create_topic_relevance_config(
        ...     relevance_threshold=0.5,
        ...     require_verified_sources=True
        ... )
        >>>
        >>> # Disable all filtering
        >>> config = create_topic_relevance_config(
        ...     enable_filtering=False,
        ...     enable_source_connectivity_filtering=False,
        ...     enable_deduplication=False
        ... )
        >>> 
        >>> # Aggressive deduplication
        >>> config = create_topic_relevance_config(
        ...     enable_deduplication=True,
        ...     deduplication_similarity_threshold=0.5
        ... )
    """
    return TopicRelevanceConfig(
        relevance_threshold=relevance_threshold,
        enable_semantic_filtering=enable_filtering,
        enable_context_filtering=enable_filtering,
        max_nodes_before_filtering=max_nodes_before_filtering,
        enable_source_connectivity_filtering=enable_source_connectivity_filtering,
        require_verified_sources=require_verified_sources,
        enable_deduplication=enable_deduplication,
        deduplication_similarity_threshold=deduplication_similarity_threshold
    )

# MARK: - Helper Functions for Enhanced Learning Plan Generation

def extract_meaningful_concepts_from_sources(sources: List[Dict[str, Any]], topic: str) -> List[Dict[str, Any]]:
    """Extract meaningful, educational concepts from source titles and content."""
    concepts = []
    
    for source in sources:
        title = source.get('title', '')
        content = source.get('content', '')
        url = source.get('url', '')
        
        # Extract concepts from title (these are usually the most meaningful)
        title_concepts = extract_concepts_from_title(title, topic)
        
        # Extract concepts from content sections
        content_concepts = extract_concepts_from_content(content, topic)
        
        # Combine and deduplicate
        for concept in title_concepts + content_concepts:
            if concept not in [c['name'] for c in concepts]:
                concepts.append({
                    'name': concept,
                    'source_title': title,
                    'source_url': url,
                    'context': extract_context_for_concept(concept, content, title),
                    'importance': calculate_concept_importance(concept, title, content)
                })
    
    # Sort by importance and return top concepts
    concepts.sort(key=lambda x: x['importance'], reverse=True)
    return concepts[:100]  # Limit to top 100 meaningful concepts

def extract_concepts_from_title(title: str, topic: str) -> List[str]:
    """Extract educational concepts from article titles."""
    concepts = []
    
    # Clean title
    title = re.sub(r'[^\w\s-]', '', title)
    
    # Look for key educational patterns
    educational_patterns = [
        r'(?:Introduction to|Understanding|Guide to|Overview of|Fundamentals of)\s+([A-Z][^:]+)',
        r'([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\s+(?:Explained|Tutorial|Guide|Basics)',
        r'How to\s+([A-Z][^:]+)',
        r'What is\s+([A-Z][^?]+)',
        r'(?:The|A)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\s+(?:Method|Approach|Framework|Model|Theory)'
    ]
    
    for pattern in educational_patterns:
        matches = re.findall(pattern, title, re.IGNORECASE)
        for match in matches:
            concept = match.strip()
            if len(concept) > 3 and concept.lower() not in ['the', 'and', 'or', 'but']:
                concepts.append(concept)
    
    # Also extract noun phrases from the title
    words = title.split()
    for i in range(len(words)):
        for length in [2, 3, 4]:  # 2-4 word phrases
            if i + length <= len(words):
                phrase = ' '.join(words[i:i+length])
                if (any(char.isupper() for char in phrase) and 
                    not phrase.lower().startswith(('a ', 'an ', 'the ', 'and ', 'or ', 'but '))):
                    concepts.append(phrase.title())
    
    return list(set(concepts))

def extract_concepts_from_content(content: str, topic: str) -> List[str]:
    """Extract educational concepts from content sections."""
    concepts = []
    
    # Look for section headings and key concepts
    lines = content.split('\n')
    
    for line in lines:
        line = line.strip()
        
        # Skip empty lines and very short lines
        if len(line) < 5:
            continue
            
        # Look for headings (often contain key concepts)
        if (line.isupper() or 
            any(line.startswith(marker) for marker in ['#', '##', '###', '•', '-', '*']) or
            line.endswith(':')):
            clean_line = re.sub(r'[#•\-*:]+', '', line).strip()
            if len(clean_line) > 3:
                concepts.append(clean_line.title())
        
        # Look for definition patterns
        definition_patterns = [
            r'([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\s+is\s+defined\s+as',
            r'([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\s+refers\s+to',
            r'The\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\s+(?:is|are|can be)',
            r'([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\s+(?:involves|includes|consists of)'
        ]
        
        for pattern in definition_patterns:
            matches = re.findall(pattern, line)
            for match in matches:
                if len(match) > 3:
                    concepts.append(match.strip())
    
    return list(set(concepts))

def extract_context_for_concept(concept: str, content: str, title: str) -> str:
    """Extract relevant context for a concept from content."""
    # Find sentences containing the concept
    sentences = re.split(r'[.!?]+', content.lower())
    concept_lower = concept.lower()
    
    relevant_sentences = []
    for sentence in sentences:
        if concept_lower in sentence:
            relevant_sentences.append(sentence.strip())
    
    if relevant_sentences:
        return '. '.join(relevant_sentences[:2]) + '.'  # First 2 relevant sentences
    else:
        # Fall back to title context
        return f"Related to {title}"

def calculate_concept_importance(concept: str, title: str, content: str) -> float:
    """Calculate importance score for a concept."""
    score = 0.0
    
    # Higher score if concept appears in title
    if concept.lower() in title.lower():
        score += 3.0
    
    # Higher score based on frequency in content
    frequency = content.lower().count(concept.lower())
    score += min(frequency * 0.5, 2.0)  # Cap frequency bonus
    
    # Higher score for longer, more specific concepts
    word_count = len(concept.split())
    if word_count >= 2:
        score += word_count * 0.3
    
    # Higher score for educational keywords
    educational_keywords = ['method', 'approach', 'framework', 'theory', 'principle', 'concept', 'model']
    if any(keyword in concept.lower() for keyword in educational_keywords):
        score += 1.0
    
    return score

def map_nodes_to_meaningful_concepts(
    node_dict: Dict[str, Any], 
    source_concepts: List[Dict[str, Any]], 
    sources: List[Dict[str, Any]]
) -> Dict[str, Any]:
    """Map graph nodes to meaningful concepts from sources with strict source connectivity requirements.
    
    Args:
        node_dict: Dictionary of graph nodes to process.
        source_concepts: List of concepts extracted from original sources.
        sources: Original source documents.
        
    Returns:
        Dictionary mapping node IDs to enhanced concept data with verified source connections.
    """
    enhanced_concepts = {}
    
    for node_id, node in node_dict.items():
        node_label = node.get('label', '').lower()
        
        # Extract source references from node dictionary or its nested properties
        node_src_raw = node.get('source_references')
        if not node_src_raw and isinstance(node.get('properties'), dict):
            node_src_raw = node['properties'].get('source_references')
        if isinstance(node_src_raw, list):
            node_source_references = node_src_raw
        else:
            # Fallback: treat as string representation (handles PythonKit str objects)
            try:
                node_source_references = [ref.strip() for ref in str(node_src_raw).split(',') if ref.strip()]
            except Exception:
                node_source_references = []
        
        # Clean node source references (remove empty or 'None')
        node_source_references = [ref for ref in node_source_references if ref and ref.lower() != 'none']

        # Find best matching concept from sources
        best_match = None
        best_score = 0.0
        
        for concept in source_concepts:
            concept_name = concept['name'].lower()
            
            # Calculate similarity score
            score = 0.0
            
            # Exact match
            if node_label == concept_name:
                score = 5.0
            # Partial match
            elif node_label in concept_name or concept_name in node_label:
                score = 3.0
            # Word overlap
            else:
                node_words = set(node_label.split())
                concept_words = set(concept_name.split())
                overlap = len(node_words & concept_words)
                if overlap > 0:
                    score = overlap / max(len(node_words), len(concept_words))
            
            if score > best_score:
                best_score = score
                best_match = concept
        
        if best_match and best_score > 0.3:
            # Use the meaningful concept from sources
            enhanced_concepts[node_id] = {
                'name': best_match['name'],
                'type': node.get('type', 'concept'),
                'description': generate_concept_description(best_match, sources),
                'resources': generate_enhanced_resources(best_match, sources),
                'source_references': [best_match['source_title']],
                'context': best_match['context'],
                'node_source_references': node_source_references
            }
        else:
            # Only include if node has valid source references from original processing
            if node_source_references:
                enhanced_name = node.get('label', 'Unknown Concept').title()
                enhanced_concepts[node_id] = {
                    'name': enhanced_name,
                    'type': node.get('type', 'concept'),
                    'description': f"Key concept related to {enhanced_name}",
                    'resources': generate_basic_resources(enhanced_name),
                    'source_references': node_source_references,
                    'context': '',
                    'node_source_references': node_source_references
                }
            # If no source references, concept is excluded (no fallback creation)
    
    return enhanced_concepts


def filter_concepts_by_source_connectivity(
    enhanced_concepts: Dict[str, Any],
    sources: List[Dict[str, Any]],
    require_verified_sources: bool = True
) -> Tuple[Dict[str, Any], List[str]]:
    """Filter concepts to ensure each has verifiable connections to original sources.
    
    Args:
        enhanced_concepts: Dictionary of enhanced concepts to filter.
        sources: Original source documents for verification.
        require_verified_sources: Whether to require source titles that match original sources.
        
    Returns:
        Tuple of (filtered_concepts, removed_concept_names).
    """
    if not sources:
        print("⚠️ No sources provided for connectivity verification")
        return enhanced_concepts, []
    
    print(f"🔍 Filtering {len(enhanced_concepts)} concepts for source connectivity...")
    
    # Create lookup of source titles for verification
    source_titles = set()
    for source in sources:
        title = source.get('title', '').strip()
        if title:
            source_titles.add(title.lower())
    
    filtered_concepts = {}
    removed_concepts = []
    
    for node_id, concept in enhanced_concepts.items():
        concept_name = concept.get('name', 'Unknown')
        
        # Get all source references for this concept
        source_refs = concept.get('source_references', [])
        node_source_refs = concept.get('node_source_references', [])
        all_refs = source_refs + node_source_refs
        
        # Check if concept has any source references
        valid_refs = [ref for ref in all_refs if ref and ref.strip() and ref.lower() != 'none']
        
        if not valid_refs:
            removed_concepts.append(concept_name)
            print(f"   🗑️  Removed '{concept_name}': No source references")
            continue
        
        # If requiring verified sources, check if any reference matches original sources
        if require_verified_sources:
            has_verified_source = False
            for ref in valid_refs:
                # Extract source title from reference (handle format like "Title (type)")
                ref_title = ref.split('(')[0].strip().lower()
                if ref_title in source_titles:
                    has_verified_source = True
                    break
                
                # Also check partial matches for source verification
                for source_title in source_titles:
                    if ref_title in source_title or source_title in ref_title:
                        has_verified_source = True
                        break
            
            if not has_verified_source:
                removed_concepts.append(concept_name)
                print(f"   🗑️  Removed '{concept_name}': No verifiable source connection")
                print(f"        References: {valid_refs[:2]}...")  # Show first 2 refs for debugging
                continue
        
        # Concept passes connectivity requirements
        filtered_concepts[node_id] = concept
    
    removed_count = len(removed_concepts)
    retained_count = len(filtered_concepts)
    
    if removed_count > 0:
        print(f"🧹 Source connectivity filter removed {removed_count} concepts")
        print(f"📊 Retained {retained_count} concepts with verified source connections")
        print(f"   Removal rate: {removed_count/(removed_count + retained_count):.1%}")
        
        # Show examples of what was removed vs kept
        if removed_concepts:
            print(f"   Examples removed: {', '.join(removed_concepts[:3])}")
        if filtered_concepts:
            kept_examples = [c.get('name', 'Unknown') for c in list(filtered_concepts.values())[:3]]
            print(f"   Examples kept: {', '.join(kept_examples)}")
    else:
        print(f"✅ All {retained_count} concepts have verified source connections")
    
    return filtered_concepts, removed_concepts

def generate_concept_description(concept: Dict[str, Any], sources: List[Dict[str, Any]]) -> str:
    """Generate a meaningful description for a concept."""
    base_description = concept.get('context', '')
    
    if not base_description or len(base_description) < 20:
        # Generate based on concept name and source title
        concept_name = concept['name']
        source_title = concept.get('source_title', '')
        
        if 'method' in concept_name.lower():
            return f"{concept_name} is a systematic approach discussed in '{source_title}' for solving specific problems or achieving particular outcomes."
        elif 'theory' in concept_name.lower():
            return f"{concept_name} is a theoretical framework explored in '{source_title}' that provides explanations and predictions about related phenomena."
        elif 'framework' in concept_name.lower():
            return f"{concept_name} is a structured framework presented in '{source_title}' for organizing and approaching complex topics."
        else:
            return f"{concept_name} is a key concept detailed in '{source_title}' with important implications for understanding the broader topic."
    
    return base_description

def generate_enhanced_resources(concept: Dict[str, Any], sources: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Generate enhanced learning resources based on actual sources."""
    resources = []
    
    concept_name = concept['name']
    source_title = concept.get('source_title', '')
    source_url = concept.get('source_url', '')
    
    # Primary source
    if source_title and source_url:
        resources.append({
            'type': 'Primary Source',
            'title': source_title,
            'description': f"Original source material covering {concept_name}",
            'url': source_url,
            'verified': True
        })
    
    # Related concepts from same domain
    related_sources = [s for s in sources if concept_name.lower() in s.get('title', '').lower()]
    for related_source in related_sources[:2]:  # Limit to 2 related sources
        if related_source.get('url') != source_url:  # Don't duplicate primary source
            resources.append({
                'type': 'Related Reading',
                'title': related_source.get('title', ''),
                'description': f"Additional perspective on {concept_name}",
                'url': related_source.get('url', ''),
                'verified': True
            })
    
    # Add suggested learning resources based on concept type
    if 'method' in concept_name.lower() or 'approach' in concept_name.lower():
        resources.append({
            'type': 'Tutorial',
            'title': f"Step-by-Step Guide to {concept_name}",
            'description': f"Practical tutorial implementing {concept_name}",
            'verified': False
        })
    
    return resources

def generate_basic_resources(concept_name: str) -> List[Dict[str, Any]]:
    """Generate basic resources for concepts without source matches."""
    return [{
        'type': 'Overview',
        'title': f"Introduction to {concept_name}",
        'description': f"Foundational overview of {concept_name} concepts and principles",
        'verified': False
    }]

def calculate_enhanced_time_estimate(concept: Dict[str, Any], depth: str, importance_score: float) -> int:
    """Calculate enhanced time estimate based on concept complexity and depth."""
    base_times = {
        'quick': 2,
        'moderate': 4,
        'comprehensive': 8
    }
    
    base_time = base_times.get(depth, 4)
    
    # Adjust based on concept complexity
    concept_name = concept.get('name', '').lower()
    complexity_multiplier = 1.0
    
    if any(keyword in concept_name for keyword in ['theory', 'framework', 'methodology']):
        complexity_multiplier = 1.5
    elif any(keyword in concept_name for keyword in ['method', 'approach', 'technique']):
        complexity_multiplier = 1.3
    elif any(keyword in concept_name for keyword in ['basic', 'introduction', 'overview']):
        complexity_multiplier = 0.8
    
    # Adjust based on importance (higher importance = more depth needed)
    importance_multiplier = 1.0 + (importance_score * 0.3)
    
    # Adjust based on available resources
    resources_count = len(concept.get('resources', []))
    if resources_count > 2:
        complexity_multiplier *= 1.2  # More resources = more comprehensive study
    
    total_time = int(base_time * complexity_multiplier * importance_multiplier)
    return max(1, min(total_time, 20))  # Cap between 1-20 hours

def create_source_bibliography(sources: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Create a bibliography of sources used in the learning plan."""
    bibliography = []
    
    for i, source in enumerate(sources, 1):
        bibliography.append({
            'id': i,
            'title': source.get('title', 'Untitled Source'),
            'url': source.get('url', ''),
            'type': determine_source_type(source),
            'description': source.get('content', '')[:200] + '...' if source.get('content', '') else '',
            'relevance_score': source.get('score', 0.0)
        })
    
    return bibliography

def determine_source_type(source: Dict[str, Any]) -> str:
    """Determine the type of source based on URL and content."""
    url = source.get('url', '').lower()
    title = source.get('title', '').lower()
    
    if 'arxiv.org' in url or 'paper' in title:
        return 'Academic Paper'
    elif 'wikipedia.org' in url:
        return 'Encyclopedia'
    elif 'tutorial' in title or 'guide' in title:
        return 'Tutorial'
    elif 'blog' in url or 'medium.com' in url:
        return 'Blog Post'
    elif 'news' in url:
        return 'News Article'
    else:
        return 'Web Article'

def deduplicate_learning_concepts(concepts: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Deduplicate learning concepts using exact and fuzzy matching.
    
    This function removes duplicate concepts from a learning plan by:
    1. Exact matching (case-insensitive)
    2. Fuzzy matching for similar concepts (e.g., "Neural Network" vs "Neural Networks")
    3. Merging source references and keeping the highest importance score
    
    Args:
        concepts: List of concept dictionaries with name, description, etc.
        
    Returns:
        List of deduplicated concepts with merged information.
    """
    if not concepts:
        return []
    
    deduplicated = []
    processed_names = set()
    
    # Sort concepts by importance score (highest first) to keep the best version
    sorted_concepts = sorted(concepts, key=lambda x: x.get('importance_score', 0.0), reverse=True)
    
    for concept in sorted_concepts:
        concept_name = concept.get('name', '').strip()
        if not concept_name:
            continue
            
        # Normalize for comparison
        normalized_name = concept_name.lower().strip()
        
        # Check for exact duplicates (case-insensitive)
        if normalized_name in processed_names:
            # Find the existing concept and merge source references
            for existing in deduplicated:
                if existing['name'].lower() == normalized_name:
                    # Merge source references
                    existing_refs = set(existing.get('source_references', []))
                    new_refs = set(concept.get('source_references', []))
                    combined_refs = list(existing_refs.union(new_refs))[:5]  # Limit to 5
                    existing['source_references'] = combined_refs
                    
                    # Merge resources
                    existing_resources = existing.get('resources', [])
                    new_resources = concept.get('resources', [])
                    for resource in new_resources:
                        if resource not in existing_resources:
                            existing_resources.append(resource)
                    existing['resources'] = existing_resources[:3]  # Limit to 3
                    
                    # Update time estimate if new one is higher
                    existing['time_estimate'] = max(
                        existing.get('time_estimate', 0),
                        concept.get('time_estimate', 0)
                    )
                    break
            continue
        
        # Check for fuzzy duplicates
        is_fuzzy_duplicate = False
        for existing in deduplicated:
            existing_name = existing['name'].lower().strip()
            
            # Check for plural/singular variations
            if _are_similar_concepts(normalized_name, existing_name):
                # Merge with existing concept
                existing_refs = set(existing.get('source_references', []))
                new_refs = set(concept.get('source_references', []))
                combined_refs = list(existing_refs.union(new_refs))[:5]
                existing['source_references'] = combined_refs
                
                # Use the more descriptive name (usually the longer one)
                if len(concept_name) > len(existing['name']):
                    existing['name'] = concept_name
                
                # Merge descriptions (use the longer one)
                existing_desc = existing.get('description', '')
                new_desc = concept.get('description', '')
                if len(new_desc) > len(existing_desc):
                    existing['description'] = new_desc
                
                # Update time estimate if new one is higher
                existing['time_estimate'] = max(
                    existing.get('time_estimate', 0),
                    concept.get('time_estimate', 0)
                )
                
                is_fuzzy_duplicate = True
                processed_names.add(normalized_name)
                break
        
        if not is_fuzzy_duplicate:
            # Add as new unique concept
            deduplicated.append(concept.copy())
            processed_names.add(normalized_name)
    
    return deduplicated


def _are_similar_concepts(name1: str, name2: str) -> bool:
    """Check if two concept names are similar enough to be considered duplicates.
    
    Args:
        name1: First concept name (normalized to lowercase)
        name2: Second concept name (normalized to lowercase) 
        
    Returns:
        True if concepts should be merged as duplicates.
    """
    # Handle exact matches
    if name1 == name2:
        return True
    
    # Handle plural/singular variations
    if name1.endswith('s') and name1[:-1] == name2:
        return True
    if name2.endswith('s') and name2[:-1] == name1:
        return True
    
    # Handle 'ing' variations
    if name1.endswith('ing') and name1[:-3] == name2:
        return True
    if name2.endswith('ing') and name2[:-3] == name1:
        return True
    
    # Handle common word variations
    variations = [
        ('method', 'methods', 'methodology'),
        ('technique', 'techniques'),
        ('algorithm', 'algorithms'),
        ('approach', 'approaches'),
        ('concept', 'concepts'),
        ('principle', 'principles'),
        ('theory', 'theories'),
        ('model', 'models', 'modeling'),
        ('analysis', 'analyses'),
        ('network', 'networks', 'networking'),
        ('learning', 'machine learning'),
        ('data', 'dataset', 'datasets')
    ]
    
    for variation_group in variations:
        if name1 in variation_group and name2 in variation_group:
            return True
    
    # Handle substring matches for compound concepts
    words1 = set(name1.split())
    words2 = set(name2.split())
    
    # If one concept is a subset of another with significant overlap
    if len(words1) >= 2 and len(words2) >= 2:
        intersection = words1.intersection(words2)
        union = words1.union(words2)
        
        # Consider similar if they share >75% of words
        similarity_ratio = len(intersection) / len(union)
        if similarity_ratio > 0.75:
            return True
    
    # Handle abbreviations and expansions
    if len(name1) <= 5 and name1.upper() in name2.upper():
        return True
    if len(name2) <= 5 and name2.upper() in name1.upper():
        return True
    
    return False


def generate_learning_plan_from_minimal_subgraph(
    minimal_subgraph: Dict[str, Any], 
    sources: List[Dict[str, Any]], 
    topic: str, 
    depth: str = "moderate"
) -> Dict[str, Any]:
    """
    Generate a detailed, structured learning plan from the minimal subgraph and source materials.
    
    Args:
        minimal_subgraph: Dictionary containing nodes and edges from minimal subgraph
        sources: List of source dictionaries used in graph generation
        topic: Main topic/subject for learning plan
        depth: Learning depth level (quick, moderate, comprehensive)
    
    Returns:
        Dictionary with structured learning plan content
    """
    try:
        import networkx as nx
        from collections import defaultdict
        import re
        
        print(f"🎓 Generating enhanced learning plan for topic: {topic}")
        print(f"📊 Minimal subgraph: {len(minimal_subgraph.get('nodes', []))} nodes, {len(minimal_subgraph.get('edges', []))} edges")
        print(f"📚 Available sources: {len(sources)} documents")
        
        # Extract meaningful concepts from sources
        source_concepts = extract_meaningful_concepts_from_sources(sources, topic)
        print(f"🧠 Extracted {len(source_concepts)} meaningful concepts from sources")
        
        # Extract nodes and edges from minimal subgraph
        nodes = minimal_subgraph.get('nodes', [])
        edges = minimal_subgraph.get('edges', [])
        
        # Create NetworkX graph from minimal subgraph for analysis
        G = nx.Graph()
        
        # Add nodes
        node_dict = {}
        for node in nodes:
            node_id = node.get('id', '')
            G.add_node(node_id, **node)
            node_dict[node_id] = node
        
        # Add edges
        for edge in edges:
            source_id = edge.get('source_id', '')
            target_id = edge.get('target_id', '')
            if source_id in node_dict and target_id in node_dict:
                G.add_edge(source_id, target_id, **edge)
        
        # Map graph nodes to meaningful concepts using source content
        enhanced_concepts = map_nodes_to_meaningful_concepts(node_dict, source_concepts, sources)
        
        # Filter concepts to ensure source connectivity (if enabled)
        removed_concepts = []
        # Note: Using default config here since learning plan generation doesn't receive topic_config directly
        # This could be enhanced in future to accept configuration parameter
        enable_source_filtering = True  # Default to enabled for stricter filtering
        require_verified = True  # Default to verified sources requirement
        
        if enable_source_filtering:
            enhanced_concepts, removed_concepts = filter_concepts_by_source_connectivity(
                enhanced_concepts, sources, require_verified_sources=require_verified
            )
            
            if removed_concepts:
                print(f"🔗 Source connectivity filter removed {len(removed_concepts)} concepts without verified source connections")
            else:
                print(f"✅ All concepts have verified connections to original sources")
        else:
            print(f"🔄 Source connectivity filtering disabled - keeping all {len(enhanced_concepts)} concepts")
        
        # Perform topological analysis for learning order
        try:
            centrality_scores = nx.degree_centrality(G)
            betweenness_scores = nx.betweenness_centrality(G)
            
            # Combine centrality metrics for importance ranking
            combined_scores = {}
            for node_id in G.nodes():
                combined_scores[node_id] = (
                    centrality_scores.get(node_id, 0) * 0.6 +
                    betweenness_scores.get(node_id, 0) * 0.4
                )
            
            # Sort nodes by importance for learning progression
            ordered_nodes = sorted(combined_scores.items(), key=lambda x: x[1], reverse=True)
            
        except Exception as e:
            print(f"⚠️ Centrality analysis failed: {e}")
            ordered_nodes = [(node_id, 1.0) for node_id in node_dict.keys()]
        
        # Group enhanced concepts by type and importance
        concept_groups = {
            'foundation': [],  # High centrality, core concepts
            'intermediate': [],  # Medium centrality, connecting concepts  
            'advanced': [],  # Lower centrality, specialized concepts
            'practical': []  # Insights and applications
        }
        
        # Collect all concepts with their data before categorization
        all_concepts = []
        for node_id, score in ordered_nodes:
            if node_id not in enhanced_concepts:
                continue
                
            enhanced_concept = enhanced_concepts[node_id]
            concept_type = enhanced_concept.get('type', 'concept')
            
            # Add time estimates based on depth and complexity
            time_estimate = calculate_enhanced_time_estimate(enhanced_concept, depth, score)
            
            # Combine source references from original analysis and node references
            combined_source_references = []

            # Add original source references
            if enhanced_concept.get('source_references'):
                combined_source_references.extend(enhanced_concept['source_references'])

            # Add node source references
            if enhanced_concept.get('node_source_references'):
                combined_source_references.extend(enhanced_concept['node_source_references'])
            
            # Filter out invalid refs and deduplicate
            cleaned_refs = [ref for ref in combined_source_references if ref and str(ref).lower() != 'none']
            unique_source_references = []
            seen: Set[str] = set()
            for ref in cleaned_refs:
                if ref not in seen:
                    unique_source_references.append(ref)
                    seen.add(ref)
            
            concept_info = {
                'name': enhanced_concept['name'],
                'type': concept_type,
                'description': enhanced_concept['description'],
                'time_estimate': time_estimate,
                'importance_score': score,
                'connections': get_concept_connections(node_id, G, enhanced_concepts),
                'resources': enhanced_concept['resources'],
                'source_references': unique_source_references[:5],  # Limit to top 5 references
                'node_id': node_id  # Keep for debugging
            }
            
            all_concepts.append(concept_info)
        
        # Deduplicate concepts before categorization
        deduplicated_concepts = deduplicate_learning_concepts(all_concepts)
        print(f"🔄 Deduplication: {len(all_concepts)} → {len(deduplicated_concepts)} concepts")
        
        # Categorize deduplicated concepts based on centrality and enhanced information
        for concept_info in deduplicated_concepts:
            concept_type = concept_info.get('type', 'concept')
            score = concept_info.get('importance_score', 0.0)
            
            # Determine learning category based on centrality and concept complexity
            if score > 0.7 or any(keyword in concept_info['name'].lower() 
                                  for keyword in ['fundamental', 'basic', 'introduction', 'overview']):
                category = 'foundation'
            elif score > 0.4 or concept_type == 'entity':
                category = 'intermediate'  
            elif concept_type == 'insight' or any(keyword in concept_info['name'].lower() 
                                                  for keyword in ['application', 'practice', 'implementation']):
                category = 'practical'
            else:
                category = 'advanced'
            
            # Remove node_id before adding to final result
            final_concept = {k: v for k, v in concept_info.items() if k != 'node_id'}
            concept_groups[category].append(final_concept)
        
        # Generate time estimates for each phase
        phase_times = {
            'foundation': sum(c['time_estimate'] for c in concept_groups['foundation']),
            'intermediate': sum(c['time_estimate'] for c in concept_groups['intermediate']),
            'advanced': sum(c['time_estimate'] for c in concept_groups['advanced']),
            'practical': sum(c['time_estimate'] for c in concept_groups['practical'])
        }
        
        total_time = sum(phase_times.values())
        
        # Create source bibliography
        source_bibliography = create_source_bibliography(sources)
        
        # Calculate deduplication statistics
        original_concept_count = len(all_concepts)
        deduplicated_concept_count = len(deduplicated_concepts)
        concepts_removed_by_deduplication = original_concept_count - deduplicated_concept_count
        
        # Generate structured learning plan
        learning_plan = {
            'topic': topic,
            'depth': depth,
            'total_estimated_time': total_time,
            'total_concepts': len([c for concepts in concept_groups.values() for c in concepts]),
            'phase_breakdown': phase_times,
            'concept_groups': concept_groups,
            'sources_used': len(sources),
            'source_bibliography': source_bibliography,
            'source_connectivity_enabled': enable_source_filtering,
            'concepts_removed_by_source_filter': len(removed_concepts) if removed_concepts else 0,
            'deduplication_enabled': True,
            'concepts_removed_by_deduplication': concepts_removed_by_deduplication,
            'original_concept_count': original_concept_count,
            'learning_path_rationale': (
                f"Learning path designed using centrality analysis of {len(nodes)} key concepts. "
                f"Concepts are ordered to ensure foundational understanding before advanced topics, "
                f"with direct connections to {len(sources)} verified source materials. "
                + (f"Source connectivity filtering removed {len(removed_concepts)} unverified concepts. " 
                   if removed_concepts else "All concepts have verified source connections. ")
                + f"Deduplication removed {concepts_removed_by_deduplication} duplicate concepts."
            )
        }
        
        print(f"✅ Enhanced learning plan generated: {total_time} hours across {learning_plan['total_concepts']} concepts")
        return learning_plan
        
    except Exception as e:
        print(f"❌ Error generating learning plan: {e}")
        return {
            'topic': topic,
            'depth': depth,
            'total_estimated_time': 0,
            'error': str(e),
            'concept_groups': {'foundation': [], 'intermediate': [], 'advanced': [], 'practical': []},
            'sources_used': len(sources) if sources else 0
        }

def calculate_time_estimate(concept_type: str, depth: str, importance_score: float) -> int:
    """Calculate time estimate for learning a concept based on type, depth, and importance."""
    base_times = {
        'concept': {'quick': 2, 'moderate': 4, 'comprehensive': 8},
        'entity': {'quick': 1, 'moderate': 2, 'comprehensive': 4},
        'insight': {'quick': 1, 'moderate': 3, 'comprehensive': 6},
        'document': {'quick': 1, 'moderate': 2, 'comprehensive': 3}
    }
    
    base_time = base_times.get(concept_type, base_times['concept']).get(depth, 4)
    
    # Adjust based on importance (higher importance = more time needed)
    importance_multiplier = 1.0 + (importance_score * 0.5)
    
    return int(base_time * importance_multiplier)

def get_concept_connections(node_id: str, graph: Any, enhanced_concepts: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Get related concepts for a given node."""
    connections = []
    for neighbor in graph.neighbors(node_id):
        if neighbor in enhanced_concepts:
            neighbor_concept = enhanced_concepts[neighbor]
            connections.append({
                'name': neighbor_concept.get('name', 'Unknown'),
                'type': neighbor_concept.get('type', 'concept'),
                'relationship': 'related_to'  # Could be enhanced with edge labels
            })
    return connections[:5]  # Limit to top 5 connections

def generate_concept_resources(concept_name: str, properties: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Generate learning resources for a concept."""
    resources = []
    
    # Add basic resource suggestions based on concept name
    if any(keyword in concept_name.lower() for keyword in ['algorithm', 'method', 'technique']):
        resources.append({
            'type': 'Tutorial',
            'title': f"Understanding {concept_name}: Step-by-Step Guide",
            'description': f"Comprehensive tutorial covering the fundamentals of {concept_name}"
        })
    
    if any(keyword in concept_name.lower() for keyword in ['history', 'background', 'origin']):
        resources.append({
            'type': 'Historical Context',
            'title': f"The Evolution of {concept_name}",
            'description': f"Historical perspective on the development of {concept_name}"
        })
    
    if any(keyword in concept_name.lower() for keyword in ['application', 'use', 'practice']):
        resources.append({
            'type': 'Case Study',
            'title': f"Real-World Applications of {concept_name}",
            'description': f"Practical examples and case studies featuring {concept_name}"
        })
    
    # Add a general resource if no specific ones were added
    if not resources:
        resources.append({
            'type': 'Overview',
            'title': f"Introduction to {concept_name}",
            'description': f"Foundational overview of {concept_name} concepts and principles"
        })
    
    return resources


if __name__ == "__main__":
    # Test function
    print("🧪 Testing knowledge graph generation...")
    
    test_sources = [
        {
            'title': 'Introduction to Machine Learning',
            'content': 'Machine learning is a subset of artificial intelligence that enables computers to learn and make decisions without being explicitly programmed. Neural networks are a key component of deep learning, which is used for pattern recognition and data analysis.',
            'url': 'https://example.com/ml-intro'
        },
        {
            'title': 'Deep Learning Fundamentals',
            'content': 'Deep learning uses neural networks with multiple layers to process complex data. Artificial intelligence applications include computer vision, natural language processing, and speech recognition. Training models requires large datasets and computational resources.',
            'url': 'https://example.com/deep-learning'
        }
    ]
    
    result = generate_knowledge_graph_from_sources(test_sources, "artificial intelligence")
    
    if result['success']:
        print(f"✅ Test successful: {len(result['nodes'])} nodes, {len(result['edges'])} edges")
    else:
        print(f"❌ Test failed: {result.get('error', 'Unknown error')}") 