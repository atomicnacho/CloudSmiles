FROM python:3.10-slim

# System deps
# ...keep your FROM, apt-get, ENV, WORKDIR, COPY requirements.txt as-is...

RUN python -m pip install --upgrade pip \
 && python -m pip install --no-cache-dir \
      fastapi==0.112.2 \
      uvicorn[standard]==0.30.6 \
      pydantic==2.8.2 \
      httpx==0.27.2 \
      numpy==1.23.5 \
      Pillow==10.4.0 \
      opencv-python-headless==4.10.0.84 \
      pyheif==0.8.0 \
 && python -m pip install --no-cache-dir tensorflow==2.10.1 \
 && python -m pip install --no-cache-dir DECIMER==2.2.1 --no-deps


# Runtime/env
ENV OMP_NUM_THREADS=1 \
    TF_NUM_INTRAOP_THREADS=1 \
    TF_NUM_INTEROP_THREADS=1 \
    TF_CPP_MIN_LOG_LEVEL=2 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Python deps
COPY requirements.txt .
RUN pip install --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt \
 && pip uninstall -y opencv-python || true \
 && pip install --no-cache-dir opencv-python-headless==4.10.0.84

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libheif1 libde265-0 \
    libgl1 libglib2.0-0 \
 && rm -rf /var/lib/apt/lists/*

# ✅ Copy your application code (this was missing)
COPY . .

# after COPY . .
RUN echo "Contents of /app during build:" && ls -la /app

# Cloud Run port
ENV PORT=8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "1"]

