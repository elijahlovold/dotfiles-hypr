#!/usr/bin/env python3
"""Where the wallpaper instance's CPU time goes, per thread.

    python3 ~/.config/dotfiles-hypr/quickshell-wall/cpu-threads.py [seconds]

Samples /proc/<pid>/task/*/stat over the window (default 20s) and prints each
busy thread's share as % of one core, plus the process total as both % of
one core and % of the whole CPU (what btop shows by default).
"""

import os
import subprocess
import sys
import time

SECS = float(sys.argv[1]) if len(sys.argv) > 1 else 20
TICK = os.sysconf("SC_CLK_TCK")


def wall_pid():
    out = subprocess.run(["pgrep", "-f", "quickshell-wall"], capture_output=True, text=True).stdout.split()
    pids = [int(p) for p in out if int(p) != os.getpid()]
    # The qs process itself, not a shell or this script.
    for pid in pids:
        with open(f"/proc/{pid}/comm") as f:
            if f.read().strip() in ("qs", "quickshell"):
                return pid
    sys.exit("quickshell-wall isn't running")


def threads(pid):
    out = {}
    for tid in os.listdir(f"/proc/{pid}/task"):
        try:
            with open(f"/proc/{pid}/task/{tid}/stat") as f:
                stat = f.read()
        except OSError:
            continue
        name = stat[stat.index("(") + 1:stat.rindex(")")]
        fields = stat.rsplit(")", 1)[1].split()
        out[tid] = (name, int(fields[11]) + int(fields[12]))
    return out


pid = wall_pid()
a = threads(pid)
t0 = time.monotonic()
time.sleep(SECS)
dt = time.monotonic() - t0
b = threads(pid)

rows = []
for tid, (name, ticks) in b.items():
    used = ticks - a[tid][1] if tid in a else ticks
    rows.append((used / TICK / dt * 100, name, tid))
rows.sort(reverse=True)
total = sum(r[0] for r in rows)
print(f"pid {pid}, {len(rows)} threads, {dt:.0f}s")
for pct, name, tid in rows:
    if pct >= 0.05:
        print(f"  {pct:5.2f}%  {name:<20} tid {tid}")
print(f"total {total:.2f}% of one core = {total / os.cpu_count():.2f}% of all {os.cpu_count()} threads")
