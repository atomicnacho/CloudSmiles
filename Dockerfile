# ---------- base ----------
FROM python:3.10-slim

# System libs needed by OpenCV + HEIF
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libglib2.0-0 \
    libgl1 \
    libxext6 \
    libxrender1 \
    libsm6 \
    libheif1 \
    libde265-0 \
 && rm -rf /var/lib/apt/lists/*

# Performance/verbosity knobs
ENV OMP_NUM_THREADS=1 \
    TF_NUM_INTRAOP_THREADS=1 \
    TF_NUM_INTEROP_THREADS=1 \
    TF_CPP_MIN_LOG_LEVEL=2 \
    PYTHONUNBUFFERED=1

# Caches so DECIMER keeps models in a writable layer
ENV PYSTOW_HOME=/models \
    HF_HOME=/models \
    TRANSFORMERS_CACHE=/models \
    XDG_CACHE_HOME=/models

WORKDIR /app

# ---------- deps ----------
COPY requirements.txt .
RUN pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt

# ---------- app ----------
COPY . /app

# Cloud Run uses $PORT
ENV PORT=8080

# Start the API
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
