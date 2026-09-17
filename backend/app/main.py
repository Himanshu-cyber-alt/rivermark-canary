import os

from fastapi import FastAPI, HTTPException

app = FastAPI()

VERSION = os.getenv("APP_VERSION", "unknown")
FAIL_HEALTH = os.getenv("FAIL_HEALTH", "false").lower() == "true"
DEGRADE_AFTER = int(os.getenv("DEGRADE_AFTER", "0"))

request_count = 0


@app.get("/")
def root():
    global request_count

    request_count += 1

    return {
        "application": "Rivermark Backend",
        "version": VERSION,
        "request_count": request_count,
        "message": f"Hello from {VERSION}",
    }


@app.get("/version")
def version():
    return {
        "version": VERSION
    }


@app.get("/health")
def health():
    if FAIL_HEALTH:
        raise HTTPException(
            status_code=500,
            detail="Canary health check failed"
        )

    if DEGRADE_AFTER > 0 and request_count >= DEGRADE_AFTER:
        raise HTTPException(
            status_code=500,
            detail="Backend degraded"
        )

    return {
        "status": "healthy",
        "version": VERSION
    }