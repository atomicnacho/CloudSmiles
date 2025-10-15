FROM python:3.10-slim

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libheif1 \
    libde265-0 \
    && rm -rf /var/lib/apt/lists/*

# Runtime/env
ENV OMP_NUM_THREADS=1 \
    TF_NUM_INTRAOP_THREADS=1 \
    TF_NUM_INTEROP_THREADS=1 \
    TF_CPP_MIN_LOG_LEVEL=2 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Python deps
COPY requirements.txt .
RUN pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt \
 && pip uninstall -y opencv-python || true \
 && pip install --no-cache-dir opencv-python-headless==4.10.0.84

# ✅ Copy your application code (this was missing)
COPY . .

# Cloud Run port
ENV PORT=8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
