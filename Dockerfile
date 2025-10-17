# ---- Base ----
FROM python:3.10-slim

# Minimal OS deps (OpenMP for TF, HEIF runtime for pyheif)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libheif1 \
    libde265-0 \
 && rm -rf /var/lib/apt/lists/*

# Env for stable, low-noise runtime
ENV OMP_NUM_THREADS=1 \
    TF_NUM_INTRAOP_THREADS=1 \
    TF_NUM_INTEROP_THREADS=1 \
    TF_CPP_MIN_LOG_LEVEL=2 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8080

WORKDIR /app

# ---- Python deps ----
COPY requirements.txt ./requirements.txt

# Always use the same interpreter for pip
RUN python -m pip install --upgrade pip \
 && python -m pip install --no-cache-dir -r requirements.txt \
 # DECIMER may pull in opencv-python; replace it with headless to avoid GUI libs
 && python -m pip uninstall -y opencv-python || true \
 && python -m pip install --no-cache-dir opencv-python-headless==4.10.0.84

# Optional: visibility-only check (does NOT fail the build)
RUN python - <<'PY'
import sys, importlib, pprint
print("Python:", sys.version)
print("sys.path:")
pprint.pprint(sys.path)
for m in ("cv2","decimer","pyheif"):
    print(f"{m}:","OK" if importlib.util.find_spec(m) else "NOT FOUND")
PY

# ---- App code ----
COPY . .

EXPOSE 8080

# ---- Entrypoint ----
CMD ["uvicorn","main:app","--host","0.0.0.0","--port","8080"]
