# ---- base
FROM python:3.10-slim

# System libs for TF (CPU), OpenCV-headless, and HEIF decoding
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 \
    libheif1 libde265-0 \
 && rm -rf /var/lib/apt/lists/*

# Keep TF on CPU and reduce noise
ENV OMP_NUM_THREADS=1 \
    TF_NUM_INTRAOP_THREADS=1 \
    TF_NUM_INTEROP_THREADS=1 \
    TF_CPP_MIN_LOG_LEVEL=2 \
    TF_FORCE_CPU=1 \
    CUDA_VISIBLE_DEVICES="" \
    PYTHONUNBUFFERED=1 \
    PORT=8080

WORKDIR /app
COPY requirements.txt .

# Install Python deps
RUN pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt

# Sanity: fail the build if imports are missing
RUN python -c "import sys, importlib; mods=['cv2','decimer','pyheif']; \
missing=[m for m in mods if importlib.util.find_spec(m) is None]; \
print('Python:', sys.version); \
assert not missing, f'Missing modules: {missing}'; \
print('Sanity import check PASSED')"

# Copy app source last
COPY . .

# Final startup: verify imports again, then run the API
CMD ["sh","-lc","python - <<'PY'\nimport importlib\nfor m in ['cv2','decimer','pyheif']:\n    importlib.import_module(m)\nprint('startup imports OK')\nPY\nexec uvicorn main:app --host 0.0.0.0 --port ${PORT}"]
