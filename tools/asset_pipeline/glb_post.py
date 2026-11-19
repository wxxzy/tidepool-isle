#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""GLB 后处理（混元3D 产物专用）

能力：
  - 贴图降采样（PNG/JPEG）
  - 从真实顶点数据计算包围盒（混元导出的 accessor min/max 不可信）
  - 把平移烘焙进顶点：--ground(min Y -> 0) / --center(x,z 居中)
  - 可选烘焙绕 X 轴旋转（默认不做，混元 3D 直出已是 Y-up）

用法:
  python glb_post.py in.glb out.glb --tex 1024 --ground --center
"""
import argparse
import io
import json
import math
import struct
import sys

from PIL import Image

GLB_MAGIC = b"glTF"


def read_glb(path):
    raw = open(path, "rb").read()
    magic, ver, total = struct.unpack_from("<4sII", raw, 0)
    assert magic == GLB_MAGIC, "not a glb"
    off, js, bin_ = 12, None, None
    while off < len(raw):
        clen, ctype = struct.unpack_from("<I4s", raw, off)
        data = raw[off + 8: off + 8 + clen]
        if ctype == b"JSON":
            js = json.loads(data.decode("utf-8"))
        elif ctype.startswith(b"BIN"):
            bin_ = data
        off += 8 + clen
    return js, bin_, ver


def write_glb(path, js, bin_):
    jb = json.dumps(js, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    jb += b" " * ((4 - len(jb) % 4) % 4)
    bb = bin_ + b"\x00" * ((4 - len(bin_) % 4) % 4)
    total = 12 + 8 + len(jb) + (8 + len(bb) if bb else 0)
    out = bytearray()
    out += struct.pack("<4sII", GLB_MAGIC, 2, total)
    out += struct.pack("<I4s", len(jb), b"JSON") + jb
    if bb:
        out += struct.pack("<I4s", len(bb), b"BIN\x00") + bb
    open(path, "wb").write(out)
    return total


def resize_image(data, max_side, force_jpeg=False):
    im = Image.open(io.BytesIO(data))
    mode = im.mode
    w, h = im.size
    scale = min(1.0, max_side / max(w, h))
    if scale < 1.0:
        im = im.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.LANCZOS)
    buf = io.BytesIO()
    if force_jpeg and mode in ("RGB", "L"):
        im.convert("RGB").save(buf, format="JPEG", quality=90, optimize=True)
        mime = "image/jpeg"
    else:
        if mode not in ("RGB", "RGBA", "L", "LA"):
            im = im.convert("RGBA")
        im.save(buf, format="PNG", optimize=True)
        mime = "image/png"
    return buf.getvalue(), mime, (w, h), im.size


def reorder_bin(js, bin_, replacements):
    bvs = js["bufferViews"]
    new = bytearray()
    for i, bv in enumerate(bvs):
        start = bv.get("byteOffset", 0)
        length = bv["byteLength"]
        data = replacements.get(i)
        if data is None:
            data = bin_[start:start + length]
        while len(new) % 4:
            new.append(0)
        bv["byteOffset"] = len(new)
        bv["byteLength"] = len(data)
        new += data
    while len(new) % 4:
        new.append(0)
    js["buffers"][0]["byteLength"] = len(new)
    return bytes(new)


def _pos_accessors(js):
    out = []
    for m in js.get("meshes", []):
        for p in m.get("primitives", []):
            ai = p.get("attributes", {}).get("POSITION")
            if ai is not None and ai not in out:
                out.append(ai)
    return out


def _acc_region(js, ai):
    acc = js["accessors"][ai]
    bv = js["bufferViews"][acc["bufferView"]]
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = bv.get("byteStride") or 12
    return acc, base, stride


def vertex_bounds(js, bin_):
    mn = [math.inf] * 3
    mx = [-math.inf] * 3
    for ai in _pos_accessors(js):
        acc, base, stride = _acc_region(js, ai)
        if acc.get("componentType") != 5126 or "sparse" in acc:
            print(f"  ! accessor {ai} unsupported, skip bounds")
            continue
        for i in range(acc["count"]):
            x, y, z = struct.unpack_from("<fff", bin_, base + i * stride)
            mn = [min(mn[0], x), min(mn[1], y), min(mn[2], z)]
            mx = [max(mx[0], x), max(mx[1], y), max(mx[2], z)]
    return mn, mx


def bake_transform(js, bin_, rot_x_deg=0.0, offset=(0.0, 0.0, 0.0)):
    buf = bytearray(bin_)
    th = math.radians(rot_x_deg)
    c, s = math.cos(th), math.sin(th)
    dx, dy, dz = offset
    touched = 0
    for m in js.get("meshes", []):
        for p in m.get("primitives", []):
            for key in ("POSITION", "NORMAL"):
                ai = p.get("attributes", {}).get(key)
                if ai is None:
                    continue
                acc, base, stride = _acc_region(js, ai)
                if acc.get("componentType") != 5126 or acc.get("type") != "VEC3" or "sparse" in acc:
                    continue
                mn = [math.inf] * 3
                mx = [-math.inf] * 3
                for i in range(acc["count"]):
                    o = base + i * stride
                    x, y, z = struct.unpack_from("<fff", buf, o)
                    if rot_x_deg:
                        y, z = y * c - z * s, y * s + z * c
                    if key == "POSITION":
                        x, y, z = x + dx, y + dy, z + dz
                    struct.pack_into("<fff", buf, o, x, y, z)
                    if key == "POSITION":
                        mn = [min(mn[0], x), min(mn[1], y), min(mn[2], z)]
                        mx = [max(mx[0], x), max(mx[1], y), max(mx[2], z)]
                if key == "POSITION":
                    acc["min"] = mn
                    acc["max"] = mx
                touched += 1
    print(f"  baked rot_x={rot_x_deg}° offset={offset} into {touched} accessors")
    return bytes(buf)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--tex", type=int, default=0)
    ap.add_argument("--jpeg", action="store_true")
    ap.add_argument("--ground", action="store_true", help="最低点平移到 y=0")
    ap.add_argument("--center", action="store_true", help="x/z 居中到 0")
    ap.add_argument("--rot-x", type=float, default=0.0)
    a = ap.parse_args()

    js, bin_, _ = read_glb(a.src)
    old_size = len(open(a.src, "rb").read())

    reps = {}
    if a.tex:
        for ii, im in enumerate(js.get("images", [])):
            bv = im.get("bufferView")
            if bv is None or "uri" in im:
                continue
            start = js["bufferViews"][bv].get("byteOffset", 0)
            length = js["bufferViews"][bv]["byteLength"]
            new, mime, oldd, newd = resize_image(bin_[start:start + length], a.tex, a.jpeg)
            reps[bv] = new
            im["mimeType"] = mime
            print(f"  img{ii} {str(im.get('name',''))[:44]}: {oldd[0]}x{oldd[1]}->{newd[0]}x{newd[1]} "
                  f"{length//1024}KB->{len(new)//1024}KB")
    if reps:
        bin_ = reorder_bin(js, bin_, reps)

    mn, mx = vertex_bounds(js, bin_)
    print(f"  true bounds min={[round(v,4) for v in mn]} max={[round(v,4) for v in mx]}")
    print(f"  size={[round(mx[i]-mn[i],4) for i in range(3)]}")

    off = [0.0, 0.0, 0.0]
    if a.ground:
        off[1] = -mn[1]
    if a.center:
        off[0] = -(mn[0] + mx[0]) * 0.5
        off[2] = -(mn[2] + mx[2]) * 0.5
    if a.rot_x or any(off):
        bin_ = bake_transform(js, bin_, a.rot_x, tuple(off))
        mn, mx = vertex_bounds(js, bin_)
        print(f"  after: min={[round(v,4) for v in mn]} max={[round(v,4) for v in mx]}")

    total = write_glb(a.dst, js, bin_)
    print(f"  {a.src.split('/')[-1]}: {old_size/1048576:.2f}MB -> {total/1048576:.2f}MB -> {a.dst}")


if __name__ == "__main__":
    main()
