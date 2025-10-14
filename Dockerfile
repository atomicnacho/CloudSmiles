# Dockerfile
FROM python:3.10-slim

# Needed by TensorFlow (OpenMP) and pyheif (libheif). Debian 12/13 may call it libheif1 or libheif1t64.
RUN apt-get update && \
    (apt-get install -y --no-install-recommends libgomp1 libheif1 \
     || apt-get install -y --no-install-recommends libgomp1 libheif1t64) \
    && rm -rf /var/lib/apt/lists/*

# Keep TF/NumPy single-threaded on small instances
ENV OMP_NUM_THREADS=1 \
    TF_NUM_INTRAOP_THREADS=1 \
    TF_NUM_INTEROP_THREADS=1 \
    TF_CPP_MIN_LOG_LEVEL=2 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt .

# Install Python deps, then guarantee HEADLESS OpenCV owns cv2
RUN pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt \
 && pip uninstall -y opencv-python || true \
 && pip install --no-cache-dir --upgrade --force-reinstall opencv-python-headless==4.10.0.84

# Optional: fail the build early if imports would crash at runtime
# RUN python - <<'PY'
# import pyheif; import cv2, importlib
# print("pyheif OK, cv2", cv2.__version__)
# importlib.import_module("DECIMER")
# print("DECIMER import OK")
# PY

COPY . .
ENV PORT=8080
CMD ["uvicorn","main:app","--host","0.0.0.0","--port","8080"]
