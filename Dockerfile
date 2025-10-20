# ---- Base image ----
FROM python:3.10-slim

# System libs required by TensorFlow + headless OpenCV + HEIF
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

# Cache to a fixed layer so repeated cold starts don’t re-download
ENV PYSTOW_HOME=/models \
    HF_HOME=/models \
    TRANSFORMERS_CACHE=/models \
    XDG_CACHE_HOME=/models

WORKDIR /app

# ---- Python deps ----
COPY requirements.txt ./

# Install deps; keep headless OpenCV; do NOT run any Python that imports decimer here
RUN python -m pip install --upgrade pip \
 && python -m pip install --no-cache-dir -r requirements.txt \
 && python -m pip uninstall -y opencv-python || true \
 && python -m pip install --no-cache-dir opencv-python-headless==4.10.0.84

# ---- App code (last for faster rebuilds) ----
COPY . .

# Cloud Run will pass $PORT
ENV PORT=8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
