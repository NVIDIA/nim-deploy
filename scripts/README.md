```markdown
# LLM NIM Function Calling Validation

## Purpose
This script is designed to test the functionality of tool calling feature in LLM NIMs.

## Usage

### Command-Line Arguments
- `--model`: The name of the LLM model to be used. This argument is optional, with the default being `meta/llama-3_1-8b-instruct`.
- `--url`: The endpoint URL to which the request will be sent. This argument is required.
- `--token`: The API key or token for authentication with the endpoint. This argument is required.

### Running the Script
To run the script, use the following command:

```bash
python test_function_calling.py --model <model-name> --url <url> --token <api-token>
```

Replace `<model-name>` with the desired model (e.g., `meta/llama-3_1-8b-instruct`), `<url>` with the endpoint URL, and `<api-token>` with the appropriate API key or token for authentication.

### Example
```bash
python test_function_calling.py --model meta/llama-3_1-8b-instruct --url https://api.example.com/endpoint --token your_api_token
```

Initial Response:
```json 
{
    "role": "assistant",
    "content": null,
    "tool_calls": [
        {
            "id": "chatcmpl-tool-0b14ee05ded4431d9c4b3c4b296eb44f",
            "type": "function",
            "function": {
                "name": "get_current_weather",
                "arguments": "{\"location\": \"San Francisco, CA\", \"format\": \"celsius\"}"
            }
        }
    ]
}
```
Follow up response:

```json
{
    "role": "assistant",
    "content": "The current weather in San Francisco, CA is 68 degrees Fahrenheit."
}
```
