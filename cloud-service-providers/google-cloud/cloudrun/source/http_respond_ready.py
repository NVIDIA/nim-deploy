from fastapi import FastAPI
from fastapi.responses import RedirectResponse

app = FastAPI()

@app.get("/v1/health/ready", status_code = 200)
async def health():
    return {"message": "200 OK; READY"}
