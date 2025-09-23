#!/usr/bin/env python3
"""
S3 to RAG Ingestion Script

This script fetches PDF files from an S3 bucket and ingests them into the RAG system
using the ingestion server API. It uses DynamoDB to track already ingested files
to avoid re-processing on subsequent runs.

Usage:
    python s3_to_rag_ingestion.py --bucket my-pdf-bucket --endpoint http://localhost:8082 --collection multimodal_data

Dependencies:
    pip install boto3 aiohttp asyncio argparse
"""

import argparse
import asyncio
import json
import logging
import os
import tempfile
from datetime import datetime
from typing import Dict, List, Optional, Set

import aiohttp
import requests
import boto3
from botocore.exceptions import ClientError, NoCredentialsError
from urllib.parse import unquote

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class DynamoDBTracker:
    """Handles tracking of ingested files in DynamoDB"""
    
    def __init__(self, table_name: str = "rag-ingested-files"):
        self.table_name = table_name
        self.dynamodb = boto3.resource('dynamodb')
        self.table = None
        self._ensure_table_exists()
    
    def _ensure_table_exists(self):
        """Create DynamoDB table if it doesn't exist"""
        try:
            self.table = self.dynamodb.Table(self.table_name)
            # Check if table exists by attempting to load it
            self.table.load()
            logger.info(f"Using existing DynamoDB table: {self.table_name}")
        except ClientError as e:
            if e.response['Error']['Code'] == 'ResourceNotFoundException':
                logger.info(f"Creating DynamoDB table: {self.table_name}")
                self._create_table()
            else:
                raise
    
    def _create_table(self):
        """Create the DynamoDB table"""
        self.table = self.dynamodb.create_table(
            TableName=self.table_name,
            KeySchema=[
                {
                    'AttributeName': 'file_key',
                    'KeyType': 'HASH'
                }
            ],
            AttributeDefinitions=[
                {
                    'AttributeName': 'file_key',
                    'AttributeType': 'S'
                }
            ],
            BillingMode='PAY_PER_REQUEST'
        )
        
        # Wait for table to be created
        self.table.wait_until_exists()
        logger.info(f"DynamoDB table {self.table_name} created successfully")
    
    def is_file_ingested(self, s3_key: str, etag: str) -> bool:
        """Check if file has already been ingested"""
        try:
            response = self.table.get_item(
                Key={'file_key': s3_key}
            )
            
            if 'Item' in response:
                stored_etag = response['Item'].get('etag', '')
                return stored_etag == etag
            return False
        except ClientError as e:
            logger.error(f"Error checking ingestion status for {s3_key}: {e}")
            return False
    
    def mark_file_ingested(self, s3_key: str, etag: str, collection_name: str, 
                          task_id: Optional[str] = None):
        """Mark file as ingested in DynamoDB"""
        try:
            self.table.put_item(
                Item={
                    'file_key': s3_key,
                    'etag': etag,
                    'collection_name': collection_name,
                    'ingested_at': datetime.utcnow().isoformat(),
                    'task_id': task_id or 'unknown'
                }
            )
            logger.info(f"Marked {s3_key} as ingested")
        except ClientError as e:
            logger.error(f"Error marking {s3_key} as ingested: {e}")
    
    def clear_all_tracked_files(self):
        """Clear all tracked files from DynamoDB table"""
        try:
            # Scan all items and delete them
            response = self.table.scan()
            
            with self.table.batch_writer() as batch:
                for item in response['Items']:
                    batch.delete_item(Key={'file_key': item['file_key']})
            
            # Handle pagination if there are more items
            while 'LastEvaluatedKey' in response:
                response = self.table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
                with self.table.batch_writer() as batch:
                    for item in response['Items']:
                        batch.delete_item(Key={'file_key': item['file_key']})
                        
            logger.info("All tracked files cleared from DynamoDB")
        except Exception as e:
            logger.error(f"Error clearing tracked files: {e}")
    
    def get_ingested_files(self) -> Set[str]:
        """Get set of all ingested file keys"""
        try:
            response = self.table.scan(
                ProjectionExpression='file_key'
            )
            return {item['file_key'] for item in response.get('Items', [])}
        except ClientError as e:
            logger.error(f"Error fetching ingested files: {e}")
            return set()


class S3PDFIngester:
    """Main class for ingesting PDFs from S3 to RAG system"""
    
    def __init__(self, bucket_name: str, ingestion_endpoint: str, collection_name: str,
                 dynamodb_table: str = "rag-ingested-files"):
        self.bucket_name = bucket_name
        self.ingestion_endpoint = ingestion_endpoint.rstrip('/')
        self.collection_name = collection_name
        self.s3_client = boto3.client('s3')
        self.tracker = DynamoDBTracker(dynamodb_table)
        
    async def list_pdf_files(self) -> List[Dict]:
        """List all PDF files in the S3 bucket"""
        try:
            paginator = self.s3_client.get_paginator('list_objects_v2')
            pdf_files = []
            
            for page in paginator.paginate(Bucket=self.bucket_name):
                if 'Contents' in page:
                    for obj in page['Contents']:
                        if obj['Key'].lower().endswith('.pdf'):
                            # Keep both original (for S3 operations) and decoded (for display/validation)
                            original_key = obj['Key']
                            decoded_key = unquote(original_key)
                            pdf_files.append({
                                'key': decoded_key,  # Decoded for filename matching
                                'original_key': original_key,  # Original for S3 operations
                                'etag': obj['ETag'].strip('"'),
                                'size': obj['Size'],
                                'last_modified': obj['LastModified']
                            })
            
            logger.info(f"Found {len(pdf_files)} PDF files in bucket {self.bucket_name}")
            return pdf_files
            
        except ClientError as e:
            logger.error(f"Error listing files from S3 bucket {self.bucket_name}: {e}")
            raise
    
    def download_file(self, s3_key: str, local_path: str) -> bool:
        """Download file from S3 to local path"""
        try:
            self.s3_client.download_file(self.bucket_name, s3_key, local_path)
            return True
        except ClientError as e:
            logger.error(f"Error downloading {s3_key}: {e}")
            return False
    
    async def check_ingestion_server_health(self) -> bool:
        """Check if ingestion server is healthy"""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(f"{self.ingestion_endpoint}/v1/health") as response:
                    if response.status == 200:
                        logger.info("Ingestion server is healthy")
                        return True
                    else:
                        logger.error(f"Ingestion server health check failed: {response.status}")
                        return False
        except Exception as e:
            logger.error(f"Error checking ingestion server health: {e}")
            return False
    
    async def check_collection_exists(self) -> bool:
        """Check if collection already exists"""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(f"{self.ingestion_endpoint}/v1/collections") as response:
                    if response.status == 200:
                        response_json = await response.json()
                        collections = response_json.get('collections', [])
                        # Check if collection_name exists in any of the collection objects
                        return any(col.get('collection_name') == self.collection_name for col in collections)
                    else:
                        logger.warning(f"Could not check existing collections: {response.status}")
                        return False
        except Exception as e:
            logger.warning(f"Error checking existing collections: {e}")
            return False

    async def create_collection(self) -> bool:
        """Create a new collection"""
        try:
            logger.info(f"Creating collection: {self.collection_name}")
            
            # Collection creation payload with optional metadata schema
            data = {
                "collection_name": self.collection_name,
                "embedding_dimension": 2048,
                "metadata_schema": [
                    {
                        "name": "s3_bucket",
                        "type": "string",
                        "description": "Source S3 bucket name"
                    },
                    {
                        "name": "s3_key", 
                        "type": "string",
                        "description": "S3 object key"
                    },
                    {
                        "name": "ingested_at",
                        "type": "datetime",
                        "description": "Timestamp when document was ingested"
                    }
                ]
            }
            
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f"{self.ingestion_endpoint}/v1/collection",
                    json=data,
                    headers={"Content-Type": "application/json"}
                ) as response:
                    if response.status in [200, 201]:
                        logger.info(f"✅ Successfully created collection: {self.collection_name}")
                        return True
                    elif response.status == 409:
                        logger.info(f"✅ Collection {self.collection_name} already exists")
                        return True
                    else:
                        response_text = await response.text()
                        logger.error(f"❌ Error creating collection: {response.status} - {response_text}")
                        return False
                        
        except Exception as e:
            logger.error(f"❌ Error creating collection: {e}")
            return False

    async def ensure_collection_exists(self) -> bool:
        """Ensure the target collection exists, create if it doesn't"""
        logger.info(f"🔍 Checking if collection '{self.collection_name}' exists...")
        
        # First check if collection already exists
        if await self.check_collection_exists():
            logger.info(f"✅ Collection '{self.collection_name}' already exists")
            return True
        
        # Create collection if it doesn't exist
        logger.info(f"📝 Collection '{self.collection_name}' not found, creating it...")
        return await self.create_collection()
    
    async def ingest_file(self, file_path: str, filename: str, s3_key: str) -> Optional[str]:
        """Ingest a single file to the RAG system"""
        try:
            # Add custom metadata that matches our collection schema
            # Use simple ISO format without Z suffix (the validator fails with Z)
            ingested_time = datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S')
            
            custom_metadata = [{
                "filename": filename,  # Must exactly match the uploaded file's filename
                "metadata": {
                    "s3_bucket": self.bucket_name,
                    "s3_key": s3_key,
                    "ingested_at": ingested_time
                }
            }]
            
            data = {
                "collection_name": self.collection_name,
                "blocking": False,
                "split_options": {"chunk_size": 512, "chunk_overlap": 150},
                "custom_metadata": custom_metadata,
                "generate_summary": False
            }
            
            logger.debug(f"📝 Ingestion payload for {filename}: {json.dumps(data, indent=2)}")
            logger.debug(f"📋 Custom metadata filename: '{custom_metadata[0]['filename']}'")
            
            form_data = aiohttp.FormData()
            
            # Read file content first, then add to form
            with open(file_path, 'rb') as f:
                file_content = f.read()
            
            # Add file - ensure filename exactly matches what we use in custom_metadata
            form_data.add_field(
                "documents",
                file_content,
                filename=filename,  # This must match custom_metadata[0]["filename"]
                content_type="application/pdf"
            )
            
            logger.debug(f"📎 Form field filename: '{filename}'")
            logger.debug(f"📎 Form field filename bytes: {filename.encode('utf-8')}")
            logger.debug(f"📎 Form field filename repr: {repr(filename)}")
            logger.debug(f"🔍 File path basename: '{os.path.basename(file_path)}'")
            logger.debug(f"📝 S3 key basename: '{os.path.basename(s3_key)}'")
            logger.debug(f"📝 Custom metadata filename bytes: {custom_metadata[0]['filename'].encode('utf-8')}")
            logger.debug(f"📝 Custom metadata filename repr: {repr(custom_metadata[0]['filename'])}")
            
            # Add metadata
            form_data.add_field(
                "data", 
                json.dumps(data), 
                content_type="application/json"
            )
            
            # Try with requests library first for better multipart handling
            try:
                files = {
                    'documents': (filename, file_content, 'application/pdf')
                }
                data_payload = {
                    'data': json.dumps(data)
                }
                
                logger.debug(f"🔗 Using requests library for {filename}")
                response = requests.post(
                    f"{self.ingestion_endpoint}/v1/documents",
                    files=files,
                    data=data_payload,
                    timeout=30
                )
                
                if response.status_code in [200, 201, 202]:
                    response_json = response.json()
                    task_id = response_json.get('task_id')
                    logger.info(f"Successfully submitted {filename} for ingestion (task_id: {task_id})")
                    return task_id
                else:
                    logger.error(f"Error ingesting {filename} with requests: {response.status_code} - {response.text}")
                    # Fall back to aiohttp
                    raise Exception("Requests failed, trying aiohttp")
                    
            except Exception as e:
                logger.warning(f"Requests method failed for {filename}: {e}, falling back to aiohttp")
                
                # Fallback to original aiohttp method
                async with aiohttp.ClientSession() as session:
                    async with session.post(
                        f"{self.ingestion_endpoint}/v1/documents",
                        data=form_data
                    ) as response:
                        if response.status in [200, 201, 202]:
                            response_json = await response.json()
                            task_id = response_json.get('task_id')
                            logger.info(f"Successfully submitted {filename} for ingestion (task_id: {task_id})")
                            return task_id
                        else:
                            response_text = await response.text()
                            logger.error(f"Error ingesting {filename}: {response.status} - {response_text}")
                            return None
                            
        except Exception as e:
            logger.error(f"Error ingesting file {filename}: {e}")
            return None
    
    async def get_collection_documents_count(self) -> Optional[int]:
        """Get the number of documents in the collection"""
        try:
            async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=30)) as session:
                async with session.get(
                    f"{self.ingestion_endpoint}/v1/documents",
                    params={"collection_name": self.collection_name}
                ) as response:
                    if response.status == 200:
                        response_json = await response.json()
                        total_documents = response_json.get('total_documents', 0)
                        logger.info(f"📊 Collection '{self.collection_name}' contains {total_documents} documents")
                        
                        # Log sample document names for debugging
                        if response_json.get('documents'):
                            sample_docs = [doc.get('document_name', 'unknown') 
                                         for doc in response_json['documents'][:3]]
                            logger.debug(f"Sample documents: {sample_docs}")
                        
                        return total_documents
                    else:
                        logger.error(f"Failed to get documents count: {response.status}")
                        return None
        except Exception as e:
            logger.error(f"Error getting collection documents count: {e}")
            return None
    
    async def get_task_status(self, task_id: str) -> Optional[str]:
        """Get the status of an ingestion task"""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(
                    f"{self.ingestion_endpoint}/v1/status",
                    params={"task_id": task_id}
                ) as response:
                    if response.status == 200:
                        response_json = await response.json()
                        status = response_json.get('state', 'UNKNOWN')
                        
                        # Log additional details if task failed
                        if status == 'FAILED':
                            result = response_json.get('result', {})
                            message = result.get('message', 'No error message')
                            logger.error(f"❌ Task {task_id} failed: {message}")
                            
                            # Log validation errors if available
                            validation_errors = result.get('validation_errors', [])
                            if validation_errors:
                                for error in validation_errors[:3]:  # Show first 3 errors
                                    logger.error(f"  📋 Validation error: {error.get('error', 'Unknown error')}")
                        
                        return status
                    else:
                        logger.warning(f"Status check failed for {task_id}: HTTP {response.status}")
                        return None
        except Exception as e:
            logger.error(f"Error getting task status for {task_id}: {e}")
            return None
    
    async def get_collection_documents_count(self) -> Optional[int]:
        """Get the number of documents in the collection using ingestor server"""
        try:
            # Use a longer timeout for document listing
            timeout = aiohttp.ClientTimeout(total=30)
            async with aiohttp.ClientSession(timeout=timeout) as session:
                # Use the ingestor server's documents endpoint to list documents in the collection
                logger.info(f"🔍 Checking documents in collection '{self.collection_name}' via ingestor server...")
                async with session.get(
                    f"{self.ingestion_endpoint}/v1/documents",
                    params={"collection_name": self.collection_name}
                ) as response:
                    if response.status == 200:
                        response_json = await response.json()
                        # The response should contain a list of documents
                        documents = response_json.get('documents', [])
                        total_documents = response_json.get('total_documents', len(documents))
                        
                        logger.info(f"📊 Collection '{self.collection_name}' contains {total_documents} documents")
                        
                        # Log some document names for debugging
                        if documents and logger.level <= logging.DEBUG:
                            doc_names = [doc.get('document_name', 'unknown') for doc in documents[:5]]
                            logger.debug(f"Sample documents: {doc_names}")
                        
                        return total_documents
                    elif response.status == 404:
                        logger.warning(f"⚠️ Collection '{self.collection_name}' not found")
                        return None
                    else:
                        response_text = await response.text()
                        logger.warning(f"Could not check collection documents: {response.status} - {response_text}")
                        return None
                        
        except Exception as e:
            logger.warning(f"Error checking collection documents: {e}")
            return None
    
    async def process_files(self, dry_run: bool = False) -> Dict:
        """Process all PDF files from S3"""
        stats = {
            'total_files': 0,
            'already_ingested': 0,
            'newly_ingested': 0,
            'failed': 0,
            'skipped': 0
        }
        
        # Check server health
        if not await self.check_ingestion_server_health():
            raise Exception("Ingestion server is not healthy")
        
        # Ensure collection exists
        if not await self.ensure_collection_exists():
            raise Exception("Failed to create/verify collection")
        
        # Get PDF files from S3
        pdf_files = await self.list_pdf_files()
        stats['total_files'] = len(pdf_files)
        
        if not pdf_files:
            logger.info("No PDF files found in the bucket")
            return stats
        
        # Process each file
        for file_info in pdf_files:
            s3_key = file_info['key']  # Decoded key for display and validation
            original_s3_key = file_info.get('original_key', s3_key)  # Original key for S3 operations
            etag = file_info['etag']
            filename = os.path.basename(s3_key)
            
            logger.info(f"Processing: {s3_key}")
            logger.debug(f"🏷️ Generated filename: '{filename}' from s3_key: '{s3_key}'")
            
            # Check if already ingested (use decoded key for consistency)
            if self.tracker.is_file_ingested(s3_key, etag):
                logger.info(f"Skipping {s3_key} - already ingested")
                stats['already_ingested'] += 1
                continue
            
            if dry_run:
                logger.info(f"DRY RUN: Would ingest {s3_key}")
                stats['skipped'] += 1
                continue
            
            # Download file to temporary location
            with tempfile.NamedTemporaryFile(suffix='.pdf', delete=False) as tmp_file:
                tmp_path = tmp_file.name
                
                try:
                    if self.download_file(original_s3_key, tmp_path):
                        # Ingest file (use decoded s3_key for metadata)
                        task_id = await self.ingest_file(tmp_path, filename, s3_key)
                        
                        if task_id:
                            logger.info(f"📋 Ingestion task submitted for {filename}: {task_id}")
                            
                            # Wait longer for task processing and check status with more detail
                            await asyncio.sleep(5)
                            task_status = await self.get_task_status(task_id)
                            if task_status:
                                logger.info(f"📊 Task {task_id} status: {task_status}")
                                
                                # Count based on actual task status
                                if task_status == 'FAILED':
                                    stats['failed'] += 1
                                    logger.error(f"❌ Task failed for {filename}")
                                    # Don't mark failed tasks as ingested in DynamoDB
                                elif task_status in ['SUCCESS', 'COMPLETED']:
                                    stats['newly_ingested'] += 1
                                    logger.info(f"✅ Task completed successfully for {filename}")
                                    # Only mark successful tasks as ingested
                                    self.tracker.mark_file_ingested(s3_key, etag, self.collection_name, task_id)
                                else:
                                    # PENDING, RUNNING, etc. - consider as in progress but don't mark as ingested yet
                                    stats['newly_ingested'] += 1
                                    logger.info(f"⏳ Task is processing for {filename} (status: {task_status})")
                                    # For pending tasks, mark as ingested (they might complete later)
                                    self.tracker.mark_file_ingested(s3_key, etag, self.collection_name, task_id)
                            else:
                                logger.warning(f"⚠️ Could not get status for task {task_id}")
                                stats['newly_ingested'] += 1  # Assume success if we can't check
                                self.tracker.mark_file_ingested(s3_key, etag, self.collection_name, task_id)
                        else:
                            logger.error(f"❌ Failed to submit ingestion task for {filename}")
                            stats['failed'] += 1
                    else:
                        stats['failed'] += 1
                        
                finally:
                    # Clean up temporary file
                    if os.path.exists(tmp_path):
                        os.unlink(tmp_path)
        
        return stats


async def main():
    parser = argparse.ArgumentParser(description='Ingest PDF files from S3 to RAG system')
    parser.add_argument('--bucket', required=True, help='S3 bucket name containing PDF files')
    parser.add_argument('--endpoint', required=True, help='RAG ingestion server endpoint')
    parser.add_argument('--collection', default='multimodal_data', help='Collection name for ingestion')
    parser.add_argument('--dynamodb-table', default='rag-ingested-files', help='DynamoDB table for tracking')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be ingested without actually doing it')
    parser.add_argument('--force', action='store_true', help='Force re-ingestion of all files (clears DynamoDB tracking)')
    parser.add_argument('--verbose', '-v', action='store_true', help='Enable verbose logging')
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    try:
        # Validate AWS credentials
        boto3.client('sts').get_caller_identity()
        logger.info("AWS credentials validated")
        
        # Initialize ingester
        ingester = S3PDFIngester(
            bucket_name=args.bucket,
            ingestion_endpoint=args.endpoint,
            collection_name=args.collection,
            dynamodb_table=args.dynamodb_table
        )
        
        # Handle force flag - clear DynamoDB tracking
        if args.force:
            logger.info("🔄 Force mode enabled - clearing DynamoDB tracking table...")
            ingester.tracker.clear_all_tracked_files()
            logger.info("✅ DynamoDB tracking table cleared")
        
        # Process files
        logger.info(f"Starting ingestion from bucket: {args.bucket}")
        logger.info(f"Target collection: {args.collection}")
        logger.info(f"Ingestion endpoint: {args.endpoint}")
        
        if args.dry_run:
            logger.info("DRY RUN MODE - No files will be actually ingested")
        
        stats = await ingester.process_files(dry_run=args.dry_run)
        
        # Print summary
        logger.info("=== Ingestion Summary ===")
        logger.info(f"Total files found: {stats['total_files']}")
        logger.info(f"Already ingested: {stats['already_ingested']}")
        logger.info(f"Newly ingested: {stats['newly_ingested']}")
        logger.info(f"Failed: {stats['failed']}")
        logger.info(f"Skipped: {stats['skipped']}")
        
        if stats['failed'] > 0:
            logger.warning(f"⚠️ {stats['failed']} files failed to ingest")
            if stats['newly_ingested'] > 0:
                logger.info(f"✅ {stats['newly_ingested']} files ingested successfully")
            return 1
        
        # Check if collection has documents for querying
        if not args.dry_run:
            logger.info("=== Collection Verification ===")
            doc_count = await ingester.get_collection_documents_count()
            if doc_count is None:
                logger.warning("⚠️ Could not verify collection document count")
            elif doc_count == 0:
                logger.error("❌ Collection exists but contains no documents - RAG queries will fail")
                logger.info("💡 This might indicate:")
                logger.info("   - Ingestion tasks are still processing (check task status)")
                logger.info("   - Document processing failed silently")
                logger.info("   - Collection was created but documents weren't added")
            else:
                logger.info(f"✅ Collection '{args.collection}' contains documents and is ready for queries")
        
        logger.info("Ingestion completed successfully")
        return 0
        
    except NoCredentialsError:
        logger.error("AWS credentials not found. Please configure AWS CLI or set environment variables.")
        return 1
    except Exception as e:
        logger.error(f"Error during ingestion: {e}")
        return 1


if __name__ == "__main__":
    exit(asyncio.run(main()))
