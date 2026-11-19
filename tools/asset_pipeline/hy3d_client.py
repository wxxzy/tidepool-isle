# -*- coding: utf-8 -*-
"""混元3D OpenAI 兼容端点客户端（submit / query / download）"""
import base64
import json
import mimetypes
import os
import sys
import time

import requests

BASE = "https://api.ai3d.cloud.tencent.com"
KEY = "sk-y1MTy3x5C6xSMRxPlaVns8aY1KjzjHW6URXznzrd2Fb872ql"
HDR = {"Authorization": KEY, "Content-Type": "application/json"}

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hy3d_out")


def _post(path, payload, timeout=90):
    url = BASE + path
    r = requests.post(url, headers=HDR, json=payload, timeout=timeout)
    try:
        body = r.json()
    except Exception:
        body = {"_raw": r.text[:2000]}
    return r.status_code, body


def img_to_data_url(path, max_bytes=6 * 1024 * 1024):
    """本地图 -> data:image/png;base64,... （按需降采样到 <=6MB base64 前）"""
    from PIL import Image
    import io

    im = Image.open(path)
    if im.mode not in ("RGB", "RGBA"):
        im = im.convert("RGBA")
    # 逐步缩小直到 base64 体积达标（6MB base64 约等于 4.4MB 原始）
    for side in (2048, 1600, 1280, 1024, 800, 640):
        w, h = im.size
        scale = min(1.0, side / max(w, h))
        cur = im if scale >= 1.0 else im.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.LANCZOS)
        buf = io.BytesIO()
        cur.save(buf, format="PNG", optimize=True)
        raw = buf.getvalue()
        if len(raw) * 1.37 <= max_bytes:
            return "data:image/png;base64," + base64.b64encode(raw).decode()
    buf = io.BytesIO()
    cur.save(buf, format="JPEG", quality=88)
    raw = buf.getvalue()
    return "data:image/jpeg;base64," + base64.b64encode(raw).decode()


def submit(payload):
    return _post("/v1/ai3d/submit", payload)


def query(job_id):
    return _post("/v1/ai3d/query", {"JobId": str(job_id)})


def wait(job_id, timeout=1800, interval=15, verbose=True):
    t0 = time.time()
    last = None
    while time.time() - t0 < timeout:
        code, body = query(job_id)
        st = json.dumps(body, ensure_ascii=False)
        status = (body.get("Status") or body.get("status") or
                  (body.get("Data") or {}).get("Status") if isinstance(body, dict) else None)
        if verbose and st != last:
            print(f"[{int(time.time()-t0):4d}s] {st[:400]}", flush=True)
            last = st
        if status in ("DONE", "FAIL", "FAILED", "ERROR", "SUCCESS"):
            return code, body, time.time() - t0
        if "Error" in body and body.get("Error"):
            return code, body, time.time() - t0
        time.sleep(interval)
    return -1, {"Status": "TIMEOUT"}, time.time() - t0


def download(url, dest):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    r = requests.get(url, timeout=300, stream=True)
    r.raise_for_status()
    n = 0
    with open(dest, "wb") as f:
        for chunk in r.iter_content(1 << 20):
            f.write(chunk)
            n += len(chunk)
    return n


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "probe"
    if cmd == "probe":
        # 1) 用一个假 JobId 探鉴权（不消耗生成额度）
        code, body = query("1000000000000000000")
        print("PROBE query fake job ->", code, json.dumps(body, ensure_ascii=False)[:600])
        # 2) 空 payload 提交，看参数校验提示（能反推必填字段）
        code, body = submit({})
        print("PROBE submit empty ->", code, json.dumps(body, ensure_ascii=False)[:800])
