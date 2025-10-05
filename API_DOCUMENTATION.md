# Worker ComfyUI API Documentation

## Overview

Worker ComfyUI is a serverless API that runs ComfyUI workflows on RunPod. It allows you to submit ComfyUI workflows via HTTP requests and receive generated images as base64 strings or S3 URLs.

## Base URL

Your deployed endpoint URL follows this pattern:
```
https://api.runpod.ai/v2/<endpoint_id>/
```

## Authentication

All requests require Bearer token authentication using your RunPod API key:

```bash
Authorization: Bearer <your_runpod_api_key>
```

## Endpoints

### 1. Synchronous Execution - `/runsync`

Execute a workflow and wait for completion. Returns the result directly.

**Method:** `POST`
**URL:** `https://api.runpod.ai/v2/<endpoint_id>/runsync`
**Timeout:** Varies based on workflow complexity

### 2. Asynchronous Execution - `/run`

Submit a workflow for processing and get a job ID. Poll `/status` for results.

**Method:** `POST`
**URL:** `https://api.runpod.ai/v2/<endpoint_id>/run`

### 3. Job Status - `/status/<job_id>`

Check the status of an asynchronous job.

**Method:** `GET`
**URL:** `https://api.runpod.ai/v2/<endpoint_id>/status/<job_id>`

### 4. Health Check - `/health`

Check if the endpoint is healthy and ready to accept requests.

**Method:** `GET`
**URL:** `https://api.runpod.ai/v2/<endpoint_id>/health`

## Request Format

### Required Headers
```
Content-Type: application/json
Authorization: Bearer <your_runpod_api_key>
```

### Request Body Structure

```json
{
  "input": {
    "workflow": {
      // ComfyUI workflow JSON (exported via Workflow > Export API)
    },
    "images": [
      {
        "name": "input_image.png",
        "image": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUg..."
      }
    ]
  }
}
```

#### Field Descriptions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `input` | Object | Yes | Top-level container for request data |
| `input.workflow` | Object | Yes | ComfyUI workflow JSON (export from ComfyUI using "Workflow > Export (API)") |
| `input.images` | Array | No | Optional input images for the workflow |

#### Images Array (Optional)

Each image object must contain:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | String | Yes | Filename referenced in the workflow (e.g., in LoadImage nodes) |
| `image` | String | Yes | Base64 encoded image data (with or without data URI prefix) |

**Note:** Images are uploaded to ComfyUI's input directory and can be referenced by name in LoadImage nodes.

## Response Format

### Successful Response

```json
{
  "id": "sync-uuid-string",
  "status": "COMPLETED",
  "output": {
    "images": [
      {
        "filename": "ComfyUI_00001_.png",
        "type": "base64",
        "data": "iVBORw0KGgoAAAANSUhEUg..."
      }
    ],
    "errors": [
      "Warning: Some non-fatal issue occurred"
    ]
  },
  "delayTime": 123,
  "executionTime": 4567
}
```

#### Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | String | Unique job identifier |
| `status` | String | Job status: `COMPLETED`, `FAILED`, `IN_PROGRESS`, `IN_QUEUE` |
| `output` | Object | Contains the execution results |
| `output.images` | Array | Generated images (if any) |
| `output.errors` | Array | Non-fatal warnings/errors (optional) |
| `delayTime` | Number | Time spent in queue (milliseconds) |
| `executionTime` | Number | Time spent processing (milliseconds) |

#### Image Object Structure

| Field | Type | Description |
|-------|------|-------------|
| `filename` | String | Original filename from ComfyUI |
| `type` | String | `"base64"` or `"s3_url"` (depending on configuration) |
| `data` | String | Base64 encoded image or S3 URL |

### Error Response

```json
{
  "id": "sync-uuid-string",
  "status": "FAILED",
  "error": "Error message describing what went wrong"
}
```

## Example Usage

### Basic Text-to-Image Request

```bash
curl -X POST \
  -H "Authorization: Bearer <your_api_key>" \
  -H "Content-Type: application/json" \
  -d '{
    "input": {
      "workflow": {
        "6": {
          "inputs": {
            "text": "a beautiful landscape",
            "clip": ["30", 1]
          },
          "class_type": "CLIPTextEncode",
          "_meta": {
            "title": "CLIP Text Encode (Positive Prompt)"
          }
        },
        "30": {
          "inputs": {
            "ckpt_name": "flux1-dev-fp8.safetensors"
          },
          "class_type": "CheckpointLoaderSimple",
          "_meta": {
            "title": "Load Checkpoint"
          }
        }
      }
    }
  }' \
  https://api.runpod.ai/v2/<endpoint_id>/runsync
```

### Request with Input Images

```bash
curl -X POST \
  -H "Authorization: Bearer <your_api_key>" \
  -H "Content-Type: application/json" \
  -d '{
    "input": {
      "workflow": {
        // Your workflow JSON here
      },
      "images": [
        {
          "name": "input.png",
          "image": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUg..."
        }
      ]
    }
  }' \
  https://api.runpod.ai/v2/<endpoint_id>/runsync
```

### Asynchronous Request

```bash
# Submit job
JOB_ID=$(curl -X POST \
  -H "Authorization: Bearer <your_api_key>" \
  -H "Content-Type: application/json" \
  -d '{"input":{"workflow":{...}}}' \
  https://api.runpod.ai/v2/<endpoint_id>/run | jq -r '.id')

# Check status
curl -H "Authorization: Bearer <your_api_key>" \
  https://api.runpod.ai/v2/<endpoint_id>/status/$JOB_ID
```

## Getting Your Workflow JSON

1. Open ComfyUI in your browser
2. Create your desired workflow
3. Go to **Workflow > Export (API)**
4. Save the downloaded `workflow.json` file
5. Use the content of this file as the `input.workflow` value

## Configuration Options

### S3 Upload (Optional)

Configure these environment variables to upload images to S3 instead of returning base64:

- `BUCKET_ENDPOINT_URL`: S3 bucket endpoint URL
- `BUCKET_ACCESS_KEY_ID`: AWS access key ID
- `BUCKET_SECRET_ACCESS_KEY`: AWS secret access key

When S3 is configured, response images will have `type: "s3_url"` instead of `type: "base64"`.

### Other Configuration

- `REFRESH_WORKER`: Set to `"true"` to restart worker after each job
- `COMFY_LOG_LEVEL`: ComfyUI logging level (`DEBUG`, `INFO`, `WARNING`, `ERROR`)
- `WEBSOCKET_RECONNECT_ATTEMPTS`: Websocket reconnection attempts (default: 5)
- `WEBSOCKET_RECONNECT_DELAY_S`: Delay between reconnect attempts (default: 3)

## Rate Limits & Size Limits

- **Request Size Limits:**
  - `/run`: 10MB
  - `/runsync`: 20MB
- **Image Size:** Large base64 images may exceed request limits
- **Timeout:** `/runsync` requests may timeout for long-running workflows

## Error Handling

Common error scenarios:

### Workflow Validation Failed
```json
{
  "error": "Workflow validation failed: Node 30 (ckpt_name): 'model.safetensors' not in available models"
}
```
**Solution:** Ensure your workflow uses models available in the deployed image.

### Missing Input Images
```json
{
  "error": "Failed to upload one or more input images"
}
```
**Solution:** Check that image names in the request match those referenced in the workflow.

### ComfyUI Server Unreachable
```json
{
  "error": "ComfyUI server (127.0.0.1:8188) not reachable after multiple retries"
}
```
**Solution:** This indicates an internal server issue. Try again or contact support.

### Execution Error
```json
{
  "error": "Workflow execution error: Node Type: KSampler, Node ID: 31, Message: CUDA out of memory"
}
```
**Solution:** Reduce image dimensions, batch size, or use a GPU with more VRAM.

## Support

- **Documentation:** [GitHub Repository](https://github.com/runpod-workers/worker-comfyui)
- **Issues:** [GitHub Issues](https://github.com/runpod-workers/worker-comfyui/issues)
- **RunPod Docs:** [RunPod Documentation](https://docs.runpod.io/)