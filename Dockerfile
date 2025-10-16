# ---- Base image -------------------------------------------------------------
FROM python:3.10-slim

# ---- OS packages needed by TensorFlow/DECIMER/OpenCV/HEIF -------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libheif1 \
    libde265-0 \
    && rm -rf /var/lib/apt/lists/*

# ---- Runtime env tweaks (quiet TF, fewer threads, unbuffered logs) ----------
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

# Use a modern pip, then install deps
RUN python -m pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt

# Force headless OpenCV in case any dependency (e.g. DECIMER) pulled in non-headless
RUN pip uninstall -y opencv-python || true \
 && pip install --no-cache-dir opencv-python-headless==4.10.0.84

# ---- Sanity check: ensure critical modules resolve at build time ------------
# (Using heredoc prevents Dockerfile from seeing any "import" token as an instruction)
RUN python - <<'PY'
import sys, importlib
mods = ['cv2','decimer','pyheif']
missing = [m for m in mods if importlib.util.find_spec(m) is None]
print('Python:', sys.version)
print('Checking modules:', mods)
if missing:
    raise SystemExit(f'ERROR: Missing modules at build time: {missing}')
print('Sanity import check PASSED')
PY

# ---- App code ---------------------------------------------------------------
# Copy the rest of your service (main.py, routers, etc.)
COPY . /app

# ---- Start server -----------------------------------------------------------
# Cloud Run injects $PORT; Uvicorn will bind to it.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
