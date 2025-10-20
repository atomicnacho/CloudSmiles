# ---- Base image ----
FROM python:3.10-slim

# System libs needed by TensorFlow + headless OpenCV + HEIF
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libglib2.0-0 \
    libsm6 \
    libxrender1 \
    libxext6 \
    libgl1 \
    libheif1 \
    libde265-0 \
  && rm -rf /var/lib/apt/lists/*

# Runtime/env tuning
ENV OMP_NUM_THREADS=1 \
    TF_NUM_INTRAOP_THREADS=1 \
    TF_NUM_INTEROP_THREADS=1 \
    TF_CPP_MIN_LOG_LEVEL=2 \
    PYTHONUNBUFFERED=1

# Put all caches where they’ll be baked into the image layer
ENV PYSTOW_HOME=/models \
    HF_HOME=/models \
    TRANSFORMERS_CACHE=/models \
    XDG_CACHE_HOME=/models

WORKDIR /app

# Python deps
COPY requirements.txt .
RUN pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt \
 # keep headless OpenCV only
 && pip uninstall -y opencv-python || true \
 && pip install --no-cache-dir opencv-python-headless==4.10.0.84

# --- Prewarm: copy and run a small python script to download DECIMER weights ---
COPY prewarm.py /tmp/prewarm.py
RUN python /tmp/prewarm.py

# App code last, for faster rebuilds
COPY . .

# Cloud Run will pass $PORT
ENV PORT=8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
