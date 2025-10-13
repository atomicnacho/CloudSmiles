# main.py
import base64, os, re, tempfile, threading
from typing import Optional
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

APP_NAME = "OCSR (DECIMER) API"
APP_VERSION = "1.0.1"

app = FastAPI(title=APP_NAME, version=APP_VERSION)

# Simple CORS (adjust if you need tighter origins)
ALLOWED_ORIGINS = os.getenv("CORS_ORIGINS", "*")
try:
    from fastapi.middleware.cors import CORSMiddleware
    CORS_LIST = [o.strip() for o in ALLOWED_ORIGINS.split(",") if o.strip()]
    app.add_middleware(
        CORSMiddleware,
        allow_origins=CORS_LIST or ["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )
except Exception:
    pass

DATA_URL_RE = re.compile(r"^data:image/(png|jpeg|jpg);base64,([A-Za-z0-9+/=]+)$")

class OcsrBody(BaseModel):
    imageDataUrl: str
    handDrawn: Optional[bool] = True

# Lazy DECIMER loading
_decimer = None
_decimer_err = None
_loading = False

def _ensure_decimer():
    """Import DECIMER when needed (don’t block startup)."""
    global _decimer, _decimer_err
    if _decimer is not None or _decimer_err is not None:
        return
    try:
        import importlib
        try:
            _decimer = importlib.import_module("DECIMER")  # uppercase package
        except Exception as e1:
            # fallback to lowercase import name
            try:
                _decimer = importlib.import_module("decimer")
            except Exception as e2:
                _decimer_err = f"{e1} | {e2}"
    except Exception as e:
        _decimer_err = str(e)

def _warmup_blocking():
    global _loading
    if _loading or _decimer is not None:
        return
    _loading = True
    try:
        _ensure_decimer()
    finally:
        _loading = False

def data_url_to_file(data_url: str) -> str:
    m = DATA_URL_RE.match(data_url)
    if not m:
        raise ValueError("Invalid image data URL (expected data:image/(png|jpeg|jpg);base64,...)")
    ext = "png" if m.group(1) == "png" else "jpg"
    raw = base64.b64decode(m.group(2))
    fd, path = tempfile.mkstemp(suffix=f".{ext}")
    with os.fdopen(fd, "wb") as f:
        f.write(raw)
    return path

@app.get("/")
def root():
    return {"ok": True, "message": "CloudSmiles up", "version": APP_VERSION}

@app.get("/api/health")
def health():
    status = "ready" if _decimer is not None else ("loading" if _loading else "idle")
    return {
        "ok": True,
        "engine": "DECIMER",
        "version": APP_VERSION,
        "status": status,
        "decimer_ok": _decimer is not None,
        "decimer_error": _decimer_err,
    }

@app.post("/api/warmup")
def warmup():
    """Kick off DECIMER import in the background so startup is instant."""
    if _decimer is not None:
        return {"ok": True, "status": "ready"}
    if not _loading:
        threading.Thread(target=_warmup_blocking, daemon=True).start()
    return {"ok": True, "status": "loading"}

@app.post("/api/ocsr")
def ocsr(body: OcsrBody):
    # Ensure DECIMER is available
    if _decimer is None and _decimer_err is None:
        _ensure_decimer()
    if _decimer is None:
        raise HTTPException(status_code=503, detail=f"DECIMER not ready: {_decimer_err or 'warming up'}")

    predict_SMILES = getattr(_decimer, "predict_SMILES", None)
    if not callable(predict_SMILES):
        raise HTTPException(status_code=500, detail="DECIMER missing predict_SMILES()")

    try:
        image_path = data_url_to_file(body.imageDataUrl)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Bad image: {e}")

    try:
        smiles = predict_SMILES(image_path, hand_drawn=bool(body.handDrawn))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"DECIMER error: {e}")
    finally:
        try:
            os.remove(image_path)
        except:
            pass

    return {"smiles": smiles or ""}

