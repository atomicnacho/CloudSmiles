# main.py
import base64, os, re, tempfile, threading, sys, types, importlib, importlib.util, time
from typing import Optional
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from fastapi import FastAPI, HTTPException, Query

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

# --- BEGIN: pyheif shim (we only use PNG/JPG; avoid native HEIF dep) ---
try:
    if importlib.util.find_spec("pyheif") is None:
        _pyheif_stub = types.ModuleType("pyheif")
        def _no_heif(*args, **kwargs):
            raise ImportError("HEIF/HEIC not supported in this build")
        _pyheif_stub.read = _no_heif
        sys.modules["pyheif"] = _pyheif_stub
except Exception:
    # If anything goes wrong, we still proceed; DECIMER will import if it can.
    pass
# --- END: pyheif shim ---

# Lazy DECIMER loading state
_decimer = None
_decimer_err = None
_loading = False
_status = "idle"

def _ensure_decimer():
    """Try importing DECIMER (uppercase first), then lowercase as fallback."""
    global _decimer, _decimer_err, _status
    if _decimer is not None or _decimer_err is not None:
        return
    _status = "loading"
    try:
        _decimer = importlib.import_module("DECIMER")  # try uppercase first
        _status = "ready"
    except Exception as e1:
        try:
            _decimer = importlib.import_module("decimer")  # fallback
            _status = "ready"
        except Exception as e2:
            _decimer_err = f"{e1} | {e2}"
            _status = "error"

WARMUP_TIMEOUT_S = 600  # choose a sensible cap for your setup
_warmup_started_at = None

def _warmup_blocking():
    global _status, _loading, _decimer, _decimer_err, _warmup_started_at
    try:
        _status = "loading"; _loading = True; _warmup_started_at = time.time()
        print("[warmup] starting...")
        import cv2; print("[warmup] cv2 ok")
        import decimer as _d; print("[warmup] decimer import ok")
        model = _d.load_model(); print("[warmup] decimer model loaded")
        _decimer = model; _decimer_err = None
        _status = "ready"; print("[warmup] ready")
    except Exception as e:
        _decimer_err = f"{e.__class__.__name__}: {e}"
        _status = "error"; print("[warmup] error:", _decimer_err)
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
def health(warmup: bool = Query(False)):
    # timeout guard
    if _status == "loading" and _warmup_started_at and time.time() - _warmup_started_at > WARMUP_TIMEOUT_S:
        return {"ok": True, "engine":"DECIMER","version":APP_VERSION,"status":"error",
                "decimer_ok": False, "decimer_error": f"warmup exceeded {WARMUP_TIMEOUT_S}s"}
    return {"ok": True, "engine":"DECIMER","version":APP_VERSION,"status": _status,
            "decimer_ok": _decimer is not None, "decimer_error": _decimer_err}

@app.post("/api/warmup")
def warmup():
    """Manual warmup endpoint (optional)."""
    if _decimer is not None:
        return {"ok": True, "status": "ready"}
    if not _loading:
        threading.Thread(target=_warmup_blocking, daemon=True).start()
    return {"ok": True, "status": "loading"}

@app.get("/api/health")
def health(warmup: bool = Query(False)):
    if warmup and _decimer is None and not _loading and _decimer_err is None:
        threading.Thread(target=_warmup_blocking, daemon=True).start()
        # status will be "loading" immediately
    return {
        "ok": True,
        "engine": "DECIMER",
        "version": APP_VERSION,
        "status": _status,
        "decimer_ok": _decimer is not None,
        "decimer_error": _decimer_err,
    }

@app.post("/api/ocsr")
def ocsr(body: OcsrBody):
    # Ensure DECIMER is available (non-blocking if warmup already ran)
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
        except Exception:
            pass

    return {"smiles": smiles or ""}
