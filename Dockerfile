# Dockerfile
FROM python:3.10-slim

# TF uses OpenMP; we need libgomp. Headless OpenCV needs no extra GUI libs.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
  && rm -rf /var/lib/apt/lists/*

# Keep TF/NumPy single-threaded on small instances
ENV OMP_NUM_THREADS=1 \
    TF_NUM_INTRAOP_THREADS=1 \
    TF_NUM_INTEROP_THREADS=1 \
    TF_CPP_MIN_LOG_LEVEL=2 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt .

# Install deps; then ensure we end with HEADLESS OpenCV files on disk.
RUN pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt \
 && pip uninstall -y opencv-python || true \
 && pip install --no-cache-dir --upgrade --force-reinstall opencv-python-headless==4.10.0.84

# (Optional sanity check; uncomment if you want to fail builds early)
# RUN python - <<'PY'
# import cv2, importlib
# print("cv2:", cv2.__version__)
# importlib.import_module("DECIMER")
# print("DECIMER import OK")
# PY

COPY . .
ENV PORT=8080
CMD ["uvicorn","main:app","--host","0.0.0.0","--port","8080"]
