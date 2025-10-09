# Dockerfile (cloudrun)
FROM python:3.11-slim

# System deps for OpenCV/DECIMER (libGL) and basic runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Helpful for libraries that use HuggingFace caches
ENV HF_HOME=/models \
    TRANSFORMERS_CACHE=/models \
    XDG_CACHE_HOME=/models

WORKDIR /app

# Copy and install Python deps first for better Docker layer caching
COPY requirements.txt .
# Tip: pin versions here; include: fastapi, uvicorn, httpx (if you want proxy), and decimer/DECIMER + deps
RUN pip install --no-cache-dir -r requirements.txt

# Now copy your app
COPY . .

# Uvicorn port provided by Cloud Run as $PORT
ENV HOST=0.0.0.0
ENV PORT=8080

# If your app file is main.py and app is "app", this is correct:
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
