// Discovery test: pathological regex inputs run against the port's re_* API.
// Goal is to surface failures across ports, not to assert behaviour.
// Panel is the same in every port (see REGEX.md).

use std::panic;
use std::time::Instant;

use voxgig_struct::{re_compile, re_find, re_find_all, re_replace, re_test};

fn record<F, R>(label: &str, fn_: F)
where
    F: FnOnce() -> R + panic::UnwindSafe,
    R: std::fmt::Debug,
{
    let t0 = Instant::now();
    let outcome = match panic::catch_unwind(fn_) {
        Ok(r) => format!("OK | {:?}", r),
        Err(e) => {
            let msg = if let Some(s) = e.downcast_ref::<&str>() {
                s.to_string()
            } else if let Some(s) = e.downcast_ref::<String>() {
                s.clone()
            } else {
                "<non-string panic>".to_string()
            };
            format!("ERR | panic: {}", msg)
        }
    };
    let ms = t0.elapsed().as_secs_f64() * 1000.0;
    println!("[regex-discovery] {} | {:.2}ms | {}", label, ms, outcome);
}

#[test]
fn regex_pathological_discovery() {
    let a22: String = "a".repeat(22);
    let nest40: String = "(".repeat(40) + "a" + &")".repeat(40);

    record("P1_redos_nested_plus", || {
        re_test("^(a+)+$", &(a22.clone() + "!"))
    });
    record("P2_redos_alt_overlap", || {
        re_test("^(a|aa)+$", &(a22.clone() + "!"))
    });
    record("P3_empty_repeat_replace", || {
        re_replace("a*", "abc", "X")
    });
    record("P4_unicode_replace_dot", || {
        re_replace(r"\.", "café.au.lait", "/")
    });
    record("P5_unicode_find_codepoint", || {
        re_find("é", "café au lait")
    });
    record("P6_deep_nesting_compile", || re_test(&nest40, "a"));
    record("P7_big_bounded_quantifier", || {
        re_test("^a{0,10000}b$", &("a".repeat(10) + "b"))
    });
    record("P8_invalid_pattern", || {
        re_compile("[abc").map(|_| ()).err().map(|e| format!("{:?}", e))
    });
    record("P9_backref_re2_forbidden", || {
        re_test(r"^(a+)\1$", "aaaa")
    });
    record("P10_find_all_zero_width", || re_find_all("a*", "bbb"));
}
