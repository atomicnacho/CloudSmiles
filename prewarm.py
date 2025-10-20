import os
import pathlib

# Make sure cache goes into the image layer
os.environ.setdefault("PYSTOW_HOME", "/models")
os.environ.setdefault("HF_HOME", "/models")
os.environ.setdefault("TRANSFORMERS_CACHE", "/models")
os.environ.setdefault("XDG_CACHE_HOME", "/models")

print("[prewarm] PYSTOW_HOME =", os.environ["PYSTOW_HOME"])

# Import DECIMER (module name varies)
dec = None
try:
    import DECIMER as dec
    print("[prewarm] imported DECIMER")
except Exception as e1:
    print("[prewarm] DECIMER import failed:", e1)
    try:
        import decimer as dec
        print("[prewarm] imported decimer")
    except Exception as e2:
        print("[prewarm] decimer import failed:", e2)
        raise SystemExit("Failed to import DECIMER/decimer during build")

# Create a tiny blank image to trigger lazy model download
from PIL import Image
img = pathlib.Path("/tmp/blank.png")
Image.new("RGB", (16, 16), (255, 255, 255)).save(img)

# Try common entry points to force weights to be pulled
ok = False
for attr in ("predict_SMILES", "predict", "load_model"):
    fn = getattr(dec, attr, None)
    if callable(fn):
        try:
            print(f"[prewarm] calling {attr} to trigger weight download...")
            # Some APIs need a path, some just load; ignore failures on blank input.
            _ = fn(str(img)) if attr != "load_model" else fn()
            ok = True
            break
        except Exception as e:
            print(f"[prewarm] {attr} raised (expected on blank image):", e)

if not ok:
    print("[prewarm] could not call a public API, but import succeeded; weights may still be cached.")

print("[prewarm] done.")
