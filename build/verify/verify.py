#!/usr/bin/env python3
"""verify.py — status-aware smoke verification of PUBLISHED struct packages.

Flow:
  1. Determine LIVE publish status via tools/release_status.py --json (queries
     each registry directly — npm/pypi/rubygems/go-proxy/crates).
  2. Verify ONLY the ports whose package is actually published. Each
     verify-<port> target self-cleans and forces a fresh online install, so we
     always exercise the live published artifact, never a stale local copy.
  3. Transient registry/network errors are retried, then reported as
     UNAVAILABLE (never FAIL) — a registry outage must not read as a broken
     package. Unpublished ports are SKIPPED.
  4. Print a full report for every harness port; exit non-zero ONLY on a real
     verification FAILURE (package published but smoke broke).

Usage: python3 verify.py [--retries N]
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
HARNESS = ["go", "typescript", "javascript", "python", "ruby", "rust"]
RETRIES = int(sys.argv[sys.argv.index("--retries") + 1]) if "--retries" in sys.argv else 3

# Output substrings that signal a TRANSIENT registry/network problem (retry),
# as opposed to a deterministic failure (the package is broken — do not retry).
TRANSIENT = re.compile(
    r"ETIMEDOUT|ECONNRESET|ECONNREFUSED|ENOTFOUND|EAI_AGAIN|socket hang up|"
    r"network|timed?[ -]?out|temporar|throttl|rate limit|\b429\b|"
    r"\b50[0-9]\b|service unavailable|bad gateway|gateway time|"
    r"could not resolve host|connection (refused|reset|timed)|"
    r"tls|handshake|failed to (download|fetch|connect|resolve)|unreachable|"
    r"spurious network error|error sending request|registry .*(down|unavailable)",
    re.I,
)


def live_status() -> dict:
    p = subprocess.run(
        [sys.executable, "tools/release_status.py", "--json"],
        cwd=ROOT, capture_output=True, text=True,
    )
    try:
        return {r["port"]: r for r in json.loads(p.stdout)}
    except Exception:
        return {}


def published(entry) -> bool:
    """A real version string in the REGISTRY column means it is installable."""
    return bool(re.match(r"^\d", (entry or {}).get("registry") or ""))


def registry_unknown(entry) -> bool:
    return (entry or {}).get("registry") in ("?", None)


def run_verify(port: str):
    """Run `make verify-<port>` with transient-retry; classify the outcome."""
    tail = ""
    for attempt in range(1, RETRIES + 1):
        p = subprocess.run(
            ["make", "-s", f"verify-{port}"], cwd=HERE, capture_output=True, text=True
        )
        out = (p.stdout + p.stderr).strip()
        tail = out.splitlines()[-1] if out else ""
        if p.returncode == 0 and "OK" in p.stdout:
            return ("OK", tail)
        if TRANSIENT.search(out):
            time.sleep(2 * attempt)  # back off and retry
            continue
        return ("FAIL", tail)  # deterministic — the published package is broken
    return ("UNAVAILABLE", f"transient registry/network error after {RETRIES} tries")


def main() -> int:
    print("== live publish status (tools/release_status.py --json) ==")
    st = live_status()
    if not st:
        print("!! could not determine status (release_status.py --json failed)")
        return 2

    results = {}
    for port in HARNESS:
        e = st.get(port)
        if published(e):
            print(f"\n== verify {port} (published {e['registry']}) — fresh online install ==")
            results[port] = run_verify(port)
        elif registry_unknown(e):
            results[port] = ("UNAVAILABLE", "registry status probe failed")
        else:
            results[port] = ("SKIPPED", "not published")

    print("\n" + "=" * 64)
    print(f"{'PORT':<12}{'PUBLISHED':<12}{'RESULT':<14}NOTE")
    print("-" * 64)
    for port in HARNESS:
        e = st.get(port) or {}
        res, note = results[port]
        pub = e.get("registry") if published(e) else "-"
        print(f"{port:<12}{str(pub):<12}{res:<14}{note[:64]}")
    print("=" * 64)

    n = lambda k: sum(1 for r in results.values() if r[0] == k)  # noqa: E731
    print(
        f"{n('OK')} verified · {n('SKIPPED')} skipped(unpublished) · "
        f"{n('UNAVAILABLE')} unavailable(transient) · {n('FAIL')} failed"
    )
    return 1 if n("FAIL") else 0


if __name__ == "__main__":
    raise SystemExit(main())
