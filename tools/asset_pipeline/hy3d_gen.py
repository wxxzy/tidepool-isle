# -*- coding: utf-8 -*-
"""混元3D 资源生成编排器：提交 / 轮询 / 下载 / 落盘清单"""
import json
import os
import sys
import time
import traceback

import hy3d_client as C

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "hy3d_out")
STATE = os.path.join(OUT, "jobs.json")
REF3D = os.path.join(HERE, "ref3d")


def load_state():
    if os.path.exists(STATE):
        with open(STATE, "r", encoding="utf-8") as f:
            return json.load(f)
    return {}


def save_state(st):
    os.makedirs(OUT, exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(st, f, ensure_ascii=False, indent=2)
    os.replace(tmp, STATE)


def build_payload(spec):
    p = {
        "Model": spec.get("model", "3.1"),
        "FaceCount": spec.get("face_count", 15000),
        "EnablePBR": spec.get("pbr", True),
        "GenerateType": spec.get("gen_type", "Normal"),
    }
    if spec.get("prompt"):
        p["Prompt"] = spec["prompt"]
    main = spec.get("main")
    if main:
        p["ImageBase64"] = C.img_to_data_url(os.path.join(REF3D, main))
    mv = []
    for view, fn in spec.get("views", {}).items():
        mv.append({"ViewType": view,
                   "ViewImageBase64": C.img_to_data_url(os.path.join(REF3D, fn))})
    if mv:
        p["MultiViewImages"] = mv
    return p


def submit_one(name, spec):
    st = load_state()
    ent = st.get(name, {})
    if ent.get("job_id") and ent.get("status") in ("RUN", "DONE"):
        print(f"[skip] {name} 已有任务 {ent['job_id']} ({ent['status']})")
        return ent
    payload = build_payload(spec)
    sizes = {k: (len(v) if isinstance(v, str) else "list") for k, v in payload.items()}
    print(f"[submit] {name} -> {sizes}", flush=True)
    code, body = C.submit(payload)
    print(f"[submit] {name} <- {code} {json.dumps(body, ensure_ascii=False)[:500]}", flush=True)
    resp = body.get("Response", body)
    if resp.get("Error"):
        ent.update({"status": "FAIL", "error": resp["Error"], "spec": spec,
                    "at": time.strftime("%Y-%m-%d %H:%M:%S")})
    else:
        ent.update({"status": "RUN", "job_id": resp.get("JobId"), "spec": spec,
                    "at": time.strftime("%Y-%m-%d %H:%M:%S")})
    st[name] = ent
    save_state(st)
    return ent


def poll_all(names, timeout=2400):
    st = load_state()
    deadline = time.time() + timeout
    pending = [n for n in names if st.get(n, {}).get("status") == "RUN"]
    while pending and time.time() < deadline:
        for n in list(pending):
            ent = st[n]
            code, body = C.query(ent["job_id"])
            resp = body.get("Response", body)
            if resp.get("Error"):
                print(f"[{n}] query err {resp['Error'].get('Code')}", flush=True)
                continue
            status = resp.get("Status")
            if status != ent.get("last_status"):
                print(f"[{n}] {status} progress={resp.get('Progress')}", flush=True)
                ent["last_status"] = status
            if status == "DONE":
                ent["status"] = "DONE"
                ent["result"] = resp
                files = resp.get("ResultFile3Ds") or []
                ent["files"] = files
                print(f"[{n}] DONE files={[(f.get('Type'), f.get('Url','')[:60]) for f in files]}", flush=True)
                save_state(st)
                pending.remove(n)
            elif status in ("FAIL", "FAILED"):
                ent["status"] = "FAIL"
                ent["error"] = resp
                print(f"[{n}] FAIL {json.dumps(resp, ensure_ascii=False)[:400]}", flush=True)
                save_state(st)
                pending.remove(n)
            save_state(st)
        if pending:
            time.sleep(12)
    return st


def download_all(names):
    st = load_state()
    for n in names:
        ent = st.get(n)
        if not ent or ent.get("status") != "DONE":
            continue
        if ent.get("downloaded"):
            print(f"[dl] {n} 已下载: {ent['downloaded']}")
            continue
        best = None
        for f in ent.get("files") or []:
            if (f.get("Type") or "").upper() == "GLB":
                best = f
                break
        if not best and ent.get("files"):
            best = ent["files"][0]
        if not best:
            print(f"[dl] {n} 无文件")
            continue
        dest = os.path.join(OUT, "glb", f"{n}.glb")
        try:
            size = C.download(best["Url"], dest)
            ent["downloaded"] = dest
            ent["bytes"] = size
            ent["preview"] = best.get("PreviewImageUrl")
            print(f"[dl] {n} -> {dest} {size/1048576:.2f} MB", flush=True)
        except Exception as e:
            print(f"[dl] {n} 失败 {e}")
        save_state(st)
    return st


MAX_INFLIGHT = 3


def run_queue(spec_path, timeout=3600):
    """队列调度：始终维持 <=3 个未完成任务，完成即下载，循环补位。"""
    with open(spec_path, "r", encoding="utf-8") as f:
        specs = json.load(f)
    # 允许在 spec 里写 "_note" / "_usage" 之类的说明字段
    specs = {k: v for k, v in specs.items() if not k.startswith("_")}
    st = load_state()
    queue = []
    for n in specs:
        ent = st.get(n, {})
        if ent.get("status") == "DONE" and ent.get("downloaded"):
            print(f"[ok] {n} 已完成并下载")
            continue
        if ent.get("status") == "DONE" and not ent.get("downloaded"):
            queue.append(n)  # 只需下载
            continue
        if ent.get("status") == "RUN" and ent.get("job_id"):
            queue.append(n)  # 已在飞，接管轮询
            continue
        ent.clear()
        st[n] = ent
        queue.append(n)
    save_state(st)

    deadline = time.time() + timeout
    while queue and time.time() < deadline:
        st = load_state()
        inflight = [n for n, v in st.items() if v.get("status") == "RUN"]
        # 先收割已完成的
        for n in list(queue):
            ent = st.get(n, {})
            if ent.get("status") == "DONE":
                download_all([n])
                queue.remove(n)
        if queue and len(inflight) < MAX_INFLIGHT:
            for n in list(queue):
                if len(inflight) >= MAX_INFLIGHT:
                    break
                st = load_state()
                ent = st.get(n, {})
                if ent.get("status") == "RUN":
                    continue
                if ent.get("status") == "DONE":
                    continue
                r = submit_one(n, specs[n])
                if r.get("status") == "RUN":
                    inflight.append(n)
                else:
                    err = (r.get("error") or {}).get("Code", "")
                    print(f"[wait] {n} {err}", flush=True)
                    if "JobNumExceed" in err:
                        break  # 名额已满，本轮不再尝试
                    queue.remove(n)
                    time.sleep(3)
        # 轮询在飞任务
        for n in list(inflight):
            st = load_state()
            ent = st.get(n)
            if not ent:
                continue
            code, body = C.query(ent["job_id"])
            resp = body.get("Response", body)
            if resp.get("Error"):
                print(f"[{n}] query err {resp['Error'].get('Code')}", flush=True)
                continue
            status = resp.get("Status")
            if status != ent.get("last_status"):
                print(f"[{n}] {status} progress={resp.get('Progress')}", flush=True)
                ent["last_status"] = status
            if status == "DONE":
                ent["status"] = "DONE"
                ent["result"] = resp
                ent["files"] = resp.get("ResultFile3Ds") or []
                save_state(st)
                print(f"[{n}] DONE {[(x.get('Type')) for x in ent['files']]}", flush=True)
                download_all([n])
            elif status in ("FAIL", "FAILED"):
                ent["status"] = "FAIL"
                ent["error"] = resp
                save_state(st)
                print(f"[{n}] FAIL {resp.get('ErrorCode')} {resp.get('ErrorMessage')}", flush=True)
            else:
                save_state(st)
        if queue or inflight:
            time.sleep(10)
    print("=== 队列结束，剩余:", queue)


if __name__ == "__main__":
    action = sys.argv[1]
    st = load_state()
    if action == "run":
        run_queue(sys.argv[2])
    elif action == "submit":
        spec_path = sys.argv[2]
        with open(spec_path, "r", encoding="utf-8") as f:
            specs = json.load(f)
        names = list(specs.keys())
        for n in names:
            submit_one(n, specs[n])
            time.sleep(1)
        print("NAMES=" + ",".join(names))
    elif action == "poll":
        names = sys.argv[2].split(",")
        poll_all(names)
    elif action == "download":
        names = sys.argv[2].split(",")
        download_all(names)
    elif action == "status":
        for k, v in load_state().items():
            print(f"{k:16s} {v.get('status'):6s} {v.get('job_id')} {v.get('error',{}).get('Code','') if isinstance(v.get('error'),dict) else ''}")
