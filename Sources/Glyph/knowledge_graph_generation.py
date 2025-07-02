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
from typing import List, Dict, Any, Optional, Tuple, Set
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
            # Use appropriate cache directory for macOS app bundles
            if os.getenv('APP_BUNDLE_MODE'):
                # Running in app bundle - use user cache directory
                home_dir = os.path.expanduser("~")
                self.cache_dir = os.path.join(home_dir, "Library", "Caches", "com.glyph.knowledge-graph-explorer")
            else:
                # Development mode - use local cache
                self.cache_dir = "./graph_cache"
        else:
            self.cache_dir = cache_dir
            
        # Create cache directory with proper error handling
        try:
            os.makedirs(self.cache_dir, exist_ok=True)
            print(f"📁 Cache directory: {self.cache_dir}")
        except OSError as e:
            print(f"⚠️ Failed to create cache directory {self.cache_dir}: {e}")
            # Fallback to temp directory
            self.cache_dir = tempfile.mkdtemp(prefix="glyph_cache_")
            print(f"📁 Using fallback cache directory: {self.cache_dir}")
        
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
    
    @traceable(name="build_knowledge_graph")
    def build_graph_from_sources(
        self, 
        sources: List[Dict[str, Any]], 
        topic: str = ""
    ) -> Dict[str, Any]:
        """Build knowledge graph from collected sources."""
        print(f"🏗️ Building knowledge graph from {len(sources)} sources...")
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
            print(f"❌ Graph construction failed: {e}")
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
        """Find minimal subgraph focusing on most important nodes."""
        if not self.centrality_scores or self.graph.number_of_nodes() == 0:
            print("⚠️ No centrality scores available - skipping minimal subgraph")
            return
        
        print(f"🎯 Finding minimal subgraph for {self.graph.number_of_nodes()} nodes...")
        step_start = datetime.now()
        
        # Combine centrality scores to find most important nodes
        print("   📊 Combining centrality scores...")
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
        print(f"   ✅ Combined scores for {len(combined_scores)} nodes")
        
        # Select top nodes (20% of total or max 100)
        total_nodes = self.graph.number_of_nodes()
        target_size = min(100, max(10, int(total_nodes * 0.2)))
        print(f"   🎯 Selecting top {target_size} nodes from {total_nodes} total")
        
        top_nodes = sorted(combined_scores.items(), key=lambda x: x[1], reverse=True)
        selected_nodes = [node for node, score in top_nodes[:target_size]]
        print(f"   📋 Selected {len(selected_nodes)} top nodes")
        
        # Create subgraph and ensure connectivity
        print("   🔗 Creating initial subgraph...")
        self.minimal_subgraph = self.graph.subgraph(selected_nodes).copy()
        print(f"   ✅ Initial subgraph: {self.minimal_subgraph.number_of_nodes()} nodes, {self.minimal_subgraph.number_of_edges()} edges")
        
        # Check connectivity (simplified approach)
        components = nx.number_weakly_connected_components(self.minimal_subgraph)
        print(f"   🔗 Graph has {components} connected components")
        
        if components > 5:
            print("   🔧 Too many components - adding connecting nodes...")
            # Simple approach: just add a few more highly connected nodes
            remaining_nodes = [node for node in self.graph.nodes() if node not in selected_nodes]
            if remaining_nodes:
                # Sort by degree and add top nodes
                node_degrees = []
                for node in remaining_nodes:
                    try:
                        degree = int(self.graph.degree(node))
                        node_degrees.append((node, degree))
                    except:
                        node_degrees.append((node, 0))
                top_connected = sorted(node_degrees, key=lambda x: x[1], reverse=True)
                additional_nodes = [node for node, degree in top_connected[:min(10, len(top_connected))]]
                selected_nodes.extend(additional_nodes)
                
                # Recreate subgraph with additional nodes
                self.minimal_subgraph = self.graph.subgraph(selected_nodes).copy()
                print(f"   ✅ Added {len(additional_nodes)} connecting nodes")
        
        # Perform topological sort if possible (for DAG-like structures)
        try:
            if nx.is_directed_acyclic_graph(self.minimal_subgraph):
                topo_order = list(nx.topological_sort(self.minimal_subgraph))  # type: ignore
                print(f"📋 Topological ordering found with {len(topo_order)} nodes")
            else:
                print("📋 Graph contains cycles - no topological ordering")
        except Exception as e:
            print(f"⚠️ Topological sort failed: {e}")
        
        print(f"🎯 Minimal subgraph: {self.minimal_subgraph.number_of_nodes()} nodes, "
              f"{self.minimal_subgraph.number_of_edges()} edges")
    
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
        
        if self.minimal_subgraph:
            for node_id in self.minimal_subgraph.nodes():
                # Find the node in the main graph
                for node in nodes:
                    if node['id'] == node_id:
                        minimal_nodes.append(node.copy())
                        break
            
            for source, target, edge_data in self.minimal_subgraph.edges(data=True):
                edge = {
                    'source_id': source,
                    'target_id': target,
                    'label': edge_data.get('label', ''),
                    'weight': edge_data.get('weight', 1.0),
                    'properties': {}
                }
                minimal_edges.append(edge)
        
        # Prepare metadata
        metadata = {
            'total_nodes': len(nodes),
            'total_edges': len(edges),
            'minimal_nodes': len(minimal_nodes),
            'minimal_edges': len(minimal_edges),
            'algorithms': ['pagerank', 'eigenvector', 'betweenness', 'closeness'],
            'last_analysis': datetime.now().isoformat(),
            'has_embeddings': len(self.node_embeddings) > 0,
            'connected_components': nx.number_weakly_connected_components(self.graph),
            'graph_density': nx.density(self.graph)
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
    progress_callback: Optional[callable] = None
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