# Test Provider (prototype) — Python port of the canonical ts/provider.ts.
#
# Reads the shared corpus (build/test/test.json) and hands test code clean,
# normalized cases. It is NOT a test runner: it never calls the subject and
# never asserts. See ../PROVIDER.md for the model and ../AGENTS.md for usage.
#
# Zero runtime dependencies (stdlib only), matching repo policy.

import json
import os
import re
from typing import Any

NULLMARK = '__NULL__'
UNDEFMARK = '__UNDEF__'
EXISTSMARK = '__EXISTS__'

# Sentinel distinguishing "key absent" from "value is None" in getpath.
_MISSING = object()


# Default corpus path: build/test/test.json relative to the repo root.
def default_test_file() -> str:
    here = os.path.dirname(os.path.abspath(__file__))  # test/proto/python
    return os.path.join(here, '..', '..', '..', 'build', 'test', 'test.json')


class TestProvider:

    def __init__(self, spec: Any):
        self.spec = spec

    @classmethod
    def load(cls, testfile: str | None = None) -> 'TestProvider':
        file = testfile if testfile is not None else default_test_file()
        with open(file, encoding='utf-8') as f:
            return cls(json.load(f))

    def raw(self) -> Any:
        return self.spec

    def _fn_node(self, fn: str) -> dict[str, Any]:
        root = self.spec.get('struct') if isinstance(self.spec, dict) else None
        node = None
        if isinstance(root, dict) and fn in root:
            node = root[fn]
        elif isinstance(self.spec, dict) and fn in self.spec:
            node = self.spec[fn]
        if node is None:
            raise ValueError(f'Unknown function: {fn}')
        return node

    def functions(self) -> list[str]:
        root = self.spec.get('struct') if isinstance(self.spec, dict) else None
        if not isinstance(root, dict):
            root = self.spec
        return [k for k in root.keys() if is_group_bag(root[k]) or has_groups(root[k])]

    def groups(self, fn: str) -> list[str]:
        node = self._fn_node(fn)
        return [k for k in node.keys() if k != 'name' and is_group_bag(node[k])]

    def entries(self, fn: str, group: str | None = None) -> list[dict[str, Any]]:
        node = self._fn_node(fn)
        groups = [group] if group is not None else self.groups(fn)
        out: list[dict[str, Any]] = []
        for g in groups:
            bag = node[g]
            if not is_group_bag(bag):
                continue
            test_set = bag['set']
            for i in range(len(test_set)):
                out.append(normalize(fn, g, i, test_set[i]))
        return out


# A group bag is a map with a `set` list.
def is_group_bag(v: Any) -> bool:
    return isinstance(v, dict) and isinstance(v.get('set'), list)


# A function node has at least one child group bag.
def has_groups(v: Any) -> bool:
    return isinstance(v, dict) and any(
        k != 'name' and is_group_bag(v[k]) for k in v.keys()
    )


def normalize(fn: str, group: str, index: int, raw: dict[str, Any]) -> dict[str, Any]:
    return {
        'function': fn,
        'group': group,
        'index': index,
        'id': str(raw['id']) if raw.get('id') is not None else None,
        'doc': raw.get('doc') is True,
        'client': str(raw['client']) if raw.get('client') is not None else None,
        'input': resolve_input(raw),
        'expect': resolve_expect(raw),
        'raw': raw,
    }


def has(raw: dict[str, Any], key: str) -> bool:
    return key in raw


def resolve_input(raw: dict[str, Any]) -> dict[str, Any]:
    if has(raw, 'ctx'):
        return {'kind': 'ctx', 'ctx': raw['ctx']}
    if has(raw, 'args'):
        return {'kind': 'args', 'args': raw['args']}
    return {'kind': 'in', 'in': raw['in'] if has(raw, 'in') else None}


def parse_err(err: Any) -> dict[str, Any]:
    if err is True:
        return {'any': True, 'text': None, 'regex': False}
    if isinstance(err, str):
        m = re.match(r'^/(.+)/$', err)
        if m:
            return {'any': False, 'text': m.group(1), 'regex': True}
        return {'any': False, 'text': err, 'regex': False}
    # Non-true, non-string err spec: treat as "any error".
    return {'any': True, 'text': None, 'regex': False}


def resolve_expect(raw: dict[str, Any]) -> dict[str, Any]:
    match_part = raw['match'] if has(raw, 'match') else None
    if has(raw, 'err'):
        return {'kind': 'error', 'error': parse_err(raw['err']), 'match': match_part}
    if has(raw, 'out'):
        return {'kind': 'value', 'value': raw['out'], 'match': match_part}
    if has(raw, 'match'):
        return {'kind': 'match', 'match': raw['match']}
    return {'kind': 'absent'}


# ─── pure comparison helpers ───────────────────────────────────────────────

def stringify(x: Any) -> str:
    return x if isinstance(x, str) else json.dumps(x)


def _norm_null(x: Any) -> Any:
    if x == NULLMARK or x is None:
        return None
    if isinstance(x, list):
        return [_norm_null(v) for v in x]
    if isinstance(x, dict):
        return {k: _norm_null(v) for k, v in x.items()}
    return x


def matchval(check: Any, base: Any) -> bool:
    if check == base:
        return True
    if isinstance(check, str):
        basestr = stringify(base)
        rem = re.match(r'^/(.+)/$', check)
        if rem:
            return re.search(rem.group(1), basestr) is not None
        return check.lower() in basestr.lower()
    if callable(check):
        return True
    return False


def equal(expected: Any, actual: Any) -> bool:
    return _deep_eq(_norm_null(expected), _norm_null(actual))


# Strict variant for the runner's `{ null: false }` functions, where an absent
# value is distinct from JSON null. Only __NULL__ is normalized.
def equal_strict(expected: Any, actual: Any) -> bool:
    return _deep_eq(_norm_mark(expected), _norm_mark(actual))


def _norm_mark(x: Any) -> Any:
    if x == NULLMARK:
        return None
    if isinstance(x, list):
        return [_norm_mark(v) for v in x]
    if isinstance(x, dict):
        return {k: _norm_mark(v) for k, v in x.items()}
    return x


def _deep_eq(a: Any, b: Any) -> bool:
    # Guard against Python's bool/int equivalence (True == 1) to mirror JS ===.
    if isinstance(a, bool) != isinstance(b, bool):
        return False
    if a is b:
        return True
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(_deep_eq(v, b[i]) for i, v in enumerate(a))
    if isinstance(a, dict) and isinstance(b, dict):
        ak = list(a.keys())
        bk = list(b.keys())
        return len(ak) == len(bk) and all(k in b and _deep_eq(a[k], b[k]) for k in ak)
    if isinstance(a, list) or isinstance(b, list):
        return False
    if isinstance(a, dict) or isinstance(b, dict):
        return False
    return a == b


def error_matches(check: dict[str, Any], message: str) -> bool:
    if check.get('any'):
        return True
    text = check.get('text')
    if text is None:
        return False
    if check.get('regex'):
        return re.search(text, message) is not None
    return text.lower() in message.lower()


# Partial structural match: every leaf of `check` must match `base` at its path.
def struct_match(check: Any, base: Any) -> dict[str, Any]:
    result: dict[str, Any] = {'ok': True}

    def visit(val: Any, path: list[str]) -> None:
        nonlocal result
        if not result['ok']:
            return
        baseval = _getpath(base, path)
        if baseval is not _MISSING and baseval == val:
            return
        if val == UNDEFMARK and baseval is _MISSING:
            return
        if val == EXISTSMARK and baseval is not _MISSING and baseval is not None:
            return
        compare_base = None if baseval is _MISSING else baseval
        if not matchval(val, compare_base):
            result = {'ok': False, 'path': path, 'expected': val, 'actual': compare_base}

    _walk_leaves(check, [], visit)
    return result


def _is_node(v: Any) -> bool:
    return isinstance(v, (dict, list))


def _walk_leaves(node: Any, path: list[str], fn) -> None:
    if isinstance(node, list):
        for i, v in enumerate(node):
            _walk_leaves(v, path + [str(i)], fn)
    elif isinstance(node, dict):
        for k in node.keys():
            _walk_leaves(node[k], path + [k], fn)
    else:
        fn(node, path)


def _getpath(store: Any, path: list[str]) -> Any:
    cur = store
    for key in path:
        if cur is None or cur is _MISSING:
            return _MISSING
        if isinstance(cur, list):
            idx = int(key)
            cur = cur[idx] if 0 <= idx < len(cur) else _MISSING
        elif isinstance(cur, dict):
            cur = cur[key] if key in cur else _MISSING
        else:
            return _MISSING
    return cur
