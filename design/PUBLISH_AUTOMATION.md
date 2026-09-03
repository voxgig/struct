# Publishing every port from CI

> A plan for releasing all 23 ports from GitHub Actions rather than from
> whichever laptop is to hand. For how publishing works today see the
> release section of the repository's agent notes and
> [`.github/workflows/publish.yml`](../.github/workflows/publish.yml); for
> per-port status see [`REPORT.md`](REPORT.md).
>
> Registry capabilities verified 2026-09-03. Four registries added trusted
> publishing in the two years before that, so re-check the ones marked
> unverified before implementing them.


## Why

A local `make publish-all` stalls on credentials, which is the expected
outcome: thirteen registries each want their own auth, present on whichever
machine happens to be running the release. In CI the credentials live in one
place — and for most of them, nowhere at all.

**14 of the 23 ports need no stored credential.** Seven have no registry, so
the git tag is the release. Seven more can use trusted publishing, where the
registry verifies a short-lived GitHub identity token and the trust lives on
the registry side, keyed to this repository and this workflow filename.


## Three tiers of credential

| Tier | Ports | What it needs |
|---|---|---|
| No credential | 7 — go, php, c, cpp, swift, zig, lean | the built-in `GITHUB_TOKEN` pushes the tag |
| Trusted publishing | 7 — typescript, javascript, rust, python, ruby, csharp, dart | `id-token: write`, and a publisher registered registry-side |
| Long-lived secret | 9 — java, kotlin, scala, perl, lua, clojure, elixir, haskell, ocaml | a token in repository secrets, plus a GPG key for Maven |


## The matrix

| Port | Registry | Auth | Mechanism | One-time setup |
|---|---|---|---|---|
| typescript | npm `@voxgig/struct` | live | OIDC | done |
| rust | crates.io `voxgig-struct` | live | OIDC | done |
| javascript | npm `@voxgig/struct-js` | OIDC | OIDC | register publisher — outstanding |
| python | PyPI `voxgig-struct` | OIDC | `pypa/gh-action-pypi-publish` | add trusted publisher |
| ruby | RubyGems `voxgig_struct` | OIDC | `rubygems/release-gem` | add trusted publisher |
| csharp | NuGet `Voxgig.Struct` | OIDC | `NuGet/login@v1` | add publishing policy |
| dart | pub.dev `voxgig_struct` | OIDC | `dart pub publish` | enable automated publishing, add a GitHub environment |
| java | Maven Central `struct-java` | secret | Central Portal token + GPG | 4 secrets |
| kotlin | Maven Central `struct-kotlin` | secret | shares java's credentials | — |
| scala | Maven Central `struct-scala_3` | secret | shares java's credentials | — |
| perl | CPAN `Voxgig-Struct` | secret | PAUSE user + password | 2 secrets |
| lua | LuaRocks `voxgig-struct` | secret | `LUAROCKS_API_KEY` | 1 secret |
| clojure | Clojars `struct-clojure` | secret | deploy token | 2 secrets |
| elixir | Hex `voxgig_struct` | secret | `HEX_API_KEY` | 1 secret |
| haskell | Hackage `voxgig-struct` | secret | API token | 1 secret |
| ocaml | opam-repository | secret | token — opens a PR, does not upload | PAT with fork access |
| go php c cpp swift zig lean | none — the tag is the release | tag | `GITHUB_TOKEN` | none |

Trusted publishing confirmed for RubyGems, NuGet, pub.dev and PyPI. Maven
Central confirmed as still token-plus-GPG: Sonatype's Central Portal accepts
Sigstore bundles alongside the PGP signature it still requires, so that is an
addition rather than a replacement. The remaining registries are token-based
as far as could be established; treat those rows as unverified.


## Architecture

Keep the shape `publish.yml` already has. Three of its properties are
load-bearing and should survive the extension:

- **One workflow file.** Every trusted publisher is registered against a
  single filename. A second workflow cannot publish whatever permissions it
  holds — npm reports the rejection as a 404 rather than a 403, so as not to
  leak whether the package exists.
- **Two jobs per port, split by privilege.** The publish job takes
  `id-token: write` and `contents: read`; the tag job takes `contents: write`
  and runs git and nothing else. Together they would hand a repository-write
  credential to every dependency install script that runs during the build.
- **Publish, then tag — not the reverse.** The dispatch path exists so the tag
  job can declare `needs:` the publish job, which means a tag only ever exists
  for a version a consumer can install. Keep it. Making a tag push the
  universal trigger would invert that for every registry port: a tag pushed
  first stays behind whether or not the tests, the token exchange and the
  upload then succeed. That is not hypothetical — `javascript/v0.1.3` sat on
  the repository for hours while npm still served 0.1.2, which is the same
  defect listed under phase 2 below. That instance has since been released;
  the defect it exposed has not been fixed.

**pub.dev is the exception, and stays isolated.** It publishes *only* from a
tag-triggered workflow, so dart alone tags before it publishes and needs its
own recovery path for a tag whose publish then failed. Do not generalise its
constraint to the other twelve registries. The seven registry-less ports tag
first by definition, because there the tag *is* the release.

So the dispatch path keeps its shape, and gains one job pair per port:

```yaml
publish-python:                 # dispatch: target = python
  permissions: { id-token: write, contents: read }
  environment: release          # secrets and required reviewers live here

tag-python:
  needs: publish-python         # the tag cannot exist without the publish
  permissions: { contents: write }
```


## Four phases

Ordered by dependency rather than by size.

1. **Finish what is outstanding.** ✅ for javascript: the npm trusted
   publisher for `@voxgig/struct-js` is registered and 0.1.3 is released, so
   all three OIDC ports now publish the same way. Typescript's tag scheme was
   unified with the rest at the same time — it released under a bare
   `v<version>` up to 0.3.4, which is why `tools/release_status.py` could not
   see any of its releases. The ports left mid-train are still outstanding.
   Nothing is built here; it clears the board so later phases start from a
   known state.
2. **Fix the release-state model.** Automation multiplies whatever the current
   logic gets wrong, so this comes before adding ports. The six defects are
   listed below.
3. **The trusted-publishing ports.** python, ruby, csharp and dart join
   typescript, javascript and rust. Each needs one publisher registered
   registry-side and one job in the workflow. No secret is created, so there is
   nothing to rotate, leak or expire — the highest value per unit of work here.
4. **The secret-bearing ports.** Maven Central first, since java, kotlin and
   scala share one credential set and one GPG key: three ports for one setup.
   Then the single-secret registries — Hex, Hackage, LuaRocks, Clojars, CPAN.
   ocaml last: it opens a pull request against opam-repository rather than
   uploading, so it needs a token with fork access and fails differently from
   everything else.


## What phase 2 has to fix

Six defects in the current release-state model, all of which get worse
unattended when a workflow is driving rather than a person. The first four are
in the release path; the last two are in the dashboard that reports on it, and
they matter here because a dashboard that calls an incomplete release
"released" is how an irreversible one goes unnoticed.

- **Released-ness is read from local tags.** `tools/bump.py` asks
  `git tag -l`, so a successful `git tag` followed by a failed `git push`
  looks released ever after. Read the remote once with
  `git ls-remote --tags` and match against that.
- **A re-run re-releases what already succeeded.** Ports that published get
  bumped again, so retrying one failure ships a new patch of every port that
  worked — irreversibly, for a registry port. Observed: a second
  `publish-all` bumped and re-tagged the five ports that had succeeded in the
  first. Separate "start a train" from "resume a train", or record the plan
  and read it back.
- **ocaml tags before it publishes.** `ocaml/Makefile` pushes the tag, then
  creates the release asset, then submits to opam. A failure after tagging is
  invisible to any tag-existence test, and the Makefile's own comments say to
  re-run `opam publish` in that case.
- **A pushed tag is not a release.** The OIDC path reports success the moment
  the tag lands, while the workflow can still fail at the build, the tests,
  the token exchange or the upload. Observed: `javascript/v0.1.3` existed
  while npm still served 0.1.2, and stayed that way until someone compared the
  registry by hand. Report those ports as pending, or wait on the workflow
  conclusion.
- **The dashboard never compares the registry.** `status()` in
  `tools/release_status.py` reports `released` whenever the manifest and the
  tag agree, treating the registry column as a cross-check rather than an
  input. That is precisely the javascript case above: local 0.1.3, tag
  `javascript/v0.1.3`, npm 0.1.2 — reported as released. Typescript was the
  mirror image until its tags were unified: released on npm, but reported
  years behind because `_add_tag` cannot read a bare `v*` tag.
- **The dashboard has no lean row.** Its `PORTS` table omits `lean` and
  `boru`. `boru` has no publish flow so that is correct; lean does, which is
  why lean sat unreleased at 0.1.0 without ever appearing as pending.


## What stays manual

- **The version bump.** It should remain a reviewable diff on a pull request.
  Automating the release is not the same as automating the decision to
  release.
- **Registry-side trust.** Every trusted publisher is added by a person, once,
  on the registry's own site. That is the point of the design.
- **Moving each secret into GitHub.** For the nine secret-bearing ports the
  registry only *issues* the credential; the workflow cannot read it until it
  is also stored as a repository or environment secret — along with the Maven
  signing key and its passphrase. Generating and storing are two steps, and
  phase 4 stalls at authentication if only the first is done.
- **The first publish of a new package name, on most registries.** npm and the
  others configure a trusted publisher on a package's own settings page, which
  exists only once the package does, so a rename or a new port needs one token
  publish by hand — as `@voxgig/struct-js` did. **PyPI is the exception**: a
  *pending* publisher is registered against a future project name from the
  account sidebar, and the first OIDC publish creates the project. A new
  Python package therefore needs no token at all.
