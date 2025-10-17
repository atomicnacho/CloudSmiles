FROM python:3.10-slim

# System libs: OpenMP for TF; HEIF for pyheif; OpenGL for OpenCV
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libheif1 \
    libde265-0 \
    libgl1 \
 && rm -rf /var/lib/apt/lists/*

ENV OMP_NUM_THREADS=1 \
    TF_NUM_INTRAOP_THREADS=1 \
    TF_NUM_INTEROP_THREADS=1 \
    TF_CPP_MIN_LOG_LEVEL=2 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8080

WORKDIR /app

COPY requirements.txt .
RUN python -m pip install --upgrade pip \
 && python -m pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8080
CMD ["uvicorn","main:app","--host","0.0.0.0","--port","8080"]
