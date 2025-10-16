# ---- base
FROM python:3.10-slim

# System libs for TF (CPU), OpenCV-headless and HEIF decoding
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 \
    libheif1 libde265-0 \
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

# Bust cache whenever you need to force a clean reinstall
ARG DEPS_VERSION=1

# Install everything in one go so we don't end up with mismatched environments
RUN pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt \
 && python - <<'PY'
import sys, pkgutil
print("Python:", sys.version)
# Verify imports NOW; fail build if missing.
for mod in ("cv2", "decimer", "pyheif"):
    m = pkgutil.find_loader(mod)
    assert m is not None, f"FATAL: {mod} not importable during build"
print("Sanity import check PASSED")
PY

# Copy app code last
COPY . .

# Optional: import check again at container start, before uvicorn
# If imports fail here, the container will exit and Cloud Run will surface logs immediately.
CMD bash -lc '\
python - <<PY || exit 1
import importlib
for m in ["cv2","decimer","pyheif"]:
    try:
        mod = importlib.import_module(m)
        print(f"startup-import {m} OK:", getattr(mod,"__version__", "n/a"))
    except Exception as e:
        print("startup-import FAILED:", m, e); raise
PY
exec uvicorn main:app --host 0.0.0.0 --port ${PORT:-8080}'
