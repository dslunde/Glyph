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


class KnowledgeGraphBuilder:
    """Main class for building knowledge graphs from source collections."""
    
    def __init__(self, cache_dir: Optional[str] = None):
        """Initialize the knowledge graph builder."""
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
        """Build knowledge graph from collected sources."""
        print(f"🏗️ Building knowledge graph from {len(sources)} sources...")
        
        # Clear status file from any previous runs
        self._clear_status_file()
        
        self._update_progress(0.0, "Starting knowledge graph construction")
        
        # Clear previous data
        self.graph.clear()
        self.node_embeddings.clear()
        self.edge_weights.clear()
        self.centrality_scores.clear()
        
        try:
            # Step 1: Extract concepts and entities (30%)
            self._update_progress(0.1, "Extracting concepts and entities")
            concepts, entities = self._extract_concepts_and_entities(sources)
            
            # Step 2: Build initial graph (50%)
            self._update_progress(0.3, "Building initial graph structure")
            self._build_graph_structure(concepts, entities, sources)
            
            # Step 3: Calculate centrality metrics (70%)
            self._update_progress(0.5, "Calculating centrality metrics")
            self._calculate_centrality_metrics()
            
            # Step 4: Find minimal subgraph (85%)
            self._update_progress(0.7, "Finding minimal subgraph")
            self._find_minimal_subgraph()
            
            # Step 5: Generate embeddings (95%)
            self._update_progress(0.85, "Generating node embeddings")
            self._generate_node_embeddings()
            
            # Step 6: Finalize results (100%)
            self._update_progress(0.95, "Finalizing results")
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
        
        for i, source in enumerate(sources):
            progress = 0.1 + (i / len(sources)) * 0.2
            self._update_progress(progress, f"Processing source {i+1}/{len(sources)}")
            
            content = source.get('content', '')
            title = source.get('title', '')
            url = source.get('url', '')
            
            # Extract text concepts
            text_concepts = self._extract_text_concepts(content + ' ' + title)
            for concept in text_concepts:
                concept_counts[concept] += 1
            
            # Extract named entities
            text_entities = self._extract_named_entities(content)
            for entity in text_entities:
                entity_counts[entity] += 1
        
        # Convert to graph nodes with frequency-based importance
        for concept, count in concept_counts.most_common(500):  # Limit to top 500
            concepts.append({
                'id': f"concept_{hashlib.md5(concept.encode()).hexdigest()[:8]}",
                'label': concept,
                'type': 'concept',
                'frequency': count,
                'importance': min(count / len(sources), 1.0)
            })
        
        for entity, count in entity_counts.most_common(300):  # Limit to top 300
            entities.append({
                'id': f"entity_{hashlib.md5(entity.encode()).hexdigest()[:8]}",
                'label': entity,
                'type': 'entity',
                'frequency': count,
                'importance': min(count / len(sources), 1.0)
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
                importance=node['importance']
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
                    'closeness': str(self.centrality_scores.get('closeness', {}).get(node_id, 0.0))
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
            'algorithms': ['pagerank', 'eigenvector', 'betweenness', 'closeness', 'hybrid_mst'],
            'last_analysis': datetime.now().isoformat(),
            'has_embeddings': len(self.node_embeddings) > 0,
            'connected_components': nx.number_weakly_connected_components(self.graph),
            'minimal_connected_components': nx.number_weakly_connected_components(self.minimal_subgraph) if self.minimal_subgraph else 0,
            'graph_density': nx.density(self.graph),
            'minimal_graph_created': self.minimal_subgraph is not None and self.minimal_subgraph.number_of_nodes() > 0,
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
    progress_callback: Optional[Callable] = None
) -> Dict[str, Any]:
    """Main function for generating knowledge graph from sources."""
    if not sources:
        return {
            'success': False,
            'error': 'No sources provided',
            'nodes': [],
            'edges': [],
            'metadata': {}
        }
    
    try:
        builder = KnowledgeGraphBuilder()
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

def generate_learning_plan_from_minimal_subgraph(minimal_subgraph, sources, topic, depth="moderate"):
    """
    Generate a detailed, structured learning plan from the minimal subgraph.
    
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
        import json
        
        print(f"🎓 Generating learning plan for topic: {topic}")
        print(f"📊 Minimal subgraph: {len(minimal_subgraph.get('nodes', []))} nodes, {len(minimal_subgraph.get('edges', []))} edges")
        
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
        
        # Perform topological analysis for learning order
        try:
            # For learning order, we want to find foundation concepts first
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
            # Fall back to simple ordering
            ordered_nodes = [(node.get('id', ''), 1.0) for node in nodes]
        
        # Group concepts by type and importance
        concept_groups = {
            'foundation': [],  # High centrality, core concepts
            'intermediate': [],  # Medium centrality, connecting concepts  
            'advanced': [],  # Lower centrality, specialized concepts
            'practical': []  # Insights and applications
        }
        
        # Categorize concepts based on type and centrality
        for node_id, score in ordered_nodes:
            node = node_dict.get(node_id, {})
            concept_name = node.get('label', 'Unknown Concept')
            concept_type = node.get('type', 'concept')
            properties = node.get('properties', {})
            
            # Determine learning category
            if score > 0.7 or concept_type == 'concept':
                category = 'foundation'
            elif score > 0.4 or concept_type == 'entity':
                category = 'intermediate'  
            elif concept_type == 'insight':
                category = 'practical'
            else:
                category = 'advanced'
            
            # Add time estimates based on depth and complexity
            time_estimate = calculate_time_estimate(concept_type, depth, score)
            
            concept_info = {
                'name': concept_name,
                'type': concept_type,
                'description': properties.get('description', f'Core concept related to {concept_name}'),
                'time_estimate': time_estimate,
                'importance_score': score,
                'connections': get_concept_connections(node_id, G, node_dict),
                'resources': generate_concept_resources(concept_name, properties)
            }
            
            concept_groups[category].append(concept_info)
        
        # Generate time estimates for each phase
        phase_times = {
            'foundation': sum(c['time_estimate'] for c in concept_groups['foundation']),
            'intermediate': sum(c['time_estimate'] for c in concept_groups['intermediate']),
            'advanced': sum(c['time_estimate'] for c in concept_groups['advanced']),
            'practical': sum(c['time_estimate'] for c in concept_groups['practical'])
        }
        
        total_time = sum(phase_times.values())
        
        # Generate structured learning plan
        learning_plan = {
            'topic': topic,
            'depth': depth,
            'total_estimated_time': total_time,
            'total_concepts': len(nodes),
            'phase_breakdown': phase_times,
            'concept_groups': concept_groups,
            'sources_used': len(sources),
            'learning_path_rationale': f"Concepts ordered by centrality analysis (PageRank + Degree) to ensure proper foundational understanding before advanced topics."
        }
        
        print(f"✅ Learning plan generated: {total_time} hours across {len(nodes)} concepts")
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

def calculate_time_estimate(concept_type, depth, importance_score):
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

def get_concept_connections(node_id, graph, node_dict):
    """Get related concepts for a given node."""
    connections = []
    for neighbor in graph.neighbors(node_id):
        neighbor_node = node_dict.get(neighbor, {})
        connections.append({
            'name': neighbor_node.get('label', 'Unknown'),
            'type': neighbor_node.get('type', 'concept'),
            'relationship': 'related_to'  # Could be enhanced with edge labels
        })
    return connections[:5]  # Limit to top 5 connections

def generate_concept_resources(concept_name, properties):
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