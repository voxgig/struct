#!/usr/bin/env python3
"""release_status.py — a release dashboard for every voxgig/struct language port.

For each port it reports four things:
  LOCAL     the version in the port's manifest (package.json, Cargo.toml, …)
  TAG       the latest published git tag for that port (<lang>/vX.Y.Z)
  REGISTRY  the latest version live on the port's package registry (best-effort)
  STATUS    released / publish-pending / unpublished / mismatch

The git tag is this repo's authoritative "released" marker — every port's
`make publish` pushes <lang>/vX.Y.Z — so STATUS is computed from LOCAL vs TAG;
REGISTRY is an independent cross-check.

Stdlib only; runs on Python 3.9+. Network lookups time out quickly and degrade
to '?' so the report always prints. Pass --no-net to skip them entirely.

Usage:
    python3 tools/release_status.py [--no-net]
"""

from __future__ import annotations

import glob
import json
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TIMEOUT = 6
NET = "--no-net" not in sys.argv
UA = {"User-Agent": "voxgig-struct-release-status"}

# port, version-source, registry-kind, registry-id
#   version-source: ("file", path) whole file | ("re", path, pat) | ("glob", pat, re)
PORTS = [
    ("typescript", ("re", "typescript/package.json", r'"version"\s*:\s*"([^"]+)"'), "npm", "@voxgig/struct"),
    ("javascript", ("re", "javascript/package.json", r'"version"\s*:\s*"([^"]+)"'), "npm", "@voxgig/structjs"),
    ("python", ("re", "python/pyproject.toml", r'(?m)^version\s*=\s*"([^"]+)"'), "pypi", "voxgig-struct"),
    ("go", ("file", "go/VERSION"), "go", "github.com/voxgig/struct/go"),
    ("ruby", ("re", "ruby/voxgig_struct.gemspec", r"version\s*=\s*['\"]([^'\"]+)"), "rubygems", "voxgig_struct"),
    ("rust", ("re", "rust/Cargo.toml", r'(?m)^version\s*=\s*"([^"]+)"'), "crates", "voxgig-struct"),
    ("csharp", ("glob", "csharp/*.csproj", r"<Version>([^<]+)</Version>"), "nuget", "Voxgig.Struct"),
    ("perl", ("re", "perl/lib/Voxgig/Struct.pm", r"VERSION\s*=\s*['\"]v?([0-9][^'\"]*)"), "cpan", "Voxgig-Struct"),
    ("java", ("re", "java/pom.xml", r"<version>([^<]+)</version>"), "maven", "com.voxgig:struct-java"),
    ("kotlin", ("re", "kotlin/build.gradle.kts", r'version\s*=\s*"([^"]+)"'), "maven", "com.voxgig:struct-kotlin"),
    # capture only the version, dropping the rockspec "-<rev>" suffix (0.1.0-1 -> 0.1.0)
    ("lua", ("re", "lua/struct.rockspec", r'version\s*=\s*"([0-9.]+)'), "luarocks", "rjrodger/voxgig-struct"),
    ("php", ("file", "php/VERSION"), "tag", None),
    ("zig", ("re", "zig/build.zig.zon", r'\.version\s*=\s*"([^"]+)"'), "tag", None),
    ("c", ("file", "c/VERSION"), "tag", None),
    ("cpp", ("file", "cpp/VERSION"), "tag", None),
    ("swift", ("file", "swift/VERSION"), "tag", None),
    ("clojure", ("file", "clojure/VERSION"), "clojars", "com.voxgig/struct-clojure"),
    ("ocaml", ("file", "ocaml/VERSION"), "tag", None),
    ("scala", ("file", "scala/VERSION"), "maven", "com.voxgig:struct-scala_3"),
    ("dart", ("re", "dart/pubspec.yaml", r'(?m)^version:\s*([0-9][^\s]*)'), "pub", "voxgig_struct"),
    ("elixir", ("file", "elixir/VERSION"), "hex", "voxgig_struct"),
    ("haskell", ("file", "haskell/VERSION"), "hackage", "voxgig-struct"),
]


def local_version(src) -> str:
    """Extract the manifest version for a port, or '?' if it can't be read."""
    kind = src[0]
    try:
        if kind == "file":
            return (ROOT / src[1]).read_text().strip()
        if kind == "re":
            m = re.search(src[2], (ROOT / src[1]).read_text())
            return m.group(1) if m else "?"
        if kind == "glob":
            for p in glob.glob(str(ROOT / src[1])):
                m = re.search(src[2], Path(p).read_text())
                if m:
                    return m.group(1)
        return "?"
    except OSError:
        return "?"


def git_tags() -> dict:
    """Map port -> {full, ver, date} for the latest <lang>/vX.Y.Z tag.

    Dates come from local annotated tags (when the release was cut); a
    remote-only tag with no local copy gets date '?'.
    """
    latest: dict = {}
    # Local tags carry the publish timestamp (annotated tagger date, or the
    # commit date for a lightweight tag).
    fmt = "%(refname:short)\t%(taggerdate:format:%Y-%m-%d %H:%M:%S)\t%(creatordate:format:%Y-%m-%d %H:%M:%S)"
    for ln in run(["git", "for-each-ref", "refs/tags/", "--format=" + fmt]).splitlines():
        parts = ln.split("\t")
        if len(parts) >= 3:
            _add_tag(latest, parts[0].strip(), parts[1].strip() or parts[2].strip() or "?")
    # Remote tags catch anything not present locally (no date available).
    if NET:
        for ln in run(["git", "ls-remote", "--tags", "origin"]).splitlines():
            if "refs/tags/" in ln:
                _add_tag(latest, ln.split("refs/tags/")[-1].replace("^{}", "").strip(), "?")
    return latest


def _add_tag(latest: dict, full: str, date: str) -> None:
    """Record `full` (e.g. 'go/v0.1.3') as a port's latest tag, keeping the
    highest version; an earlier dated entry wins over a later dateless one."""
    m = re.match(r"^([a-z+]+)/v(.+)$", full)
    if not m:
        return
    port, ver = m.group(1), m.group(2)
    cur = latest.get(port)
    if cur is None or vkey(ver) > vkey(cur["ver"]):
        latest[port] = {"full": full, "ver": ver, "date": date}


def registry_version(kind: str, ident) -> str:
    """Best-effort latest version from the port's package registry, or a short
    label naming how the port is distributed when there is nothing to query
    (tag-only ports, --no-net, or a registry we don't auto-check)."""
    if kind == "tag":
        return "git-tag"        # no package registry — the git tag IS the release
    if not NET:
        return "(offline)"      # --no-net: registries not queried
    if ident is None:
        return f"({kind})"      # lives on this registry, but we don't auto-query it (luarocks)
    try:
        if kind == "npm":
            d = fetch(f"https://registry.npmjs.org/{ident.replace('/', '%2F')}/latest")
            return d["version"]
        if kind == "pypi":
            return fetch(f"https://pypi.org/pypi/{ident}/json")["info"]["version"]
        if kind == "rubygems":
            return fetch(f"https://rubygems.org/api/v1/gems/{ident}.json")["version"]
        if kind == "go":
            return fetch(f"https://proxy.golang.org/{ident}/@latest")["Version"].lstrip("v")
        if kind == "crates":
            return fetch(f"https://crates.io/api/v1/crates/{ident}")["crate"]["max_stable_version"]
        if kind == "nuget":
            return fetch(f"https://api.nuget.org/v3-flatcontainer/{ident.lower()}/index.json")["versions"][-1]
        if kind == "maven":
            # Maven Central metadata is XML, not JSON — fetch raw and pull <release>.
            g, a = ident.split(":")
            return maven_metadata_version(f"https://repo1.maven.org/maven2/{g.replace('.', '/')}/{a}")
        if kind == "clojars":
            # Clojars is a Maven repo; same metadata format, coords are group/artifact.
            g, a = ident.split("/")
            return maven_metadata_version(f"https://repo.clojars.org/{g.replace('.', '/')}/{a}")
        if kind == "pub":
            return fetch(f"https://pub.dev/api/packages/{ident}")["latest"]["version"]
        if kind == "hex":
            return fetch(f"https://hex.pm/api/packages/{ident}")["latest_stable_version"]
        if kind == "hackage":
            # /package/<name>.json -> {"0.1.0": "normal", "0.0.9": "deprecated"}.
            # Take the highest version still "normal" (published, not deprecated).
            d = fetch(f"https://hackage.haskell.org/package/{ident}.json")
            normal = [v for v, s in d.items() if s == "normal"]
            return max(normal, key=vkey) if normal else "absent"
        if kind == "luarocks":
            # luarocks.org has no JSON API; parse the owner's Lua-table manifest.
            # ident is "<user>/<rock>". Scope to the rock's block (its 3-space-
            # indented ["name"] key, up to the next such key), take the highest
            # version, and drop the rockspec "-<rev>" suffix (0.1.0-1 -> 0.1.0)
            # so the column matches LOCAL/TAG.
            user, rock = ident.split("/", 1)
            text = fetch_text(f"https://luarocks.org/manifests/{user}/manifest")
            i = text.find(f'["{rock}"]')
            if i < 0:
                return "absent"
            nxt = re.search(r'\n {3}\["', text[i + 1:])
            block = text[i: i + 1 + nxt.start()] if nxt else text[i:]
            vers = re.findall(r'\["(\d[^"]*)"\]', block)
            return max((v.split("-")[0] for v in vers), key=vkey) if vers else "absent"
        if kind == "cpan":
            # MetaCPAN reports Perl versions v-prefixed ("v0.1.0"); strip it so
            # the REGISTRY column matches LOCAL/TAG (which are plain "0.1.0").
            return str(fetch(f"https://fastapi.metacpan.org/v1/release/{ident}")["version"]).lstrip("v")
    except (urllib.error.HTTPError,) as e:
        return "absent" if e.code == 404 else "?"
    except Exception:
        return "?"
    return "?"  # unrecognized kind


def fetch(url: str):
    # URLs come only from the hardcoded https registry endpoints in
    # registry_version() (no user input). Reject any non-https scheme
    # defensively so urllib can never be steered at file:// or similar.
    if not url.startswith("https://"):
        raise ValueError("refusing non-https url")
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:  # nosemgrep  # noqa: S310
        return json.load(r)


def fetch_text(url: str) -> str:
    # Same hardcoded-https guard as fetch(), but returns the raw body (for XML
    # endpoints like Maven Central's maven-metadata.xml).
    if not url.startswith("https://"):
        raise ValueError("refusing non-https url")
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:  # nosemgrep  # noqa: S310
        return r.read().decode("utf-8", "replace")


def maven_metadata_version(base: str) -> str:
    """Latest <release> (else <latest>) from a Maven-style repo's
    maven-metadata.xml at <base>/maven-metadata.xml (Maven Central, Clojars)."""
    xml = fetch_text(f"{base}/maven-metadata.xml")
    m = re.search(r"<release>([^<]+)</release>", xml) or re.search(r"<latest>([^<]+)</latest>", xml)
    return m.group(1) if m else "absent"


def run(args) -> str:
    try:
        return subprocess.run(args, cwd=ROOT, capture_output=True, text=True, timeout=20).stdout
    except Exception:
        return ""


def vkey(v: str):
    """Sortable key from the numeric components of a version string."""
    return tuple(int(n) for n in re.findall(r"\d+", v)) or (0,)


def status(local: str, tag, reg: str) -> str:
    if not tag:
        return "unpublished"
    if vkey(local) > vkey(tag):
        return "publish-pending"  # local manifest is ahead of the latest tag
    if vkey(local) < vkey(tag):
        return "tag>local!"
    # local == tag: the release is tagged. A registry we actually queried can
    # still lag (npm/nuget/pypi/cpan/crates/hackage index asynchronously) — that
    # surfaces as "absent"/"?". Everything else — a version match, a tag-only
    # "git-tag", or a not-queried registry label like "(luarocks)"/"(offline)" —
    # means the tag IS the release, so: released.
    if reg in ("absent", "?"):
        return "pending-index"
    return "released"


def main() -> int:
    tags = git_tags()
    hdr = ("PORT", "LOCAL", "TAG", "PUBLISHED", "REGISTRY", "STATUS")
    rows = []
    json_rows = []
    for name, src, kind, ident in PORTS:
        loc = local_version(src)
        t = tags.get(name)
        reg = registry_version(kind, ident)
        st = status(loc, t["ver"] if t else None, reg)
        rows.append((name, loc, t["full"] if t else "—", t["date"] if t else "—", reg, st))
        json_rows.append({
            "port": name, "local": loc,
            "tag": t["full"] if t else None, "published": t["date"] if t else None,
            "registry_kind": kind, "registry": reg, "status": st,
        })

    if "--json" in sys.argv:
        print(json.dumps(json_rows, indent=2))
        return 0

    rows.sort(key=lambda r: r[0])  # alphabetical by port name
    cols = len(hdr)
    w = [max(len(str(r[i])) for r in rows + [hdr]) for i in range(cols)]
    print("  ".join(h.ljust(w[i]) for i, h in enumerate(hdr)))
    print("  ".join("-" * w[i] for i in range(cols)))
    for r in rows:
        print("  ".join(str(c).ljust(w[i]) for i, c in enumerate(r)))

    c = lambda s: sum(1 for r in rows if r[-1] == s)  # noqa: E731
    parts = [f"{c('released')} released"]
    if c("pending-index"):
        parts.append(f"{c('pending-index')} pending-index")
    if c("publish-pending"):
        parts.append(f"{c('publish-pending')} publish-pending")
    parts.append(f"{c('unpublished')} unpublished")
    print("\n" + " · ".join(parts)
          + ("" if NET else "  (--no-net: tags from local only, registries skipped)"))
    print("REGISTRY: a version = live on the registry · git-tag = no registry, "
          "released via the git tag · (name) = on that registry, not auto-checked · "
          "absent/? = queried, not indexed yet")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
