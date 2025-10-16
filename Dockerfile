FROM python:3.10-slim

# System libs for OpenCV + HEIF (and TF on CPU)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libheif1 libde265-0 \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 \
 && rm -rf /var/lib/apt/lists/*

ENV OMP_NUM_THREADS=1 \
    TF_NUM_INTRAOP_THREADS=1 \
    TF_NUM_INTEROP_THREADS=1 \
    TF_CPP_MIN_LOG_LEVEL=2 \
    TF_FORCE_CPU=1 \
    CUDA_VISIBLE_DEVICES="" \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt .

# Install base deps first
RUN pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt

# Install DECIMER after base deps (this may bring opencv-python)
RUN pip install --no-cache-dir DECIMER==2.2.1

# Force headless OpenCV in final image
RUN pip uninstall -y opencv-python || true \
 && pip install --no-cache-dir opencv-python-headless==4.10.0.84

# Sanity-check imports so build fails early if broken
RUN python - <<'PY'
import sys, pkgutil
print("Python:", sys.version)
# cv2
import cv2
print("cv2 OK:", cv2.__version__, cv2.__file__)
# decimer
assert pkgutil.find_loader("decimer"), "decimer not found"
import decimer
print("DECIMER OK:", getattr(decimer, "__version__", "unknown"))
# pyheif
import pyheif
print("pyheif OK")
PY

COPY . .

ENV PORT=8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
