from promptflow import tool
from openai import OpenAI

client = OpenAI(
  api_key="<your NGC API key>",
  base_url="https://ai.api.nvidia.com/v1/retrieval/nvidia"
)

@tool
def get_embedding(input_text: str):
    response = client.embeddings.create(
    input=[input_text],
    model="NV-Embed-QA", 
    encoding_format="float",
    extra_body={"input_type": "query", "truncate": "NONE"})

    return response.data[0].embedding

#print(response.data[0].embedding)
# Example usage
# input_text = "What is the capital of France?"
# embeddings = get_embedding(input_text)
# print(embeddings)



    