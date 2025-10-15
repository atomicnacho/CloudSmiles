# Dockerfile
FROM python:3.10-slim

# System deps: OpenMP for TF + HEIF runtime for pyheif
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libheif1 \
    libde265-0 \
    && rm -rf /var/lib/apt/lists/*

# Keep TF small/quiet and limit threads a bit
ENV OMP_NUM_THREADS=1 \
    TF_NUM_INTRAOP_THREADS=1 \
    TF_NUM_INTEROP_THREADS=1 \
    TF_CPP_MIN_LOG_LEVEL=2 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt .

# Install Python deps, then enforce headless OpenCV
RUN pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt \
 && pip uninstall -y opencv-python || true \
 && pip install --no-cache-dir opencv-python-headless==4.10.0.84

# If your app code is copied in a separate step, include it:
# COPY . .

# Cloud Run uses PORT=8080
ENV PORT=8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
