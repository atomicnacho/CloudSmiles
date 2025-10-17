# ---- Base image ----
FROM python:3.10-slim

# OS deps: OpenMP for TF; HEIF libs for pyheif
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libheif1 \
    libde265-0 \
 && rm -rf /var/lib/apt/lists/*

# Runtime env
ENV OMP_NUM_THREADS=1 \
    TF_NUM_INTRAOP_THREADS=1 \
    TF_NUM_INTEROP_THREADS=1 \
    TF_CPP_MIN_LOG_LEVEL=2 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8080

WORKDIR /app

# Install Python deps
COPY requirements.txt ./requirements.txt
RUN python -m pip install --upgrade pip \
 && python -m pip install --no-cache-dir -r requirements.txt \
    # Replace any GUI OpenCV with headless variant to avoid extra libs
 && python -m pip uninstall -y opencv-python || true \
 && python -m pip install --no-cache-dir opencv-python-headless==4.10.0.84

# App code last (keeps layer cache effective for deps)
COPY . .

EXPOSE 8080

CMD ["uvicorn","main:app","--host","0.0.0.0","--port","8080"]
