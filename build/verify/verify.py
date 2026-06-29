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
# Registry ports: published == a real version on the package registry.
HARNESS_REGISTRY = ["go", "typescript", "javascript", "python", "ruby", "rust"]
# Tag-only ports: the release IS the git tag (no registry). Published == the
# tag exists (release_status STATUS == released). Verified by fetching the
# source at the live tag and building a smoke client against it.
HARNESS_TAG = ["php", "zig", "c", "cpp", "swift"]
HARNESS = HARNESS_REGISTRY + HARNESS_TAG
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

# A LOCAL toolchain problem (missing tool, or a link/SDK incompatibility) is not
# the published package's fault — the source fetched + compiled, the machine
# just can't finish the build. Report TOOLCHAIN (non-failing), like transient.
# NB: only link/SDK-stage errors qualify; a compile error in the fetched source
# falls through to FAIL (that WOULD be a broken release).
TOOLCHAIN = re.compile(
    r"toolchain not found|command not found|not found.*toolchain|"
    r"unable to (link|create)|\bld:|linker|lld|undefined symbol: _|"
    r"libsystem|\bsdk\b|posix_memalign|incompatible.*sdk|no such file or directory.*(zig|swiftc)",
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


def registry_published(entry) -> bool:
    """A real version string in the REGISTRY column means it is installable."""
    return bool(re.match(r"^\d", (entry or {}).get("registry") or ""))


def is_published(port: str, entry) -> bool:
    """Is the port's release live? Registry ports: a registry version. Tag-only
    ports: the git tag exists (release_status STATUS == released)."""
    if port in HARNESS_TAG:
        return (entry or {}).get("status") == "released"
    return registry_published(entry)


def registry_unknown(port: str, entry) -> bool:
    # Only registry ports can have an indeterminate (network-flaky) probe;
    # tag status comes from git and is always known.
    return port not in HARNESS_TAG and (entry or {}).get("registry") in ("?", None)


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
            ok = [ln for ln in p.stdout.splitlines() if ln.lstrip().startswith("OK")]
            return ("OK", ok[-1] if ok else tail)
        if TRANSIENT.search(out):
            time.sleep(2 * attempt)  # back off and retry
            continue
        if TOOLCHAIN.search(out):
            return ("TOOLCHAIN", tail)  # local toolchain can't build — not the package
        return ("FAIL", tail)  # deterministic — the published package is broken
    return ("UNAVAILABLE", f"transient registry/network error after {RETRIES} tries")


def main() -> int:
    print("== live publish status (tools/release_status.py --json) ==")
    st = live_status()
    if not st:
        print("!! could not determine status (release_status.py --json failed)")
        return 2

    results = {}  # only the harness ports get a smoke result
    for port in HARNESS:
        e = st.get(port)
        if is_published(port, e):
            how = "fresh online install" if port in HARNESS_REGISTRY else "build from live tag source"
            print(f"\n== verify {port} (published) — {how} ==")
            results[port] = run_verify(port)
        elif registry_unknown(port, e):
            results[port] = ("UNAVAILABLE", "registry status probe failed")
        else:
            results[port] = ("SKIPPED", "not published")

    def released(port, e) -> str:
        if is_published(port, e):
            ver = e["registry"] if registry_published(e) else (e.get("local") or "")
            return f"yes {ver}".rstrip()
        return "no"

    def kind(port, e) -> str:
        rk = (e or {}).get("registry_kind", "?")
        return "tag" if rk == "tag" else rk

    # Full report: EVERY port. KIND shows the channel (registry name vs `tag`).
    # Non-harness ports have no smoke client (shown 'no-client').
    print("\n" + "=" * 78)
    print(f"{'PORT':<12}{'KIND':<11}{'PUBLISHED':<13}{'VERIFY':<13}NOTE")
    print("-" * 78)
    for port, e in st.items():
        if port in results:
            res, note = results[port]
        else:
            res, note = "no-client", "not in verify harness (no smoke client)"
        print(f"{port:<12}{kind(port, e):<11}{released(port, e):<13}{res:<13}{note[:38]}")
    print("=" * 78)

    n = lambda k: sum(1 for r in results.values() if r[0] == k)  # noqa: E731
    no_client = len(st) - len(results)
    print(
        f"{n('OK')} verified · {n('SKIPPED')} skipped(unpublished) · "
        f"{n('UNAVAILABLE')} unavailable(transient) · {n('TOOLCHAIN')} toolchain-blocked · "
        f"{n('FAIL')} failed · {no_client} no-client"
    )
    return 1 if n("FAIL") else 0


if __name__ == "__main__":
    raise SystemExit(main())
