FROM python:3.10-slim

# --- system deps for OpenCV + HEIF ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libheif1 libde265-0 \
    libgl1 libglib2.0-0 \
    libsm6 libxext6 libxrender1 \
 && rm -rf /var/lib/apt/lists/*

# helpful runtime flags; adjust as you like
ENV OMP_NUM_THREADS=1 \
    TF_NUM_INTRAOP_THREADS=1 \
    TF_NUM_INTEROP_THREADS=1 \
    TF_CPP_MIN_LOG_LEVEL=2 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt .

# install python deps; ensure we end up with *headless* opencv
RUN pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt \
 && pip uninstall -y opencv-python || true \
 && pip install --no-cache-dir opencv-python-headless==4.10.0.84

# (optional) sanity check so builds fail fast if libs are missing
# RUN python - <<'PY'
# import cv2, sys; print("cv2:", cv2.__version__)
# PY

COPY . .

ENV PORT=8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
