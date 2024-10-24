import requests
import json
import argparse

# Define the function to get weather
def get_weather(location, format):
    # Dummy weather data for predefined cities
    dummy_weather_data = {
        "San Francisco, CA": {"temperature": 68, "unit": "fahrenheit"},
        "Paris, France": {"temperature": 20, "unit": "celsius"}
    }
    
    # Return the weather data if the location is known
    if location in dummy_weather_data:
        return dummy_weather_data[location]
    else:
        return {"error": "Weather data not available for the specified location"}

# Define the function to make a request
def make_request(url, headers, messages, model, tools=None, tool_choice=None):
    data = {
        "model": model,
        "messages": messages,
        "top_p": 1,
        "n": 1,
        "max_tokens": 200,
        "stream": False,
    }
    
    if tools:
        data["tools"] = tools
    if tool_choice:
        data["tool_choice"] = tool_choice
    
    try:
        response = requests.post(url, headers=headers, data=json.dumps(data))
        response.raise_for_status()  # Raises an HTTPError if the HTTP request returned an unsuccessful status code
        return response.json()
    except (requests.exceptions.HTTPError,
            requests.exceptions.ConnectionError,
            requests.exceptions.Timeout,
            requests.exceptions.RequestException,
            json.JSONDecodeError) as err:
        print(f"An error occurred: {err}")
    return None

# Define the function to handle function calls
def handle_function_call(response_json):
    if 'choices' in response_json:
        for tool_call in response_json['choices'][0]['message']['tool_calls']:
            assert tool_call["type"] == "function"
            if tool_call["function"]['name'] == 'get_current_weather':
                arguments = json.loads(tool_call["function"]["arguments"])
                # Actual function call to get weather
                return tool_call['id'], get_weather(arguments["location"], arguments["format"])
    return response_json

# Define the main function to run the test
def run_test(url, token, model="meta/llama-3.1-8b-instruct"):
    headers = {
        'Authorization': f'Bearer {token}',
        # 'azureml-model-deployment': 'llama31-8b--deployment-aml-1', (required only when deployed on AzureML)
        'accept': 'application/json',
        'Content-Type': 'application/json'
    }

    messages = [
        {"role": "user", "content": "Hello! How are you?"},
        {"role": "assistant", "content": "Hi! I am quite well, how can I help you today?"},
        {"role": "user", "content": "Can you get me weather for San Francisco, CA?"}
    ]

    weather_tool = {
        "type": "function",
        "function": {
            "name": "get_current_weather",
            "description": "Get the current weather",
            "parameters": {
                "type": "object",
                "properties": {
                    "location": {
                        "type": "string",
                        "description": "The city and state, e.g. San Francisco, CA"
                    },
                    "format": {
                        "type": "string",
                        "enum": ["celsius", "fahrenheit"],
                        "description": "The temperature unit to use. Infer this from the user's location."
                    }
                },
                "required": ["location", "format"]
            }
        }
    }

    # Make the initial request
    initial_response_json = make_request(url, headers, messages, model, tools=[weather_tool], tool_choice="auto")

    assistant_message = initial_response_json['choices'][0]['message']
    messages.append(assistant_message)

    print("Initial Response", json.dumps(initial_response_json["choices"][0]["message"], indent=4))

    # Handle the function call and make follow-up request if needed
    tool_call_id, tool_call_result = handle_function_call(initial_response_json)

    # Append the function result to the messages
    messages.append({
        "role": "tool",
        "content": json.dumps(tool_call_result),
        "tool_call_id": tool_call_id
    })
    # Make a follow-up request with the function call result
    follow_up_response_json = make_request(url, headers, messages, model, tools=[weather_tool], tool_choice="auto")    

    # Print the follow-up response
    print("Follow up Response", json.dumps(follow_up_response_json["choices"][0]["message"], indent=4))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run LLM function calling test.")
    parser.add_argument("--model", type=str, default="meta/llama-3_1-8b-instruct", help="The model name to use.")
    parser.add_argument("--url", type=str, required=True, help="The endpoint URL to send the request to.")
    parser.add_argument("--token", type=str, required=True, help="API key for the endpoint if any.")

    args = parser.parse_args()

    run_test(args.url, args.token, args.model)
