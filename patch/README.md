# patch/

One patch this session could not push itself.

`.github/workflows/` is refused to this session on both write paths — git
push rejects it (`refusing to allow an OAuth App to create or update
workflow ... without workflow scope`) and the GitHub App's file API fails on
the same path while writing every other file fine. The change below is
mostly a workflow change, so it is delivered as a patch instead.

Delete this folder once the patch is applied. The repository's release
targets check for a clean tree — `make publish-all` refuses to run against
`git status --porcelain` output — so leaving it behind untracked would block
a release; and once the patch has landed the file is only a duplicate of the
history it created.

## 0001-publish-one-tag-scheme-for-every-port.patch

Gives typescript the same tag scheme as every other port and every sibling
repository: `typescript/v<version>` in place of the bare `v<version>`.

```sh
# From this branch, streamed so it survives the checkout: shell redirection
# is resolved BEFORE `git am` runs, so `git am < patch/...` from `main`
# looks for a file that only exists here and fails.
git fetch origin claude/struct-tag-scheme-patch
git checkout main && git pull
git show origin/claude/struct-tag-scheme-patch:patch/0001-publish-one-tag-scheme-for-every-port.patch | git am
```

Or copy it out first, then apply it from anywhere:

```sh
git show origin/claude/struct-tag-scheme-patch:patch/0001-publish-one-tag-scheme-for-every-port.patch > /tmp/tagscheme.patch
git checkout main && git pull && git am < /tmp/tagscheme.patch
```

Six files:

| file | change |
|---|---|
| `.github/workflows/publish.yml` | push trigger `v*` → `typescript/v*`, the job selector, and the four places that compose the tag |
| `tools/bump.py` | drops the typescript special case (`"v"` → `"typescript/v"`) |
| `typescript/package.json` | the `repo-tag` npm script, which cut the bare tag too |
| `AGENTS.md` | the release table's typescript row, what the `@voxgig/struct-js` section says about its trusted publisher, and the paragraphs that existed to explain the inconsistency |
| `Makefile`, `design/PUBLISH_AUTOMATION.md` | the same, where they repeat it |

**Apply it whole.** `tools/bump.py` composes the tag that `publish.yml`'s
trigger listens for, so landing the tooling half alone would cut
`typescript/v0.3.5` at a workflow still waiting on `v*` — a tag push that
publishes nothing, silently.

### Why it is worth doing

`tools/release_status.py` reads a port's release marker by matching
`^([a-z+]+)/v`. A bare tag does not match, so it dropped every typescript
release and reported the port at `typescript/v0.2.1` — a stale tag from an
old Makefile publish — while 0.3.4 was live on npm. The repository also cut
the same release under two different tags depending on the path taken:
`publish.yml` wrote `v<version>`, `typescript/Makefile` wrote
`typescript/v<version>`, and the `repo-tag` npm script wrote the bare one
again.

### What it deliberately leaves alone

The 16 bare tags stay, up to and including `v0.3.4`: they are what those
releases went out under. The new namespace starts at the first release cut
after the patch lands, and `typescript/package.json` is held at 0.3.4 here
so that release belongs with a real change rather than with this one.

Until then `tools/bump.py` reports 0.3.4 as untagged. That is accurate — no
`typescript/v0.3.4` exists — and it self-corrects the moment the first
release is cut under the new scheme. Backfilling that tag was not possible
from this session either: tag pushes are refused the same way.
