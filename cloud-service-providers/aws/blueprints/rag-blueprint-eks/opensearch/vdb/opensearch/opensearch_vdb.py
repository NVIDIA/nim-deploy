# SPDX-FileCopyrightText: Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
OpenSearch vector database implementation for NVIDIA RAG.

Auth support:
 - Basic auth (username/password)
 - AWS SigV4 (Amazon OpenSearch Service and Serverless)

Connection options:
 - TLS verification and custom CA certificates

Mirrors ElasticVDB structure for drop-in parity.
"""

import logging
import os
import time
from typing import Any

import pandas as pd
from langchain_core.documents import Document
from langchain_core.runnables import RunnableAssign, RunnableLambda
from langchain_community.vectorstores import OpenSearchVectorSearch

try:
    from nv_ingest_client.util.milvus import cleanup_records
except Exception:  # pragma: no cover - optional dependency in some environments
    def cleanup_records(
        records,
        meta_dataframe=None,
        meta_source_field=None,
        meta_fields=None,
    ):
        return records

from nvidia_rag.utils.common import get_config
from nvidia_rag.utils.vdb import DEFAULT_METADATA_SCHEMA_COLLECTION
from nvidia_rag.utils.vdb.opensearch.os_queries import (
    create_metadata_collection_mapping,
    get_delete_docs_query,
    get_delete_metadata_schema_query,
    get_metadata_schema_query,
    get_unique_sources_query,
)
from nvidia_rag.utils.vdb.vdb_base import VDBRag
from opentelemetry import context as otel_context

logger = logging.getLogger(__name__)
CONFIG = get_config()


class OpenSearchVDB(VDBRag):
    def __init__(
        self,
        opensearch_url: str = "http://localhost:9200", 
        index_name: str = "test",
        embedding_model: Any | None = None,
        meta_dataframe: pd.DataFrame | None = None,
        meta_source_field: str | None = None,
        meta_fields: list[str] | None = None,
        hybrid: bool = False,
        csv_file_path: str | None = None,
    ):
        # Follow documented pattern: opensearch_url, index_name, embedding_model as primary params
        self.opensearch_url = opensearch_url  # matches documented URL pattern
        self.index_name = index_name
        self.embedding_model = embedding_model  # public attribute as per docs
        
        # Additional parameters for advanced functionality
        self.hybrid = hybrid
        self.meta_dataframe = meta_dataframe
        self.meta_source_field = meta_source_field
        self.meta_fields = meta_fields
        self.csv_file_path = csv_file_path
        
        # Lazy initialization - don't create vectorstore in __init__
        self._vectorstore = None

        kwargs = locals().copy()
        kwargs.pop("self", None)
        super().__init__(**kwargs)

    @property
    def collection_name(self) -> str:
        return self.index_name

    @collection_name.setter
    def collection_name(self, collection_name: str) -> None:
        self.index_name = collection_name
        # Reset vectorstore when collection changes
        self._vectorstore = None

    @property 
    def vectorstore(self) -> OpenSearchVectorSearch:
        """Lazy initialization of vectorstore to follow documented pattern"""
        if self._vectorstore is None:
            self._vectorstore = self.get_langchain_vectorstore(self.index_name)
        return self._vectorstore

    # ---------------- Ingestion API ----------------
    def _ensure_index(self, index_name: str, dimensions: int) -> None:
        try:
            # LC creates index lazily; create explicitly to set k‑NN mapping
            client = self._make_low_level_client()
            if not client.indices.exists(index=index_name):
                settings = {"index": {"knn": True}}
                mappings = {
                    "properties": {
                        "text": {"type": "text"},
                        "vector": {
                            "type": "knn_vector",
                            "dimension": dimensions,
                            "method": {
                                "name": "hnsw",
                                "space_type": "l2",
                                "engine": "nmslib",
                            },
                        },
                        "metadata": {"type": "object", "enabled": True},
                    }
                }
                body = {"settings": settings, "mappings": mappings}
                client.indices.create(index=index_name, body=body)
        except Exception as e:
            logger.warning("OpenSearch ensure index failed: %s", e)

    def _infer_aws_service_name(self) -> str:
        try:
            override = os.getenv("APP_VECTORSTORE_AWS_SERVICE")
            if override:
                return override
            host = self.opensearch_url or ""
            if ".aoss." in host or "opensearchserverless" in host:
                return "aoss"
        except Exception:
            pass
        return "es"

    def _build_http_auth(self):
        username = os.getenv("APP_VECTORSTORE_USERNAME")
        password = os.getenv("APP_VECTORSTORE_PASSWORD")
        # Default to SigV4 if no basic auth credentials are provided
        aws_sigv4 = os.getenv("APP_VECTORSTORE_AWS_SIGV4", "true" if not (username and password) else "false").lower() == "true"

        if username and password:
            logger.info("Using basic authentication for OpenSearch")
            return (username, password), {}

        if aws_sigv4:
            try:
                from requests_aws4auth import AWS4Auth
                import boto3
                import re

                # Create boto3 session and get credentials (matches test_opensearch_sigv4.py)
                session = boto3.Session()
                creds = session.get_credentials().get_frozen_credentials()
                
                # Determine region with fallback logic
                region = os.getenv("APP_VECTORSTORE_AWS_REGION") or os.getenv("AWS_REGION")
                if not region:
                    region = session.region_name
                if not region and self.opensearch_url:
                    # Extract region from URL (for .amazonaws.com domains)
                    match = re.search(r"\.([a-z0-9-]+)\.amazonaws\.com", self.opensearch_url)
                    if match:
                        region = match.group(1)
                
                if not region:
                    raise ValueError("AWS region could not be determined. Set APP_VECTORSTORE_AWS_REGION or AWS_REGION")
                
                # Determine service name (matches _infer_aws_service_name logic)
                service = self._infer_aws_service_name()
                
                logger.info(f"Using SigV4 authentication for OpenSearch (service: {service}, region: {region})")
                
                # Create AWS4Auth instance (matches test_opensearch_sigv4.py exactly)
                awsauth = AWS4Auth(
                    creds.access_key,
                    creds.secret_key,
                    region,
                    service,
                    session_token=creds.token,
                )
                
                # Set service attribute for LangChain AOSS detection
                awsauth.service = service
                return awsauth, {"sigv4": True}
            except Exception as e:
                logger.error("SigV4 auth requested but failed to configure: %s", e)
                raise

        logger.warning("No authentication method configured for OpenSearch")
        return None, {}

    def _make_low_level_client(self):
        # Build OpenSearch client with env-driven auth (Basic or SigV4)
        from opensearchpy import OpenSearch, RequestsHttpConnection

        verify = os.getenv("APP_VECTORSTORE_VERIFYSSL", "true").lower() == "true"
        ca_certs = os.getenv("APP_VECTORSTORE_CA_CERT")
        client_cert = os.getenv("APP_VECTORSTORE_CLIENT_CERT")
        client_key = os.getenv("APP_VECTORSTORE_CLIENT_KEY")

        use_ssl = self.opensearch_url.startswith("https")

        http_auth, extras = self._build_http_auth()

        kwargs = {
            "hosts": [self.opensearch_url],
            "verify_certs": verify,
            "use_ssl": use_ssl,
        }
        
        # SSL/TLS certificate configuration
        if ca_certs:
            kwargs["ca_certs"] = ca_certs
        if client_cert and client_key:
            kwargs["client_cert"] = client_cert
            kwargs["client_key"] = client_key
        
        # Authentication configuration
        if http_auth is not None:
            kwargs["http_auth"] = http_auth
        
        # For SigV4, use RequestsHttpConnection and configure timeouts/retries
        # as demonstrated in the working test_opensearch_sigv4.py
        if extras.get("sigv4"):
            kwargs["connection_class"] = RequestsHttpConnection
            kwargs["timeout"] = int(os.environ.get("OS_REQUEST_TIMEOUT", 60))
            kwargs["max_retries"] = int(os.environ.get("OS_MAX_RETRIES", 1))
            kwargs["retry_on_timeout"] = True
        
        return OpenSearch(**kwargs)

    def create_index(self):
        logger.info("Creating OpenSearch index if not exists: %s", self.index_name)
        self._ensure_index(self.index_name, CONFIG.embeddings.dimensions)

    def _check_index_exists(self, index_name: str) -> bool:
        try:
            return self._make_low_level_client().indices.exists(index=index_name)
        except Exception as e:
            logger.warning("OpenSearch exists failed: %s", e)
            return False

    def write_to_index(self, records: list, **kwargs) -> None:
        cleaned_records = cleanup_records(
            records=records,
            meta_dataframe=self.meta_dataframe,
            meta_source_field=self.meta_source_field,
            meta_fields=self.meta_fields,
        )

        texts, embeddings, metadatas = [], [], []
        for item in cleaned_records:
            texts.append(item.get("text"))
            embeddings.append(item.get("vector"))
            metadatas.append(
                {
                    "source": item.get("source"),
                    "content_metadata": item.get("content_metadata"),
                }
            )

        total = len(texts)
        batch_size = 200
        uploaded = 0

        logger.info("Commencing OpenSearch ingestion for %s records…", total)

        # Ensure index exists with proper mapping
        self._ensure_index(self.index_name, CONFIG.embeddings.dimensions)

        client = self._make_low_level_client()
        for i in range(0, total, batch_size):
            end = min(i + batch_size, total)
            batch_actions = []
            for j in range(i, end):
                batch_actions.append({
                    "index": {"_index": self.index_name}
                })
                batch_actions.append({
                    "text": texts[j],
                    "vector": embeddings[j],
                    "metadata": metadatas[j],
                })
            try:
                # Use bulk API with newline-delimited JSON payload
                client.bulk(body=batch_actions)
            except Exception as e:
                logger.error("OpenSearch bulk indexing failed: %s", e)
                raise
            uploaded += end - i
            if uploaded % (5 * batch_size) == 0 or uploaded == total:
                logger.info(
                    "Ingested %s/%s into OpenSearch index %s",
                    uploaded,
                    total,
                    self.index_name,
                )

        # Best-effort refresh (not available in OpenSearch Serverless)
        is_aoss = self._infer_aws_service_name() == "aoss"
        try:
            client.indices.refresh(index=self.index_name)
            if not is_aoss:
                logger.debug(f"Index {self.index_name} refreshed successfully")
        except Exception as e:
            if is_aoss:
                # OpenSearch Serverless doesn't support refresh operation
                # Add a small delay to allow for eventual consistency
                logger.debug("Index refresh not available for OpenSearch Serverless (expected): %s", e)
                time.sleep(1)
            else:
                # Regular OpenSearch should support refresh - log warning
                logger.warning(f"Index refresh failed unexpectedly for OpenSearch Service: {e}")

    def retrieval(self, queries: list, **kwargs) -> list[dict[str, Any]]:
        raise NotImplementedError("retrieval must be implemented for OpenSearchVDB")

    def reindex(self, records: list, **kwargs) -> None:
        raise NotImplementedError("reindex must be implemented for OpenSearchVDB")

    def run(self, records: list) -> None:
        self.create_index()
        self.write_to_index(records)

    # ---------------- Health & Collections ----------------
    async def check_health(self) -> dict[str, Any]:
        status = {
            "service": "OpenSearch",
            "url": self.opensearch_url,
            "status": "unknown",
            "error": None,
        }
        if not self.opensearch_url:
            status["status"] = "skipped"
            status["error"] = "No URL provided"
            return status
        try:
            start = time.time()
            client = self._make_low_level_client()
            
            # For OpenSearch Serverless, cluster health is not available
            # Follow the same pattern as test_opensearch_sigv4.py
            cluster_health = {"status": "unknown"}
            try:
                # Try cluster health for regular OpenSearch Service
                cluster_health = client.cluster.health()
            except Exception:
                # OpenSearch Serverless doesn't support cluster.health
                # This is expected and not an error
                logger.debug("Cluster health not available (expected for OpenSearch Serverless)")
            
            # Test connectivity with indices list (available in both Service and Serverless)
            try:
                indices = client.cat.indices(format="json")
                indices_count = len(indices)
            except Exception as e:
                # If indices list fails, try a simpler connectivity test
                logger.warning("Failed to list indices, trying basic connectivity: %s", e)
                # Try index exists check as a basic connectivity test
                client.indices.exists(index="__connectivity_test__")
                indices_count = 0  # We don't know the count, but connection works
            
            status["status"] = "healthy"
            status["latency_ms"] = round((time.time() - start) * 1000, 2)
            status["indices"] = indices_count
            status["cluster_status"] = cluster_health.get("status", "unknown")
            
            # Log successful connection details
            service_type = self._infer_aws_service_name()
            auth_type = "SigV4" if os.getenv("APP_VECTORSTORE_AWS_SIGV4", "true").lower() == "true" else "Basic"
            logger.info(f"OpenSearch connection healthy (service: {service_type}, auth: {auth_type})")
            
        except Exception as e:
            status["status"] = "error"
            status["error"] = str(e)
            logger.error("OpenSearch health check failed: %s", e)
        return status

    def create_collection(self, collection_name: str, dimension: int = 2048, collection_type: str = "text") -> None:
        self._ensure_index(collection_name, dimension)
        try:
            client = self._make_low_level_client()
            # For OpenSearch Serverless, cluster health operations may not be available
            try:
                client.cluster.health(index=collection_name, wait_for_status="yellow", timeout=5)
            except Exception:
                # Skip cluster health wait for OpenSearch Serverless
                pass
        except Exception:
            pass

    def check_collection_exists(self, collection_name: str) -> bool:
        return self._check_index_exists(collection_name)

    def get_collection(self):
        self.create_metadata_schema_collection()
        client = self._make_low_level_client()
        indices = client.cat.indices(format="json")
        info = []
        for idx in indices:
            name = idx["index"]
            if not name.startswith("."):
                metadata_schema = self.get_metadata_schema(name)
                info.append({
                    "collection_name": name,
                    "num_entities": idx.get("docs.count", 0),
                    "metadata_schema": metadata_schema
                })
        return info

    def delete_collections(self, collection_names: list[str]) -> dict[str, Any]:
        client = self._make_low_level_client()
        _ = client.indices.delete(
            index=",".join(collection_names), ignore_unavailable=True
        )
        
        # Delete the metadata schema from the collection
        is_aoss = self._infer_aws_service_name() == "aoss"
        
        for collection_name in collection_names:
            if not is_aoss:
                # For regular OpenSearch, use delete_by_query
                try:
                    _ = client.delete_by_query(
                        index=DEFAULT_METADATA_SCHEMA_COLLECTION,
                        body=get_delete_metadata_schema_query(collection_name),
                    )
                except Exception as e:
                    logger.warning(f"Could not delete metadata schema for {collection_name}: {e}")
            else:
                # For OpenSearch Serverless, search and delete individual documents
                try:
                    query = get_metadata_schema_query(collection_name)
                    response = client.search(
                        index=DEFAULT_METADATA_SCHEMA_COLLECTION, 
                        body=query,
                        size=100
                    )
                    
                    # Delete each found document individually
                    for hit in response.get("hits", {}).get("hits", []):
                        try:
                            client.delete(
                                index=DEFAULT_METADATA_SCHEMA_COLLECTION,
                                id=hit["_id"]
                            )
                        except Exception as e:
                            logger.warning(f"Could not delete metadata schema document {hit['_id']}: {e}")
                except Exception as e:
                    logger.warning(f"Could not clean up metadata schema for {collection_name}: {e}")
        
        return {
            "message": "Collection deletion process completed.",
            "successful": collection_names,
            "failed": [],
            "total_success": len(collection_names),
            "total_failed": 0,
        }

    def get_documents(self, collection_name: str, retry_for_consistency: bool = None, bypass_validation: bool = False) -> list[dict[str, Any]]:
        metadata_schema = self.get_metadata_schema(collection_name)
        client = self._make_low_level_client()
        
        # Check if this is OpenSearch Serverless for eventual consistency handling
        is_aoss = self._infer_aws_service_name() == "aoss"
        
        # For OpenSearch, enable retry when bypass_validation=True
        # This covers the main validation case from ingestor server
        if retry_for_consistency is None:
            retry_for_consistency = bypass_validation  # Only retry extensively when validating
        
        # Smart retry settings based on service type and call context
        # Service-specific defaults handle eventual consistency differences automatically
        if bypass_validation:
            # Validation call - use generous retries for eventual consistency
            if is_aoss:
                max_retries = 8    # OpenSearch Serverless: slower indexing
                retry_delay = 15.0
            else:
                max_retries = 3    # OpenSearch Service: faster indexing with refresh
                retry_delay = 2.0
        else:
            # Initial check - use minimal retries to stay under client timeout
            if is_aoss:
                max_retries = 3    # Quick check for newly created collections
                retry_delay = 5.0  # 3 × 5s = 15s max
            else:
                max_retries = 1    # Regular OpenSearch: immediate consistency with refresh
                retry_delay = 1.0
        
        if bypass_validation and retry_for_consistency:
            service_type = "OpenSearch Serverless" if is_aoss else "OpenSearch Service"
            logger.info(
                f"{service_type} validation call detected - enabling {max_retries} retries "
                f"with {retry_delay}s delays for eventual consistency"
            )
        
        for attempt in range(max_retries):
            try:
                # Try aggregation query first
                response = client.search(
                    index=collection_name, body=get_unique_sources_query()
                )
                
                # Check if aggregations exist in response
                if "aggregations" not in response:
                    logger.debug("No aggregations in response, trying simple search")
                    raise KeyError("aggregations")
                
                # Check if we actually have results
                buckets = response.get("aggregations", {}).get("unique_sources", {}).get("buckets", [])
                if not buckets and attempt < max_retries - 1:
                    logger.debug(f"No aggregation results on attempt {attempt + 1}, retrying in {retry_delay}s for eventual consistency")
                    time.sleep(retry_delay)
                    continue
                    
                documents_list = []
                for hit in buckets:
                    source_name = hit["key"]["source_name"]
                    metadata = (
                        hit["top_hit"]["hits"]["hits"][0]["_source"]
                        .get("metadata", {})
                        .get("content_metadata", {})
                    )
                    metadata_dict = {}
                    for metadata_item in metadata_schema:
                        metadata_name = metadata_item.get("name")
                        metadata_value = metadata.get(metadata_name, None)
                        metadata_dict[metadata_name] = metadata_value
                    documents_list.append(
                        {
                            "document_name": os.path.basename(source_name),
                            "metadata": metadata_dict,
                        }
                    )
                return documents_list
                
            except (KeyError, Exception) as e:
                if attempt < max_retries - 1:
                    logger.debug(f"Aggregation query failed on attempt {attempt + 1} ({e}), retrying in {retry_delay}s")
                    time.sleep(retry_delay)
                    continue
                else:
                    logger.debug("Aggregation query failed (%s), falling back to simple search", e)
            
        # Fallback to simple search for OpenSearch Serverless compatibility
        for attempt in range(max_retries):
            try:
                response = client.search(
                    index=collection_name,
                    body={
                        "size": 100,  # Limit results
                        "query": {"match_all": {}},
                        "_source": ["metadata"]
                    }
                )
                
                # Check if we have results
                hits = response.get("hits", {}).get("hits", [])
                if not hits and attempt < max_retries - 1:
                    logger.debug(f"No simple search results on attempt {attempt + 1}, retrying in {retry_delay}s for eventual consistency")
                    time.sleep(retry_delay)
                    continue
                
                documents_list = []
                seen_sources = set()
                
                for hit in hits:
                    source_data = hit.get("_source", {})
                    metadata = source_data.get("metadata", {})
                    
                    # Extract source name from different possible locations
                    source_name = None
                    if isinstance(metadata, dict):
                        # Try different source field patterns
                        source_name = (
                            metadata.get("source", {}).get("source_name") if isinstance(metadata.get("source"), dict) else
                            metadata.get("source_name") or
                            metadata.get("content_metadata", {}).get("source") or
                            "unknown_source"
                        )
                    
                    if source_name and source_name not in seen_sources:
                        seen_sources.add(source_name)
                        
                        metadata_dict = {}
                        content_metadata = metadata.get("content_metadata", {}) if isinstance(metadata, dict) else {}
                        
                        for metadata_item in metadata_schema:
                            metadata_name = metadata_item.get("name")
                            metadata_value = content_metadata.get(metadata_name, None) if isinstance(content_metadata, dict) else None
                            metadata_dict[metadata_name] = metadata_value
                            
                        documents_list.append({
                            "document_name": os.path.basename(str(source_name)),
                            "metadata": metadata_dict,
                        })
                
                return documents_list
                
            except Exception as fallback_e:
                if attempt < max_retries - 1:
                    logger.debug(f"Simple search failed on attempt {attempt + 1} ({fallback_e}), retrying in {retry_delay}s")
                    time.sleep(retry_delay)
                    continue
                else:
                    logger.warning("Both aggregation and simple search failed: %s", fallback_e)
                    return []

    def delete_documents(self, collection_name: str, source_values: list[str]) -> bool:
        client = self._make_low_level_client()
        
        # Check if this is OpenSearch Serverless
        is_aoss = self._infer_aws_service_name() == "aoss"
        
        for val in source_values:
            try:
                if is_aoss:
                    # OpenSearch Serverless doesn't support delete_by_query
                    # Use search + individual deletes as a workaround
                    logger.info(f"Using individual document deletion for OpenSearch Serverless (source: {val})")
                    
                    query = get_delete_docs_query(val)
                    response = client.search(
                        index=collection_name,
                        body=query,
                        size=1000  # Process in batches to avoid large result sets
                    )
                    
                    deleted_count = 0
                    for hit in response.get("hits", {}).get("hits", []):
                        try:
                            client.delete(
                                index=collection_name,
                                id=hit["_id"]
                            )
                            deleted_count += 1
                        except Exception as e:
                            logger.warning(f"Could not delete document {hit['_id']}: {e}")
                    
                    logger.info(f"Deleted {deleted_count} documents for source: {val}")
                else:
                    client.delete_by_query(
                        index=collection_name,
                        body=get_delete_docs_query(val),
                    )
            except Exception as e:
                logger.warning("Delete by source failed for %s: %s", val, e)
        
        try:
            if not is_aoss:
                client.indices.refresh(index=collection_name)
                logger.debug(f"Index {collection_name} refreshed after deletion")
        except Exception as e:
            # Regular OpenSearch Service should support refresh
            logger.warning(f"Index refresh after deletion failed for OpenSearch Service: %s", e)
        return True

    def create_metadata_schema_collection(self) -> None:
        """Create a metadata schema collection."""
        mapping = create_metadata_collection_mapping()
        if not self.check_collection_exists(collection_name=DEFAULT_METADATA_SCHEMA_COLLECTION):
            client = self._make_low_level_client()
            client.indices.create(
                index=DEFAULT_METADATA_SCHEMA_COLLECTION, body=mapping
            )
            logging_message = (
                f"Collection {DEFAULT_METADATA_SCHEMA_COLLECTION} created "
                + f"at {self.opensearch_url} with mapping {mapping}"
            )
            logger.info(logging_message)
        else:
            logging_message = f"Collection {DEFAULT_METADATA_SCHEMA_COLLECTION} already exists at {self.opensearch_url}"
            logger.info(logging_message)

    def add_metadata_schema(
        self,
        collection_name: str,
        metadata_schema: list[dict[str, Any]],
    ) -> None:
        """Add metadata schema to an OpenSearch index."""
        client = self._make_low_level_client()
        
        # Check if this is OpenSearch Serverless
        is_aoss = self._infer_aws_service_name() == "aoss"
        
        if not is_aoss:
            # For regular OpenSearch, use delete_by_query to clean up existing schema
            try:
                _ = client.delete_by_query(
                    index=DEFAULT_METADATA_SCHEMA_COLLECTION,
                    body=get_delete_metadata_schema_query(collection_name),
                )
            except Exception as e:
                logger.warning(f"Could not delete existing metadata schema for {collection_name}: {e}")
        else:
            # For OpenSearch Serverless, search and delete individual documents
            try:
                query = get_metadata_schema_query(collection_name)
                response = client.search(
                    index=DEFAULT_METADATA_SCHEMA_COLLECTION, 
                    body=query,
                    size=100  # Limit to avoid large result sets
                )
                
                # Delete each found document individually
                for hit in response.get("hits", {}).get("hits", []):
                    try:
                        client.delete(
                            index=DEFAULT_METADATA_SCHEMA_COLLECTION,
                            id=hit["_id"]
                        )
                    except Exception as e:
                        logger.warning(f"Could not delete metadata schema document {hit['_id']}: {e}")
            except Exception as e:
                logger.warning(f"Could not clean up existing metadata schema for {collection_name}: {e}")
        
        # Add the metadata schema to the index
        data = {
            "collection_name": collection_name,
            "metadata_schema": metadata_schema,
        }
        client.index(index=DEFAULT_METADATA_SCHEMA_COLLECTION, body=data)
        logger.info(
            f"Metadata schema added to the OpenSearch index {collection_name}. Metadata schema: {metadata_schema}"
        )

    def get_metadata_schema(
        self,
        collection_name: str,
    ) -> list[dict[str, Any]]:
        """Get the metadata schema for a collection in the OpenSearch index."""
        try:
            query = get_metadata_schema_query(collection_name)
            client = self._make_low_level_client()
            response = client.search(
                index=DEFAULT_METADATA_SCHEMA_COLLECTION, body=query
            )
            if len(response["hits"]["hits"]) > 0:
                return response["hits"]["hits"][0]["_source"]["metadata_schema"]
            else:
                logging_message = (
                    f"No metadata schema found for the collection: {collection_name}."
                    + " Possible reason: The collection is not created with metadata schema."
                )
                logger.info(logging_message)
                return []
        except Exception as e:
            logger.warning("Failed to get metadata schema for %s: %s", collection_name, e)
            return []

    # ---------------- Retrieval API ----------------
    def get_langchain_vectorstore(
        self, collection_name: str
    ) -> OpenSearchVectorSearch:
        verify = os.getenv("APP_VECTORSTORE_VERIFYSSL", "true").lower() == "true"
        ca_certs = os.getenv("APP_VECTORSTORE_CA_CERT")
        use_ssl = self.opensearch_url.startswith("https")

        http_auth, extras = self._build_http_auth()

        # Check if this is OpenSearch Serverless
        is_aoss = (
            http_auth is not None 
            and hasattr(http_auth, 'service') 
            and http_auth.service == "aoss"
        )
        
        # Configure LangChain vectorstore with same auth as low-level client
        vectorstore_kwargs = {
            "embedding_function": self.embedding_model,
            "index_name": collection_name,
            "opensearch_url": self.opensearch_url,
            "http_auth": http_auth,
            "use_ssl": use_ssl,
            "verify_certs": verify,
            "timeout": int(os.environ.get("OS_REQUEST_TIMEOUT", 600)),
        }
        
        # Add CA certs if specified
        if ca_certs:
            vectorstore_kwargs["ca_certs"] = ca_certs
        
        # For OpenSearch Serverless, set AOSS-specific configurations
        if is_aoss:
            logger.info("Configuring LangChain vectorstore for OpenSearch Serverless")
            vectorstore_kwargs["is_aoss"] = True
            vectorstore_kwargs["engine"] = "nmslib"  # AOSS default engine
            vectorstore_kwargs["is_appx_search"] = True  # AOSS only supports approximate search
            # Match our field names with LangChain expectations
            vectorstore_kwargs["vector_field"] = "vector"  # Our field name
            vectorstore_kwargs["text_field"] = "text"  # Our field name
            
            try:
                from opensearchpy import RequestsHttpConnection
                vectorstore_kwargs["connection_class"] = RequestsHttpConnection
                vectorstore_kwargs["timeout"] = int(os.environ.get("OS_REQUEST_TIMEOUT", 60))
                vectorstore_kwargs["max_retries"] = int(os.environ.get("OS_MAX_RETRIES", 1))
                vectorstore_kwargs["retry_on_timeout"] = True
                logger.info("✅ Using RequestsHttpConnection for LangChain AOSS compatibility")
            except ImportError:
                logger.warning("❌ RequestsHttpConnection not available, fallback to direct client")
            
        elif extras.get("sigv4"):
            # Regular OpenSearch Service with SigV4
            logger.info("Configuring LangChain vectorstore with SigV4 authentication")
            # Also use RequestsHttpConnection for regular OpenSearch with SigV4
            try:
                from opensearchpy import RequestsHttpConnection
                vectorstore_kwargs["connection_class"] = RequestsHttpConnection
                vectorstore_kwargs["timeout"] = int(os.environ.get("OS_REQUEST_TIMEOUT", 60))
                vectorstore_kwargs["max_retries"] = int(os.environ.get("OS_MAX_RETRIES", 1))
                vectorstore_kwargs["retry_on_timeout"] = True
                logger.info("✅ Using RequestsHttpConnection for SigV4 compatibility")
            except ImportError:
                logger.warning("❌ RequestsHttpConnection not available")
                pass
        
        vectorstore = OpenSearchVectorSearch(**vectorstore_kwargs)
        return vectorstore

    def retrieval_langchain(
        self,
        query: str,
        collection_name: str,
        vectorstore: OpenSearchVectorSearch | None = None,
        top_k: int = 10,
        filter_expr: str | list[dict[str, Any]] = "",
        otel_ctx: Any = None,
    ) -> list[dict[str, Any]]:
        # Check if this is OpenSearch Serverless
        is_aoss = self._infer_aws_service_name() == "aoss"
        
        # Try LangChain first, fall back to direct client if it fails
        try:
            if vectorstore is None:
                vectorstore = self.get_langchain_vectorstore(collection_name)

            token = None
            if otel_ctx is not None:
                try:
                    token = otel_context.attach(otel_ctx)
                except Exception:
                    token = None

            start_time = time.time()
            retriever = vectorstore.as_retriever(search_kwargs={"k": top_k, "fetch_k": top_k})
            
            # Clean up filter_expr for LangChain compatibility
            clean_filter = None
            if filter_expr and filter_expr != "" and filter_expr != []:
                clean_filter = filter_expr
            
            retriever_lambda = RunnableLambda(lambda x: retriever.invoke(x, filter=clean_filter))
            retriever_chain = {"context": retriever_lambda} | RunnableAssign({"context": lambda input: input["context"]})
            retriever_docs = retriever_chain.invoke(query, config={"run_name": "retriever"})
            docs = retriever_docs.get("context", [])
            latency = time.time() - start_time
            logger.info(" OpenSearch LangChain Retrieval latency: %.4f seconds", latency)

            if token is not None:
                try:
                    otel_context.detach(token)
                except Exception:
                    pass

            return self._add_collection_name_to_retreived_docs(docs, collection_name)
            
        except Exception as e:
            # Handle various LangChain compatibility issues
            if any(issue in str(e) for issue in [
                "AWS4Auth", 
                "takes 2 positional arguments but 4 were given",
                "filter doesn't support values of type: VALUE_STRING",
                "x_content_parse_exception",
                "vector_field' is not knn_vector type",
                "search_phase_execution_exception"
            ]):
                # Known compatibility issues - fall back to direct client
                logger.warning("🔄 LangChain compatibility issue detected, falling back to direct client: %s", e)
                return self._direct_vector_search(query, collection_name, top_k, filter_expr, otel_ctx)
            else:
                # Unexpected error - log and re-raise
                logger.error("❌ LangChain retrieval failed unexpectedly: %s", e)
                raise
    
    def _direct_vector_search(
        self,
        query: str,
        collection_name: str,
        top_k: int = 10,
        filter_expr: str | list[dict[str, Any]] = "",
        otel_ctx: Any = None,
    ) -> list[Document]:
        """Direct vector search using OpenSearch client (AOSS-compatible)."""
        if not self.embedding_model:
            logger.error("Embedding model not configured for direct search")
            return []
        
        try:
            # Generate query embedding
            query_vector = self.embedding_model.embed_query(query)
            
            # Build search query
            search_body = {
                "size": top_k,
                "query": {
                    "knn": {
                        "vector": {
                            "vector": query_vector,
                            "k": top_k
                        }
                    }
                }
            }
            
            # Add filters if provided
            if filter_expr:
                if isinstance(filter_expr, str) and filter_expr.strip():
                    # Simple string filter - convert to match query
                    search_body["query"] = {
                        "bool": {
                            "must": [
                                search_body["query"],
                                {"match": {"text": filter_expr}}
                            ]
                        }
                    }
                elif isinstance(filter_expr, list):
                    # Complex filter
                    search_body["query"] = {
                        "bool": {
                            "must": [search_body["query"]],
                            "filter": filter_expr
                        }
                    }
            
            # Execute search
            client = self._make_low_level_client()
            start_time = time.time()
            
            response = client.search(index=collection_name, body=search_body)
            
            latency = time.time() - start_time
            logger.info(" OpenSearch Direct Retrieval latency: %.4f seconds", latency)
            
            # Convert results to Document objects
            docs = []
            for hit in response.get("hits", {}).get("hits", []):
                source = hit.get("_source", {})
                doc = Document(
                    page_content=source.get("text", ""),
                    metadata=source.get("metadata", {})
                )
                docs.append(doc)
            
            return self._add_collection_name_to_retreived_docs(docs, collection_name)
            
        except Exception as e:
            logger.error("Direct vector search failed: %s", e)
            return []

    @staticmethod
    def _add_collection_name_to_retreived_docs(docs: list[Document], collection_name: str) -> list[Document]:
        for doc in docs:
            doc.metadata["collection_name"] = collection_name
        return docs
