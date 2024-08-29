#!/bin/bash

if [[ -z $LHOST ]]; then
  echo "please provide an LHOST env var"
  exit 1
fi

Q="Write a song about pizza"

curl "http://${LHOST}/v1/chat/completions" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
    {
        "content": "'"${Q}"'",
        "role": "user"
    }
   ],
   "model": "meta/llama3-8b-instruct",
   "max_tokens": 500,
   "top_p": 0.8,
   "temperature": 0.9,
   "seed": '$RANDOM',
   "stream": false,
   "stop": ["hello\n"],
   "frequency_penalty": 1.0
}' | jq -r '.choices[0]|.message.content'
