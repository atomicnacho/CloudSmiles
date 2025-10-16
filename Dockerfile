FROM python:3.10-slim

# --- system deps for OpenCV + HEIF ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libheif1 libde265-0 \
    libgl1 libglib2.0-0 \
    libsm6 libxext6 libxrender1 \
 && rm -rf /var/lib/apt/lists/*

ENV OMP_NUM_THREADS=1 \
    TF_NUM_INTRAOP_THREADS=1 \
    TF_NUM_INTEROP_THREADS=1 \
    TF_CPP_MIN_LOG_LEVEL=2 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt .

# 1) install base deps
# 2) install DECIMER (this may pull opencv-python)
# 3) forcibly replace OpenCV with headless variant
RUN pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt \
 && pip install --no-cache-dir DECIMER==2.2.1 \
 && pip uninstall -y opencv-python || true \
 && pip install --no-cache-dir opencv-python-headless==4.10.0.84 \
 # --- sanity checks: fail build early if imports break ---
 && python - <<'PY'
import cv2, importlib, pkgutil
print("cv2 OK:", cv2.__version__, cv2.__file__)
assert pkgutil.find_loader("decimer") is not None, "decimer not found"
print("decimer OK")
import pyheif
print("pyheif OK")
PY

COPY . .

ENV PORT=8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
