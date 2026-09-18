# Source code comment policy

Adapted from [Aontu ADR-032](https://github.com/aontu-lang/aontu/blob/main/ADR.md#adr-032--code-comments-are-sparse-and-terse-intent-lives-in-names-requirements-live-in-documents).

Comments are sparse and terse. Use them only for intricate or surprising code:
why an unobvious form is necessary, or what a maintainer could otherwise break.
Prefer a precise identifier, named constant, or extracted function to an
explanation of what the code does. Business rules and requirements belong in
documents. History belongs in commit messages and issues.

A line or two is the norm. Delete redundant or stale comments; move durable
explanations into a design document. A coverage exclusion still needs its short
justification. Paths, backticked symbols, and ADR numbers must resolve. Avoid
issue numbers, dates, versions, unverifiable counts, TODO narratives, and
commented-out code. These rules apply to authored code in every language.

## Automated enforcement

`make comments` runs `tools/comment-gate.cjs`. `make comments-test` runs its
positive and negative tests, including the repository gate. CI runs both on
pushes and pull requests. `make hooks` installs the tracked pre-push hook;
Node.js and Git are required, and a missing Node.js fails the hook.

The automated scope covers `.ts`, `.go`, `.rs`, `.aon`, and `.aontu`, including
authored models, test corpora and generator templates. Other languages follow
the written policy through review. JavaScript build/release tooling is outside
the automated scope, as in Aontu. Tracked and unignored new files are checked;
symlinks, dependency directories, compiled output and Rust build artifacts are
not. `tools/comment-scope.json` lists any additional exclusions with reasons.
License notices and compiler, lint, formatting and coverage directives remain.
Generator slot and insertion markers (such as `<[SLOT]>`, `#SecretsImport`, and `EJECT-START`/`EJECT-END`)
are executable tooling directives and are exempt too.
Aontu models use `#` line comments; quoted strings and multiline backtick values
are preserved. Authored `model/target/` files are included. Generated model
goldens are excluded explicitly through `excludeModels` in the scope config;
this does not exclude implementation files in the same directories.

| Rule | Rejected content |
| --- | --- |
| `long-block` | More than 5 consecutive comment lines |
| `dense-file` | More than 12% comment/code lines, when comment lines exceed 8 |
| `narrative` | First person, change history, reviews, issues, commits, TODOs |
| `requirements` | Requirement and business-rule vocabulary |
| `commented-code` | Disabled source code |
| `count-claim`, `dated-claim`, `issue-ref`, `version-claim` | Unverifiable claims |
| `stale-path`, `stale-symbol`, `stale-adr` | Unresolved references |

The checker uses lexical heuristics; passing it does not establish the truth
of every sentence. Review still checks meaning and whether a comment is needed.
`node tools/comment-gate.cjs --json` emits findings with a failing exit status;
`--measure` prints statistics. There is no baseline that accepts existing debt.
