// Smoke check for the Rust Test Provider port. Loads the corpus and prints a
// summary that must match the canonical TS reference numbers.

use std::collections::BTreeMap;

use structproto::{ExpectKind, InputKind, TestProvider};

fn main() {
    let provider = TestProvider::load(None);

    let functions = provider.functions();
    println!("functions: {}", functions.join(", "));

    let mut total = 0usize;
    let mut expect_counts: BTreeMap<&str, usize> = BTreeMap::new();
    let mut input_counts: BTreeMap<&str, usize> = BTreeMap::new();

    for func in &functions {
        for entry in provider.entries(func, None) {
            total += 1;
            let ek = match entry.expect.kind {
                ExpectKind::Value => "value",
                ExpectKind::Error => "error",
                ExpectKind::Match => "match",
                ExpectKind::Absent => "absent",
            };
            *expect_counts.entry(ek).or_insert(0) += 1;
            let ik = match entry.input.kind {
                InputKind::In => "in",
                InputKind::Args => "args",
                InputKind::Ctx => "ctx",
            };
            *input_counts.entry(ik).or_insert(0) += 1;
        }
    }

    println!("total entries: {}", total);
    println!(
        "expect kinds: value={}, absent={}, match={}, error={}",
        expect_counts.get("value").copied().unwrap_or(0),
        expect_counts.get("absent").copied().unwrap_or(0),
        expect_counts.get("match").copied().unwrap_or(0),
        expect_counts.get("error").copied().unwrap_or(0),
    );
    println!(
        "input kinds: in={}, args={}, ctx={}",
        input_counts.get("in").copied().unwrap_or(0),
        input_counts.get("args").copied().unwrap_or(0),
        input_counts.get("ctx").copied().unwrap_or(0),
    );

    // getpath/basic[0]
    let basic = provider.entries("getpath", Some("basic"));
    let e0 = &basic[0];
    let input_kind = match e0.input.kind {
        InputKind::In => "in",
        InputKind::Args => "args",
        InputKind::Ctx => "ctx",
    };
    let expect_kind = match e0.expect.kind {
        ExpectKind::Value => "value",
        ExpectKind::Error => "error",
        ExpectKind::Match => "match",
        ExpectKind::Absent => "absent",
    };
    println!(
        "getpath/basic[0]: id={}, doc={}, input.kind={}, expect.kind={}, expect.value={}",
        e0.id.as_deref().unwrap_or("<none>"),
        e0.doc,
        input_kind,
        expect_kind,
        e0.expect
            .value
            .as_ref()
            .map(|v| v.to_string())
            .unwrap_or_else(|| "<none>".to_string()),
    );
}
