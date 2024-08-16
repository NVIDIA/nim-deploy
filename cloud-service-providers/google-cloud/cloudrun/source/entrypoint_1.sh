#! /bin/bash

echo Starting NIM in standby mode
cd /home/nemo
uvicorn --host 0.0.0.0 --port  3333 http_respond_ready:app &

echo Starting NIM
/opt/nim/start-server.sh 




