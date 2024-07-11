import requests
import json
from promptflow import tool


ENDPOINT_URL = "https://integrate.api.nvidia.com"
CHAT_COMPLETIONS_URL_EXTN = "/v1/chat/completions"
MODEL = "mistralai/mixtral-8x7b-instruct-v0.1"
url = ENDPOINT_URL + CHAT_COMPLETIONS_URL_EXTN
api_key = "<your api key>"
headers = {'Content-Type': 'application/json', 'Authorization': ('Bearer ' + api_key)}

@tool
def my_python_tool(question: str, prompt_text: str) -> str:
    body = {
        "model": MODEL,
        "messages": [
            {
                "role": "assistant",
                "content": prompt_text
            },
            {
                "role": "user",
                "content": f"{question} Please be brief, use my name in the response, reference previous purchases, and add emojis for personalization and flair."
            }
        ],
        "max_tokens": 1024,
        "stream": False,
    }
    
    try:
        response = requests.post(url=url, json=body, headers=headers)
        response.raise_for_status()  # Raise an HTTPError for bad responses (4xx and 5xx)
        response_json = response.json()
        
        if 'choices' in response_json:
            return response_json['choices'][0]['message']['content']
        else:
            raise KeyError("'choices' key not found in the response")
    
    except requests.exceptions.RequestException as e:
        return f"Request failed: {e}"
    except KeyError as e:
        return f"Key error: {e}"
    except Exception as e:
        return f"An unexpected error occurred: {e}"