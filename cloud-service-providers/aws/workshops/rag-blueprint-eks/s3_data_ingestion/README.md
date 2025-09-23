# S3 to RAG Ingestion

Automatically ingest PDF files from S3 bucket into RAG system with DynamoDB tracking to avoid re-processing.

## Setup

### Environment Variables

Set up the resource names that will be used throughout:

```bash
# S3 bucket for storing PDF files (append with account id for uniqueness)
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
export S3_BUCKET_NAME="my-rag-pdf-bucket-$AWS_ACCOUNT_ID"

# DynamoDB table for tracking ingested files
export DYNAMODB_TABLE_NAME="rag-ingested-files"

# RAG collection name
export COLLECTION_NAME="multimodal_data"

# RAG Ingestor endpoint (use Load Balancer URL from deployment)
export RAG_INGESTOR_ENDPOINT="http://$(kubectl get svc ingestor-server -n nv-nvidia-blueprint-rag -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):8082"

# Alternative: If using port-forwarding instead of Load Balancer
# export RAG_INGESTOR_ENDPOINT="http://localhost:8082"
```

### Dependencies

Create and activate a virtual environment:

```bash
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install boto3 aiohttp
```

### AWS Resources
```bash
# Create S3 bucket and upload PDFs
aws s3 mb s3://$S3_BUCKET_NAME
aws s3 cp /path/to/pdfs/ s3://$S3_BUCKET_NAME/ --recursive --include "*.pdf"

# DynamoDB table (auto-created by script)
# Or create manually:
aws dynamodb create-table \
    --table-name $DYNAMODB_TABLE_NAME \
    --attribute-definitions AttributeName=file_key,AttributeType=S \
    --key-schema AttributeName=file_key,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST
```

### Prerequisites

Ensure your AWS credentials have permissions for:
- **S3**: `s3:GetObject`, `s3:ListBucket` on your bucket
- **DynamoDB**: `dynamodb:GetItem`, `dynamodb:PutItem`, `dynamodb:Scan`, `dynamodb:CreateTable`, `dynamodb:DescribeTable`

## Usage

### Basic
```bash
python3 s3_to_rag_ingestion.py \
    --bucket $S3_BUCKET_NAME \
    --endpoint $RAG_INGESTOR_ENDPOINT \
    --collection $COLLECTION_NAME
```

### Options
| Flag | Default | Description |
|------|---------|-------------|
| `--bucket` | Required | S3 bucket with PDFs |
| `--endpoint` | Required | RAG ingestion server URL |
| `--collection` | `$COLLECTION_NAME` | Collection name |
| `--dynamodb-table` | `$DYNAMODB_TABLE_NAME` | Tracking table |
| `--dry-run` | `False` | Preview mode |
| `--force` | `False` | Clear tracking and re-ingest all files |
| `--verbose` | `False` | Debug logging |

### Example with All Options
```bash
python3 s3_to_rag_ingestion.py \
    --bucket $S3_BUCKET_NAME \
    --endpoint $RAG_INGESTOR_ENDPOINT \
    --collection $COLLECTION_NAME \
    --dynamodb-table $DYNAMODB_TABLE_NAME \
    --verbose
```

### Force Re-ingestion
To re-ingest all files (useful after deleting collections or fixing issues):
```bash
python3 s3_to_rag_ingestion.py \
    --bucket $S3_BUCKET_NAME \
    --endpoint $RAG_INGESTOR_ENDPOINT \
    --collection $COLLECTION_NAME \
    --force
```

## Features

- **Auto-deduplication**: Tracks files by S3 ETag, skips unchanged files
- **Collection creation**: Automatically creates collection with metadata schema
- **Error handling**: Continues on failures, provides summary statistics
- **Progress tracking**: Real-time logging and final report

## Troubleshooting

| Error | Solution |
|-------|----------|
| AWS credentials not found | `aws configure` or set environment variables |
| S3 Access Denied | Check IAM S3 permissions |
| Ingestion server unreachable | Verify endpoint URL and server status |
| DynamoDB permissions | Add DynamoDB permissions to IAM role |
| Files marked as "already ingested" | Use `--force` flag to clear DynamoDB tracking |
| Collection has 0 documents after ingestion | Check ingestor server logs for validation errors |

### Common Use Cases

**Initial Setup:**
```bash
python3 s3_to_rag_ingestion.py --bucket $S3_BUCKET_NAME --endpoint $RAG_INGESTOR_ENDPOINT --collection $COLLECTION_NAME
```

**After Deleting Collection:**
```bash
python3 s3_to_rag_ingestion.py --bucket $S3_BUCKET_NAME --endpoint $RAG_INGESTOR_ENDPOINT --collection $COLLECTION_NAME --force
```

**Testing (Preview Only):**
```bash
python3 s3_to_rag_ingestion.py --bucket $S3_BUCKET_NAME --endpoint $RAG_INGESTOR_ENDPOINT --collection $COLLECTION_NAME --dry-run
```
