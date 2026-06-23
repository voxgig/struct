# Smoke test for the Python test provider port. Prints summary stats that must
# match the canonical TS output documented in PROVIDER work.

from provider import (
    TestProvider,
    equal,
    equal_strict,
    error_matches,
    struct_match,
)


def main() -> None:
    prov = TestProvider.load()

    fns = prov.functions()
    print('functions:', ', '.join(fns))

    total = 0
    expect_kinds: dict[str, int] = {}
    input_kinds: dict[str, int] = {}
    for fn in fns:
        for entry in prov.entries(fn):
            total += 1
            ek = entry['expect']['kind']
            ik = entry['input']['kind']
            expect_kinds[ek] = expect_kinds.get(ek, 0) + 1
            input_kinds[ik] = input_kinds.get(ik, 0) + 1

    print('total entries:', total)
    print(
        'expect kinds:',
        ', '.join(f'{k}={expect_kinds[k]}' for k in sorted(expect_kinds)),
    )
    print(
        'input kinds:',
        ', '.join(f'{k}={input_kinds[k]}' for k in sorted(input_kinds)),
    )

    e = prov.entries('getpath', 'basic')[0]
    print(
        'getpath/basic[0]:',
        f"id={e['id']}, doc={e['doc']}, "
        f"input.kind={e['input']['kind']}, input.in={e['input']['in']}, "
        f"expect.kind={e['expect']['kind']}, expect.value={e['expect']['value']}",
    )

    # ─── helper sanity checks ──────────────────────────────────────────────
    print('equal(None, missing) lenient:', equal(None, {}.get('x')))
    print(
        'equal_strict distinguishes None vs __NULL__-collapse:',
        equal_strict(None, '__NULL__'), '/', equal_strict(None, 1),
    )
    print(
        'error_matches substring case-insensitive:',
        error_matches({'any': False, 'text': 'Foo', 'regex': False}, 'a foobar error'),
    )
    sm = struct_match({'a': {'b': 2}}, {'a': {'b': 3}})
    print('struct_match failure:', sm)


if __name__ == '__main__':
    main()
