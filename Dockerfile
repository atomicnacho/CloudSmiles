# ---- Base image ----
FROM python:3.10-slim

# System deps for TF/OpenCV headless & HEIF
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libglib2.0-0 \
    libsm6 \
    libxrender1 \
    libxext6 \
    libheif1 \
    libde265-0 \
  && rm -rf /var/lib/apt/lists/*

# Performance / logging defaults
ENV OMP_NUM_THREADS=1 \
    TF_NUM_INTRAOP_THREADS=1 \
    TF_NUM_INTEROP_THREADS=1 \
    TF_CPP_MIN_LOG_LEVEL=2 \
    PYTHONUNBUFFERED=1

# Put all on-disk model caches in /models so they’re included in the image layer
ENV PYSTOW_HOME=/models \
    HF_HOME=/models \
    TRANSFORMERS_CACHE=/models \
    XDG_CACHE_HOME=/models

WORKDIR /app

# Python deps
COPY requirements.txt .
RUN pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt \
 # Ensure we only keep headless OpenCV
 && pip uninstall -y opencv-python || true \
 && pip install --no-cache-dir opencv-python-headless==4.10.0.84

# --- Pre-warm DECIMER at build time (this is the key bit) ---
# This downloads/caches the DECIMER weights into /models so runtime warmup is instant.
RUN python - <<'PY'
import os, sys, pathlib
os.environ['PYSTOW_HOME'] = os.environ.get('PYSTOW_HOME','/models')
print('[prewarm] PYSTOW_HOME =', os.environ['PYSTOW_HOME'])
# Try both module names; different wheels expose either.
mod = None
try:
    import DECIMER as mod
    print('[prewarm] imported DECIMER')
except Exception as e1:
    print('[prewarm] DECIMER import failed:', e1)
    try:
        import decimer as mod
        print('[prewarm] imported decimer')
    except Exception as e2:
        print('[prewarm] decimer import failed:', e2)
        raise SystemExit('Failed to import DECIMER/decimer during build')

# Some builds lazily fetch weights on first call.
# We call the public API to force weight download.
img = pathlib.Path('/tmp/blank.png')
# Create a tiny blank PNG
from PIL import Image
Image.new('RGB',(16,16),(255,255,255)).save(img)

# Find a callable to trigger model materialization
predict = getattr(mod, 'predict_SMILES', None)
if callable(predict):
    try:
        print('[prewarm] calling predict_SMILES(...) to trigger weight download')
        _ = predict(str(img))  # we ignore result; it’s blank anyway
    except Exception as e:
        print('[prewarm] predict_SMILES raised (expected for blank image):', e)
else:
    loader = getattr(mod, 'load_model', None)
    if callable(loader):
        print('[prewarm] calling load_model() to trigger weight download')
        _ = loader()
    else:
        raise SystemExit('DECIMER imported but no usable entry point found')

print('[prewarm] done')
PY

# App code last (keeps code iteration fast)
COPY . .

# Health: Cloud Run expects your server on $PORT
ENV PORT=8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
