#! /bin/bash

URL=${CLOUD_RUN_ENDPOINT_URL?}

echo using CLOUD_RUN_ENDPOINT_URL $URL
input=$(mktemp)
output=test_output

cd /home/nemo
uvicorn --host 0.0.0.0 --port  3333 http_respond:app &


while true
do

    for ASK in "write a pome about rocks" "tell me a funny joke" "describe a beautiful place" "write a new happy birthday song" "once upon a time"
    do
    cat <<EOF >$input
    {
      "model": "meta/llama3-8b-instruct",
      "prompt": "${ASK?}",
      "max_tokens": 100,
      "temperature": 1,
      "top_p": 1,
      "n": 1,
      "stream": false,
      "stop": "string",
      "frequency_penalty": 0.0
    }
EOF

    time curl -X POST  "${URL?}/v1/completions"   -H 'accept: application/json' \
          -H 'Content-Type: application/json'   -d "@${input}"  >> $output

    done
done 


