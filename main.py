# main.py
import base64, os, re, tempfile, threading, sys, types, importlib, importlib.util, time
from typing import Optional, Callable
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel

APP_NAME = "OCSR (DECIMER) API"
APP_VERSION = "1.0.1"

app = FastAPI(title=APP_NAME, version=APP_VERSION)

# CORS (adjust origins as needed)
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

# --- BEGIN: pyheif shim (we only support PNG/JPG; avoid native HEIF dep) ---
try:
    if importlib.util.find_spec("pyheif") is None:
        _pyheif_stub = types.ModuleType("pyheif")
        def _no_heif(*args, **kwargs):
            raise ImportError("HEIF/HEIC not supported in this build")
        _pyheif_stub.read = _no_heif
        sys.modules["pyheif"] = _pyheif_stub
except Exception:
    pass
# --- END: pyheif shim ---

# Lazy DECIMER state
_decimer_predict: Optional[Callable] = None   # a callable(image_path, hand_drawn=bool) -> str
_decimer_err: Optional[str] = None
_loading = False
_status = "idle"

# Warmup timing / timeout
WARMUP_TIMEOUT_S = int(os.getenv("WARMUP_TIMEOUT_S", "900"))  # 15 min cap by default (TF + model can be heavy)
_warmup_started_at: Optional[float] = None

def _resolve_decimer_callable() -> Callable:
    """
    Import DECIMER (try 'DECIMER' then 'decimer').
    Return a callable that accepts (image_path, hand_drawn=bool) and returns SMILES.
    """
    # Try module import (uppercase first for PyPI name)
    mod = None
    e1 = e2 = None
    try:
        mod = importlib.import_module("DECIMER")
    except Exception as err:
        e1 = err
        try:
            mod = importlib.import_module("decimer")
        except Exception as err2:
            e2 = err2

    if mod is None:
        raise ImportError(f"{e1} | {e2}")

    # Case A: module directly exposes predict_SMILES(image_path, hand_drawn=bool)
    predict = getattr(mod, "predict_SMILES", None)
    if callable(predict):
        def _call(image_path: str, hand_drawn: bool) -> str:
            try:
                return predict(image_path, hand_drawn=hand_drawn)
            except TypeError:
                # Some builds accept only the path
                return predict(image_path)
        return _call

    # Case B: module exposes load_model() returning an object with a predict method
    loader = getattr(mod, "load_model", None)
    if callable(loader):
        mdl = loader()
        # common method variants
        for name in ("predict_SMILES", "predict_smiles", "predict"):
            fn = getattr(mdl, name, None)
            if callable(fn):
                def _call(image_path: str, hand_drawn: bool, _fn=fn):
                    try:
                        return _fn(image_path, hand_drawn=hand_drawn)
                    except TypeError:
                        return _fn(image_path)
                return _call

    raise AttributeError("DECIMER is imported but no usable predict function was found")

def _warmup_blocking():
    global _status, _loading, _decimer_predict, _decimer_err, _warmup_started_at
    try:
        _status = "loading"
        _loading = True
        _warmup_started_at = time.time()
        print("[warmup] starting...")

        # OpenCV check first so we fail fast if runtime libs are missing
        import cv2  # noqa: F401
        print("[warmup] cv2 import ok")

        # Resolve DECIMER into a callable
        _decimer_predict = _resolve_decimer_callable()
        _decimer_err = None
        _status = "ready"
        print("[warmup] DECIMER ready")
    except Exception as e:
        _decimer_predict = None
        _decimer_err = f"{e.__class__.__name__}: {e}"
        _status = "error"
        print("[warmup] error:", _decimer_err)
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
    # auto-warmup if asked and not started yet
    if warmup and (_decimer_predict is None) and (not _loading) and (_decimer_err is None):
        threading.Thread(target=_warmup_blocking, daemon=True).start()

    # timeout guard while loading
    if _status == "loading" and _warmup_started_at and time.time() - _warmup_started_at > WARMUP_TIMEOUT_S:
        return {
            "ok": True, "engine": "DECIMER", "version": APP_VERSION,
            "status": "error", "decimer_ok": False,
            "decimer_error": f"warmup exceeded {WARMUP_TIMEOUT_S}s"
        }

    return {
        "ok": True, "engine": "DECIMER", "version": APP_VERSION,
        "status": _status, "decimer_ok": _decimer_predict is not None,
        "decimer_error": _decimer_err
    }

@app.post("/api/warmup")
def warmup():
    if _decimer_predict is not None:
        return {"ok": True, "status": "ready"}
    if not _loading:
        threading.Thread(target=_warmup_blocking, daemon=True).start()
    return {"ok": True, "status": "loading"}

@app.post("/api/ocsr")
def ocsr(body: OcsrBody):
    # Ensure DECIMER is available (fast path if already warmed)
    if _decimer_predict is None and _decimer_err is None and not _loading:
        try:
            # Try to resolve quickly without full background thread
            _decimer = _resolve_decimer_callable()
            globals()["_decimer_predict"] = _decimer
            globals()["_status"] = "ready"
        except Exception as e:
            globals()["_decimer_err"] = f"{e.__class__.__name__}: {e}"
            globals()["_status"] = "error"

    if _decimer_predict is None:
        raise HTTPException(status_code=503, detail=f"DECIMER not ready: {_decimer_err or 'warming up'}")

    try:
        image_path = data_url_to_file(body.imageDataUrl)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Bad image: {e}")

    try:
        # Call the resolved predictor; support both with/without hand_drawn arg
        try:
            smiles = _decimer_predict(image_path, hand_drawn=bool(body.handDrawn))
        except TypeError:
            smiles = _decimer_predict(image_path)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"DECIMER error: {e}")
    finally:
        try:
            os.remove(image_path)
        except Exception:
            pass

    return {"smiles": smiles or ""}
