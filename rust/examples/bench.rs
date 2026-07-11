// Performance bench for the Rust port. Emits one JSON line per
// build/bench/README.md; diagnostics go to stderr.
// Run: cargo run --release --example bench
use std::hint::black_box;
use std::time::Instant;

use voxgig_struct::{clone, get_path, merge, stringify, walk, Value};

fn envi(k: &str, d: i64) -> i64 {
    std::env::var(k).ok().and_then(|v| v.parse().ok()).unwrap_or(d)
}

fn build(w: i64, d: i64, leaf: i64) -> Value {
    if d == 0 {
        return Value::from(leaf);
    }
    Value::map_of((0..w).map(|i| (format!("k{}", i), build(w, d - 1, leaf))))
}

fn nodecount(w: i64, d: i64) -> i64 {
    let (mut n, mut p) = (0i64, 1i64);
    for _ in 0..=d {
        n += p;
        p *= w;
    }
    n
}

// (min, median, mean) in ms.
fn measure(warm: i64, runs: i64, mut f: impl FnMut()) -> (f64, f64, f64) {
    for _ in 0..warm {
        f();
    }
    let mut t: Vec<f64> = Vec::with_capacity(runs as usize);
    for _ in 0..runs {
        let a = Instant::now();
        f();
        t.push(a.elapsed().as_nanos() as f64 / 1e6);
    }
    t.sort_by(|x, y| x.partial_cmp(y).unwrap());
    let sum: f64 = t.iter().sum();
    (t[0], t[t.len() / 2], sum / t.len() as f64)
}

fn op_json(op: &str, runs: i64, uc: i64, t: (f64, f64, f64)) -> String {
    format!(
        "{{\"op\":\"{}\",\"runs\":{},\"unit_count\":{},\"min_ms\":{},\"median_ms\":{},\"mean_ms\":{}}}",
        op, runs, uc, t.0, t.1, t.2
    )
}

fn main() {
    let w = envi("BENCH_WIDTH", 5);
    let d = envi("BENCH_DEPTH", 6);
    let warm = envi("BENCH_WARMUP", 3);
    let runs = envi("BENCH_RUNS", 21);
    let gp = envi("BENCH_GETPATH_ITERS", 50000);

    let tree = build(w, d, 0);
    let nodes = nodecount(w, d);
    let mlist = Value::list(vec![build(w, d, 1), build(w, d, 2)]);
    let path = Value::str(
        std::iter::repeat("k0").take(d as usize).collect::<Vec<_>>().join("."),
    );

    let t_clone = measure(warm, runs, || {
        black_box(clone(black_box(&tree)));
    });
    let t_walk = measure(warm, runs, || {
        let mut cb = |_k: &Value, v: &Value, _p: &Value, path: &[String]| -> Value {
            black_box(path.len());
            v.clone()
        };
        black_box(walk(tree.clone(), Some(&mut cb), None, None));
    });
    let t_merge = measure(warm, runs, || {
        black_box(merge(black_box(&mlist), None));
    });
    let t_stringify = measure(warm, runs, || {
        black_box(stringify(black_box(&tree), None, false));
    });
    let t_getpath = measure(warm, runs, || {
        let mut s = 0usize;
        for _ in 0..gp {
            let r = get_path(&tree, &path, None);
            s += black_box(&r).is_noval() as usize;
        }
        black_box(s);
    });

    eprintln!("rust: done");
    let runtime = std::env::var("BENCH_RUSTC").unwrap_or_else(|_| "rustc".into());
    let ops = [
        op_json("clone", runs, nodes, t_clone),
        op_json("walk", runs, nodes, t_walk),
        op_json("merge", runs, nodes, t_merge),
        op_json("stringify", runs, nodes, t_stringify),
        op_json("getpath", runs, gp, t_getpath),
    ]
    .join(",");
    println!(
        "{{\"lang\":\"rust\",\"runtime\":\"{}\",\"nodes\":{},\"params\":{{\"width\":{},\"depth\":{},\"warmup\":{},\"runs\":{},\"getpath_iters\":{}}},\"ops\":[{}]}}",
        runtime, nodes, w, d, warm, runs, gp, ops
    );
}
