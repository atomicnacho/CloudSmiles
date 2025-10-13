# Python 3.10 is required because DECIMER 2.2.1 pins TensorFlow 2.10.x
FROM python:3.10-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_HOME=/models \
    TRANSFORMERS_CACHE=/models \
    XDG_CACHE_HOME=/models \
    TF_CPP_MIN_LOG_LEVEL=2

WORKDIR /app

# Minimal native deps. Use headless OpenCV so no libGL needed.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
 && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --upgrade pip && pip install --no-cache-dir -r requirements.txt

COPY . .

# Cloud Run passes $PORT; default to 8080 for local
CMD ["sh","-c","uvicorn main:app --host 0.0.0.0 --port ${PORT:-8080}"]
