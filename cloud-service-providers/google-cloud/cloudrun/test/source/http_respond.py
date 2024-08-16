from fastapi import FastAPI
from fastapi.responses import PlainTextResponse

app = FastAPI()

@app.get("/v1/health/ready", status_code = 200)
async def health():
    return {"message": "200 OK; READY"}

@app.get("/output", response_class=PlainTextResponse)
async def output(response: PlainTextResponse):
    with open("test_output") as f:
        return f.read()

