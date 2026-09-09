# Apply note: publish.yml header, struct-js OIDC status

One patch, carrying one comment-only commit to `.github/workflows/publish.yml`.

```sh
git am < patch/0001-publish-the-struct-js-OIDC-gap-is-closed-so-stop-doc.patch
```

Then delete this folder, in the same commit if you can. AGENTS.md
("`patch/` — a legitimate folder, and a temporary one") says a `patch/` left
on `main` is a bug: once applied the file only duplicates the history it just
created, and a patch that has drifted from `main` is worse than no patch.

## Why it arrives this way

An agent session cannot write `.github/workflows/`. Both write paths refuse
it, exactly as AGENTS.md records — `git push` rejected the ref with

```
refusing to allow an OAuth App to create or update workflow
`.github/workflows/publish.yml` without `workflow` scope
```

and ref deletion returned 403 the same way. So the change could not arrive as
a branch.

## What it touches

`.github/workflows/publish.yml` only, and only comments: 17 lines replace 10
in the header. Verified before hand-off — the file still parses as YAML, all
six jobs (`publish`, `tag`, `publish-javascript`, `tag-javascript`,
`publish-rust`, `tag-rust`) and all three dispatch inputs (`target`,
`expect_sha`, `dry_run`) are unchanged, and every changed line is a comment.
No job, step, guard or permission is altered.

## Why

The header stated that `@voxgig/struct-js` had never published over OIDC, and
that a `target: javascript` dispatch "cannot succeed" until a publisher was
registered. Both were true when written, on 2026-09-03. Neither is true now,
and left as it stood the paragraph tells the next person to cut a release that
the javascript target is blocked — costing them a dispatch to disprove.

What the registry records instead:

| package | first OIDC release | publisher |
| --- | --- | --- |
| `@voxgig/struct` | 0.3.0 | `trustedPublisher: github`, SLSA provenance |
| `@voxgig/struct-js` | 0.1.4, 2026-09-04 (gitHead `224ce10`) | `trustedPublisher: github`, SLSA provenance |

`@voxgig/struct-js@0.1.5` followed on 2026-09-05 from gitHead `f856ceb`.
0.1.2 remains the lone token publish, under a personal account with no
attestation, and 0.1.3 was never published at all.

The replacement keeps the two things in the old paragraph still worth knowing:
npm registers a trusted publisher only against a package that already exists,
which is why a renamed port needs one bootstrap publish first and why 0.1.2
can never gain provenance; and a 404 on the PUT still means the registration
rather than the workflow. It adds the trap this repository actually hit — the
two npm names are registered separately and carry different OIDC config ids,
so `@voxgig/struct` publishing cleanly says nothing about `@voxgig/struct-js`.

## Check it has not already landed

```sh
git apply --check patch/0001-publish-the-struct-js-OIDC-gap-is-closed-so-stop-doc.patch
```

Generated against `main` at `adda952`, where it applies cleanly.
