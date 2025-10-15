# ---- base that works with TF 2.10 wheels ----
FROM python:3.10-slim-bullseye

# Small runtime dep TF/OpenCV need on CPU
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
  && rm -rf /var/lib/apt/lists/*

# Keep things quiet/fast and CPU-friendly
ENV OMP_NUM_THREADS=1 \
    TF_NUM_INTRAOP_THREADS=1 \
    TF_NUM_INTEROP_THREADS=1 \
    TF_CPP_MIN_LOG_LEVEL=2 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

WORKDIR /app
COPY requirements.txt .

# 1) install your deps
# 2) DECIMER may pull opencv-python -> remove it
# 3) install opencv headless explicitly
# 4) remove pyheif to avoid the cffi/“handle” crash
RUN pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt \
 && pip uninstall -y opencv-python || true \
 && pip install --no-cache-dir opencv-python-headless==4.10.0.84 \
 && pip uninstall -y pyheif || true

COPY . .

# Cloud Run will inject PORT=8080
CMD exec uvicorn main:app --host 0.0.0.0 --port ${PORT:-8080}
