#!/usr/bin/env python3
"""One-shot patcher: insert the new RE2-coverage $LIKE tests into
build/test/test.json right after the existing $LIKE entry in
select.operators. The .jsonic source has already been updated; this
keeps the compiled JSON in sync without running the model toolchain.
"""

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEST_JSON = ROOT / "build/test/test.json"

NEW_TESTS = [
    {"in": {"query": {"s": {"`$LIKE`": "hello"}},
            "obj": [{"s": "say hello world"}, {"s": "goodbye"}]},
     "out": [{"s": "say hello world", "$KEY": 0}]},
    {"in": {"query": {"s": {"`$LIKE`": "^cat"}},
            "obj": [{"s": "cat sat"}, {"s": "a cat"}]},
     "out": [{"s": "cat sat", "$KEY": 0}]},
    {"in": {"query": {"s": {"`$LIKE`": "end$"}},
            "obj": [{"s": "the end"}, {"s": "ended here"}]},
     "out": [{"s": "the end", "$KEY": 0}]},
    {"in": {"query": {"s": {"`$LIKE`": "^abc$"}},
            "obj": [{"s": "abc"}, {"s": "abcd"}, {"s": "xabc"}]},
     "out": [{"s": "abc", "$KEY": 0}]},
    {"in": {"query": {"s": {"`$LIKE`": "^a.c$"}},
            "obj": [{"s": "abc"}, {"s": "aXc"}, {"s": "ac"}]},
     "out": [{"s": "abc", "$KEY": 0}, {"s": "aXc", "$KEY": 1}]},
    {"in": {"query": {"s": {"`$LIKE`": "^ab*c$"}},
            "obj": [{"s": "ac"}, {"s": "abc"}, {"s": "abbbc"}, {"s": "abdc"}]},
     "out": [{"s": "ac", "$KEY": 0}, {"s": "abc", "$KEY": 1}, {"s": "abbbc", "$KEY": 2}]},
    {"in": {"query": {"s": {"`$LIKE`": "^ab+c$"}},
            "obj": [{"s": "ac"}, {"s": "abc"}, {"s": "abbbc"}]},
     "out": [{"s": "abc", "$KEY": 1}, {"s": "abbbc", "$KEY": 2}]},
    {"in": {"query": {"s": {"`$LIKE`": "^colou?r$"}},
            "obj": [{"s": "color"}, {"s": "colour"}, {"s": "colouur"}]},
     "out": [{"s": "color", "$KEY": 0}, {"s": "colour", "$KEY": 1}]},
    {"in": {"query": {"s": {"`$LIKE`": "^a{3}$"}},
            "obj": [{"s": "aa"}, {"s": "aaa"}, {"s": "aaaa"}]},
     "out": [{"s": "aaa", "$KEY": 1}]},
    {"in": {"query": {"s": {"`$LIKE`": "^a{2,4}$"}},
            "obj": [{"s": "a"}, {"s": "aa"}, {"s": "aaa"}, {"s": "aaaa"}, {"s": "aaaaa"}]},
     "out": [{"s": "aa", "$KEY": 1}, {"s": "aaa", "$KEY": 2}, {"s": "aaaa", "$KEY": 3}]},
    {"in": {"query": {"s": {"`$LIKE`": "^a{2,}$"}},
            "obj": [{"s": "a"}, {"s": "aa"}, {"s": "aaa"}]},
     "out": [{"s": "aa", "$KEY": 1}, {"s": "aaa", "$KEY": 2}]},
    {"in": {"query": {"s": {"`$LIKE`": "^[abc]$"}},
            "obj": [{"s": "a"}, {"s": "b"}, {"s": "c"}, {"s": "d"}]},
     "out": [{"s": "a", "$KEY": 0}, {"s": "b", "$KEY": 1}, {"s": "c", "$KEY": 2}]},
    {"in": {"query": {"s": {"`$LIKE`": "^[^xyz]$"}},
            "obj": [{"s": "a"}, {"s": "x"}, {"s": "y"}]},
     "out": [{"s": "a", "$KEY": 0}]},
    {"in": {"query": {"s": {"`$LIKE`": "^[0-9]+$"}},
            "obj": [{"s": "123"}, {"s": "12a"}, {"s": ""}]},
     "out": [{"s": "123", "$KEY": 0}]},
    {"in": {"query": {"s": {"`$LIKE`": "^\\d{3}$"}},
            "obj": [{"s": "123"}, {"s": "12"}, {"s": "abc"}]},
     "out": [{"s": "123", "$KEY": 0}]},
    {"in": {"query": {"s": {"`$LIKE`": "^\\w+$"}},
            "obj": [{"s": "abc_123"}, {"s": "hi there"}]},
     "out": [{"s": "abc_123", "$KEY": 0}]},
    {"in": {"query": {"s": {"`$LIKE`": "^a\\sb$"}},
            "obj": [{"s": "a b"}, {"s": "a\tb"}, {"s": "ab"}]},
     "out": [{"s": "a b", "$KEY": 0}, {"s": "a\tb", "$KEY": 1}]},
    {"in": {"query": {"s": {"`$LIKE`": "^\\D+$"}},
            "obj": [{"s": "abc"}, {"s": "a1"}]},
     "out": [{"s": "abc", "$KEY": 0}]},
    {"in": {"query": {"s": {"`$LIKE`": "^(cat|dog)$"}},
            "obj": [{"s": "cat"}, {"s": "dog"}, {"s": "fish"}]},
     "out": [{"s": "cat", "$KEY": 0}, {"s": "dog", "$KEY": 1}]},
    {"in": {"query": {"s": {"`$LIKE`": "^(?:ab|cd)+$"}},
            "obj": [{"s": "ab"}, {"s": "abcd"}, {"s": "abcdab"}, {"s": "abc"}]},
     "out": [{"s": "ab", "$KEY": 0}, {"s": "abcd", "$KEY": 1}, {"s": "abcdab", "$KEY": 2}]},
    {"in": {"query": {"s": {"`$LIKE`": "^a(bc)+d$"}},
            "obj": [{"s": "abcd"}, {"s": "abcbcd"}, {"s": "ad"}]},
     "out": [{"s": "abcd", "$KEY": 0}, {"s": "abcbcd", "$KEY": 1}]},
    {"in": {"query": {"s": {"`$LIKE`": "\\bword\\b"}},
            "obj": [{"s": "a word here"}, {"s": "sword"}, {"s": "word!"}]},
     "out": [{"s": "a word here", "$KEY": 0}, {"s": "word!", "$KEY": 2}]},
    {"in": {"query": {"s": {"`$LIKE`": "^a\\.b$"}},
            "obj": [{"s": "a.b"}, {"s": "aXb"}]},
     "out": [{"s": "a.b", "$KEY": 0}]},
    {"in": {"query": {"s": {"`$LIKE`": "^a.*?b$"}},
            "obj": [{"s": "ab"}, {"s": "aXXXb"}, {"s": "aXY"}]},
     "out": [{"s": "ab", "$KEY": 0}, {"s": "aXXXb", "$KEY": 1}]},
]


def main() -> int:
    d = json.loads(TEST_JSON.read_text())
    ops = d["struct"]["select"]["operators"]["set"]
    # Find the existing LIKE entry and insert after it (only once).
    insert_at = None
    for i, t in enumerate(ops):
        if not isinstance(t, dict):
            continue
        q = t.get("in", {}).get("query", {})
        if isinstance(q, dict) and "s0" in q and isinstance(q["s0"], dict) and "`$LIKE`" in q["s0"]:
            insert_at = i + 1
            break
    if insert_at is None:
        print("could not find anchor LIKE test", file=sys.stderr)
        return 1
    # Skip if already patched (look for one of the new patterns in the next entries).
    for j in range(insert_at, min(insert_at + 24, len(ops))):
        if isinstance(ops[j], dict):
            q = ops[j].get("in", {}).get("query", {})
            if isinstance(q, dict) and "s" in q and isinstance(q["s"], dict) and q["s"].get("`$LIKE`") == "hello":
                print("test.json already patched")
                return 0
    ops[insert_at:insert_at] = NEW_TESTS
    TEST_JSON.write_text(json.dumps(d, indent=2) + "\n")
    print(f"inserted {len(NEW_TESTS)} new LIKE tests at index {insert_at}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
