# LLM NIM Function Calling Validation

## Purpose
This script is designed to validate the functionality of an LLM-based tool by interacting with an API that processes user-defined messages and returns appropriate responses. The script can be configured to use different models and can handle function calls within the messages.

## Usage

### Command-Line Arguments
- `--model`: The name of the LLM model to be used. This argument is optional, with the default being `meta/llama-3_1-8b-instruct`.
- `--url`: The endpoint URL to which the request will be sent. This argument is required.

### Running the Script
To run the script, use the following command:

```bash
python test_function_calling.py --model <model-name> --url <url>
```

Replace `<model-name>` with the desired model (e.g., `meta/llama-3_1-8b-instruct`), and `<url>` with the endpoint URL.

### Example
```bash
python test_function_calling.py --model meta/llama-3_1-8b-instruct --url https://integrate.api.nvidia.com
```

### Parameters
- `model`: The name of the LLM model to be used (default: `meta/llama-3_1-8b-instruct`).
- `url`: The endpoint URL where the requests will be sent.

## Requirements
- Python 3.x
- `requests` module (`pip install requests`)

## Example Output
When the script is executed, it will print the initial response from the API and the follow-up response after handling any function calls.

```json
Initial Response
{
    "id": "example-response-id",
    "object": "chat.completion",
    "created": 1686602098,
    "choices": [
        {
            "message": {
                "role": "assistant",
                "content": "Hi! I am quite well, how can I help you today?"
            },
            "tool_calls": [
                {
                    "type": "function",
                    "function": {
                        "name": "get_current_weather",
                        "arguments": "{\"location\":\"San Francisco, CA\",\"format\":\"fahrenheit\"}"
                    }
                }
            ]
        }
    ]
}

Follow up Response
{
    "id": "example-follow-up-id",
    "object": "chat.completion",
    "created": 1686602100,
    "choices": [
        {
            "message": {
                "role": "tool",
                "content": "{\"temperature\":68,\"unit\":\"fahrenheit\"}",
                "tool_call_id": "example-tool-call-id"
            }
        }
    ]
}
```
