# ---- Base image -------------------------------------------------------------
FROM python:3.10-slim

# ---- OS packages needed by TensorFlow/DECIMER/OpenCV/HEIF -------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libheif1 \
    libde265-0 \
 && rm -rf /var/lib/apt/lists/*

# ---- Runtime env tweaks -----------------------------------------------------
ENV OMP_NUM_THREADS=1 \
    TF_NUM_INTRAOP_THREADS=1 \
    TF_NUM_INTEROP_THREADS=1 \
    TF_CPP_MIN_LOG_LEVEL=2 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8080

# ---- Workdir ----------------------------------------------------------------
WORKDIR /app

# ---- Python deps first (better layer caching) -------------------------------
COPY requirements.txt ./

RUN python -m pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt \
 # Force headless OpenCV in case a dependency pulled GUI build
 && pip uninstall -y opencv-python || true \
 && pip install --no-cache-dir opencv-python-headless==4.10.0.84

# ---- Sanity check: ensure critical modules resolve at build time ------------
# (No Dockerfile heredocs; write a tiny script then run it)
RUN set -e; \
  printf '%s\n' \
    "import sys, importlib" \
    "mods=['cv2','decimer','pyheif']" \
    "missing=[m for m in mods if importlib.util.find_spec(m) is None]" \
    "print('Python:', sys.version)" \
    "print('Checking modules:', mods)" \
    "print('Missing:', missing)" \
    "sys.exit(1 if missing else 0)" \
    > /tmp/sanity.py; \
  python /tmp/sanity.py; \
  rm -f /tmp/sanity.py

# ---- App code ---------------------------------------------------------------
COPY . /app

# ---- Start server -----------------------------------------------------------
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
