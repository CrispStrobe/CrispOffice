"""Summarise build/typing_profile.json from the typing profile integration test.

Prints the slowest keystrokes (handler time, phases, GC overlapping the
handler span) and GC/frame totals.  Usage: keystroke_trace_report.py FILE
"""
import json
import sys


def main(path):
    data = json.load(open(path))
    keys = data.get("keys", [])
    timeline = data.get("timeline") or {}
    events = timeline.get("traceEvents", [])
    spans = {}
    for e in events:
        if e.get("name") != "KEY_HANDLER":
            continue
        k = (e.get("args") or {}).get("key")
        ident = e.get("id")
        ph = e.get("ph")
        if ph == "b":
            spans.setdefault(ident, {})["start"] = e["ts"]
            spans[ident]["key"] = k
        elif ph == "e":
            spans.setdefault(ident, {})["end"] = e["ts"]
    windows = {}
    for s in spans.values():
        if "start" in s and "end" in s and s.get("key") is not None:
            windows[int(s["key"])] = (s["start"], s["end"])
    # GC slices: complete events or begin/end pairs per thread and name.
    gc = []
    idle = 0.0
    open_ = {}
    for e in events:
        if e.get("cat") != "GC":
            continue
        ph = e.get("ph")
        name = e.get("name", "")
        key = (e.get("tid"), name)
        if ph == "X" and "dur" in e:
            span = (e["ts"], e["ts"] + e["dur"], name)
        elif ph == "B":
            open_.setdefault(key, []).append(e["ts"])
            continue
        elif ph == "E" and open_.get(key):
            span = (open_[key].pop(), e["ts"], name)
        else:
            continue
        if name == "NotifyIdle":
            idle += (span[1] - span[0]) / 1000
            continue
        if name in ("Scavenge", "MarkSweep", "MarkCompact",
                    "StartConcurrentMark", "EvacuateNewGeneration"):
            gc.append(span)
    gc_in = {}
    for k, (a, b) in windows.items():
        total = 0.0
        names = {}
        for s, t, n in gc:
            o = min(b, t) - max(a, s)
            if o > 0:
                total += o / 1000
                names[n] = names.get(n, 0) + o / 1000
        gc_in[k] = (total, names)
    handler = [k["handlerMs"] for k in keys]
    order = sorted(range(len(handler)), key=lambda i: -handler[i])
    srt = sorted(handler)
    pct = lambda p: srt[round((len(srt) - 1) * p)] if srt else 0
    print(f"keystrokes {len(handler)} handler p50 {pct(.5):.2f} p95 {pct(.95):.2f} "
          f"max {max(handler) if handler else 0:.2f} ms")
    print(f"idle-time GC (NotifyIdle, between frames) {idle:.1f} ms")
    print(f"GC events {len(gc)}, total {sum(t - s for s, t, _ in gc) / 1000:.1f} ms; "
          f"GC inside handlers {sum(v[0] for v in gc_in.values()):.1f} ms")
    frames = data.get("frames", [])
    if frames:
        b = sorted(f["buildMs"] for f in frames)
        r = sorted(f["rasterMs"] for f in frames)
        print(f"frames {len(frames)} build p50 {b[len(b)//2]:.2f} max {b[-1]:.2f}; "
              f"raster p50 {r[len(r)//2]:.2f} max {r[-1]:.2f} ms")
    print("slowest keystrokes:")
    for i in order[:10]:
        ph = keys[i].get("phases", {})
        top = sorted(ph.items(), key=lambda kv: -kv[1])[:6]
        g = gc_in.get(i, (0, {}))
        print(f"  key {i}: {handler[i]:.2f} ms; GC {g[0]:.2f} {dict((n, round(v, 2)) for n, v in g[1].items())}; "
              + ", ".join(f"{n}={v}" for n, v in top))
    totals = {}
    for k in keys:
        for n, v in k.get("phases", {}).items():
            totals[n] = totals.get(n, 0) + v
    print("phase totals (ms over all keystrokes):")
    for n, v in sorted(totals.items(), key=lambda kv: -kv[1])[:15]:
        print(f"  {v:9.1f}  {n}")


if __name__ == "__main__":
    main(sys.argv[1])
