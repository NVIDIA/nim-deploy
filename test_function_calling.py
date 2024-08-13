import requests
import json

# Define the endpoint and headers
url = "<endpoint-url>"
headers = {
    'Authorization': 'Bearer <token>',
    # 'azureml-model-deployment': 'llama31-8b--deployment-aml-1', (required only when deployed on AzureML)
    'accept': 'application/json',
    'Content-Type': 'application/json'
}

# Define the initial messages
messages = [
    {"role": "user", "content": "Hello! How are you?"},
    {"role": "assistant", "content": "Hi! I am quite well, how can I help you today?"},
    {"role": "user", "content": "Can you get me weather for San Francisco, CA?"}
]

# Define function
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

def make_request(messages, tools=None, tool_choice=None):
    data = {
        "model": "meta/llama-3_1-8b-instruct",
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
    
    response = requests.post(url, headers=headers, data=json.dumps(data))
    return response.json()

def handle_function_call(response_json):
    if 'choices' in response_json:
        assistant_message = response_json['choices'][0]['message']
        messages.append(assistant_message)
        for tool_call in assistant_message['tool_calls']:
            assert tool_call["type"] == "function"
            if tool_call["function"]['name'] == 'get_current_weather':
                arguments =  json.loads(tool_call["function"]["arguments"])
                # Actual function call to get weather
                tool_call_result = get_weather(arguments["location"], arguments["format"])
                
                # Append the function result to the messages
                messages.append({
                    "role": "tool",
                    "content": json.dumps(tool_call_result),
                    "tool_call_id": tool_call['id']
                })
                # Make a follow-up request with the function call result
                return make_request(messages, tools=[weather_tool], tool_choice="auto")
    return response_json

# Make the initial request
initial_response_json = make_request(messages, tools=[weather_tool], tool_choice="auto")

print("Initial Response", json.dumps(initial_response_json, indent=4))

# Handle the function call and make follow-up request if needed
follow_up_response_json = handle_function_call(initial_response_json)

# Print the follow-up response
print("Follow up Response", json.dumps(follow_up_response_json, indent=4))

