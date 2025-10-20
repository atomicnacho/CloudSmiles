# main.py
import base64, os, re, tempfile, threading, sys, types, importlib, importlib.util, time, traceback
from typing import Optional, Callable, Dict, Any
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel

# Ensure DECIMER model data (pystow) has a writeable location
os.environ.setdefault("PYSTOW_HOME", "/models")

APP_NAME = "OCSR (DECIMER) API"
APP_VERSION = "1.0.1"

app = FastAPI(title=APP_NAME, version=APP_VERSION)

# ---------------- CORS ----------------
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

# ---------------- Utilities ----------------
DATA_URL_RE = re.compile(r"^data:image/(png|jpeg|jpg);base64,([A-Za-z0-9+/=]+)$")

class OcsrBody(BaseModel):
    imageDataUrl: str
    handDrawn: Optional[bool] = True

def _probe() -> Dict[str, Any]:
    """Lightweight import probe to aid debugging."""
    report: Dict[str, Any] = {"cv2": None, "decimer": None, "pyheif": None, "errors": []}
    for mod in ("cv2", "DECIMER", "decimer", "pyheif"):
        key = "decimer" if mod.lower() in ("decimer", "decimer") else mod
        try:
            m = importlib.import_module(mod)
            report[key] = {
                "version": getattr(m, "__version__", None),
                "file": getattr(m, "__file__", None),
                "ok": True,
            }
        except Exception as e:
            report[key] = {"ok": False}
            report["errors"].append(f"{mod}: {e}")
    return report

# pyheif shim — avoid native HEIF requirement; we only accept PNG/JPG from the frontend.
try:
    if importlib.util.find_spec("pyheif") is None:
        _pyheif_stub = types.ModuleType("pyheif")
        def _no_heif(*_a, **_k):
            raise ImportError("HEIF/HEIC not supported in this build")
        _pyheif_stub.read = _no_heif
        sys.modules["pyheif"] = _pyheif_stub
except Exception:
    pass

# ---------------- Lazy DECIMER state ----------------
_decimer_predict: Optional[Callable[[str, bool], str]] = None
_decimer_err: Optional[str] = None
_loading = False
_status = "idle"

# Warmup timeout guard (default 15 minutes; override via env)
WARMUP_TIMEOUT_S = int(os.getenv("WARMUP_TIMEOUT_S", "900"))
_warmup_started_at: Optional[float] = None

def _resolve_decimer_callable() -> Callable[[str, bool], str]:
    """
    Import DECIMER package (try 'DECIMER', then 'decimer') and return a callable:
        fn(image_path: str, hand_drawn: bool) -> str

    IMPORTANT: This function avoids heavy model loading during warmup.
    If the package only exposes load_model(), we create a wrapper that lazily
    constructs the model on first invocation instead of during warmup.
    """
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

    # If module-level predict_SMILES exists, use it directly.
    predict = getattr(mod, "predict_SMILES", None)
    if callable(predict):
        def _call(image_path: str, hand_drawn: bool) -> str:
            try:
                return predict(image_path, hand_drawn=hand_drawn)
            except TypeError:
                # Some builds ignore/omit the kwarg
                return predict(image_path)
        return _call

    # Fallback: lazy model load via load_model()
    loader = getattr(mod, "load_model", None)
    if callable(loader):
        _lock = threading.Lock()
        _model_holder = {"m": None}

        def _ensure_model():
            if _model_holder["m"] is None:
                with _lock:
                    if _model_holder["m"] is None:
                        _model_holder["m"] = loader()

        def _call(image_path: str, hand_drawn: bool) -> str:
            _ensure_model()
            m = _model_holder["m"]
            for name in ("predict_SMILES", "predict_smiles", "predict"):
                fn = getattr(m, name, None)
                if callable(fn):
                    try:
                        return fn(image_path, hand_drawn=hand_drawn)
                    except TypeError:
                        return fn(image_path)
            raise AttributeError("Loaded DECIMER model has no predict function")
        return _call

    raise AttributeError("DECIMER imported, but no usable predict function was found")

def _warmup_blocking():
    """Background warmup: import cv2 and resolve DECIMER callable without heavy loads."""
    global _status, _loading, _decimer_predict, _decimer_err, _warmup_started_at
    try:
        _status = "loading"
        _loading = True
        _warmup_started_at = time.time()
        print("[warmup] starting; env:", {k: os.getenv(k) for k in ("WARMUP_TIMEOUT_S",)})

        # Verify OpenCV import (fast, but catches missing libGL/libglib/etc)
        try:
            import cv2  # noqa: F401
            print("[warmup] cv2 import ok")
        except Exception as e:
            raise ImportError(f"OpenCV import failed: {e}")

        # Resolve decimer callable (no heavy model load here)
        _decimer_predict = _resolve_decimer_callable()
        _decimer_err = None
        _status = "ready"
        print("[warmup] DECIMER callable resolved")
    except Exception as e:
        _decimer_predict = None
        _decimer_err = f"{e.__class__.__name__}: {e}"
        _status = "error"
        print("[warmup] error:", _decimer_err)
        traceback.print_exc()
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

# ---------------- Routes ----------------
@app.get("/")
def root():
    return {"ok": True, "message": "CloudSmiles up", "version": APP_VERSION}

@app.get("/api/health")
def health(warmup: bool = Query(False), probe: bool = Query(False)):
    # Kick off warmup if requested and not already warming/ready/errored
    if warmup and (_decimer_predict is None) and (not _loading) and (_decimer_err is None):
        threading.Thread(target=_warmup_blocking, daemon=True).start()

    # Timeout guard while loading
    if _status == "loading" and _warmup_started_at and time.time() - _warmup_started_at > WARMUP_TIMEOUT_S:
        return {
            "ok": True,
            "engine": "DECIMER",
            "version": APP_VERSION,
            "status": "error",
            "decimer_ok": False,
            "decimer_error": f"warmup exceeded {WARMUP_TIMEOUT_S}s",
            **({"probe": _probe()} if probe else {}),
        }

    return {
        "ok": True,
        "engine": "DECIMER",
        "version": APP_VERSION,
        "status": _status,
        "decimer_ok": _decimer_predict is not None,
        "decimer_error": _decimer_err,
        **({"probe": _probe()} if probe else {}),
    }

@app.get("/api/probe")
def probe():
    return {"ok": True, "engine": "DECIMER", "version": APP_VERSION, "probe": _probe()}

@app.post("/api/warmup")
def warmup():
    if _decimer_predict is not None:
        return {"ok": True, "status": "ready"}
    if not _loading:
        threading.Thread(target=_warmup_blocking, daemon=True).start()
    return {"ok": True, "status": "loading"}

@app.post("/api/ocsr")
def ocsr(body: OcsrBody):
    # If not warmed, try to resolve quickly once (still lightweight)
    if _decimer_predict is None and _decimer_err is None and not _loading:
        try:
            # Check cv2 quickly; gives nice 503 if missing
            import cv2  # noqa: F401
            dec = _resolve_decimer_callable()
            globals()["_decimer_predict"] = dec
            globals()["_status"] = "ready"
        except Exception as e:
            globals()["_decimer_err"] = f"{e.__class__.__name__}: {e}"
            globals()["_status"] = "error"

    if _decimer_predict is None:
        raise HTTPException(status_code=503, detail=f"DECIMER not ready: {_decimer_err or 'warming up'}")

    # Accept data URL (png/jpg) from the client
    try:
        image_path = data_url_to_file(body.imageDataUrl)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Bad image: {e}")

    try:
        # Call predictor; support variants with/without hand_drawn kw
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
