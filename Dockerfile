# Dockerfile
FROM python:3.10-slim

# Small, CPU-only runtime dep TensorFlow uses (OpenMP).
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
  && rm -rf /var/lib/apt/lists/*

# Keep memory/CPU modest for Cloud Run
ENV OMP_NUM_THREADS=1 \
    TF_NUM_INTRAOP_THREADS=1 \
    TF_NUM_INTEROP_THREADS=1 \
    TF_CPP_MIN_LOG_LEVEL=2 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Install Python deps
COPY requirements.txt .
RUN pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt \
    # DECIMER drags in opencv-python; replace with headless to avoid libGL
 && pip uninstall -y opencv-python || true \
 && pip install --no-cache-dir opencv-python-headless==4.10.0.84

# App code
COPY . .

# Cloud Run injects $PORT (defaults to 8080). Bind to it.
# Also keep workers=1 to control memory.
CMD uvicorn main:app --host 0.0.0.0 --port ${PORT:-8080} --workers 1
