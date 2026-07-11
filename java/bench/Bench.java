// Performance bench for the Java port. Emits one JSON line per
// build/bench/README.md; diagnostics go to stderr. Uses the default-package
// Struct compiled alongside this file.
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;

import voxgig.struct.Struct;

public class Bench {
    static long sink = 0;

    interface Fn { void run(); }

    static int envi(String k, int d) {
        try { return Integer.parseInt(System.getenv(k)); }
        catch (Exception e) { return d; }
    }

    static Object build(int w, int d, int leaf) {
        if (d == 0) return leaf;
        HashMap<String, Object> m = new HashMap<>();
        for (int i = 0; i < w; i++) m.put("k" + i, build(w, d - 1, leaf));
        return m;
    }

    static long nodecount(int w, int d) {
        long n = 0, p = 1;
        for (int i = 0; i <= d; i++) { n += p; p *= w; }
        return n;
    }

    static double[] measure(int warm, int runs, Fn f) {
        for (int i = 0; i < warm; i++) f.run();
        double[] t = new double[runs];
        for (int r = 0; r < runs; r++) {
            long a = System.nanoTime();
            f.run();
            long b = System.nanoTime();
            t[r] = (b - a) / 1e6;
        }
        Arrays.sort(t);
        double s = 0;
        for (double x : t) s += x;
        return new double[]{t[0], t[runs / 2], s / runs};
    }

    public static void main(String[] args) {
        int W = envi("BENCH_WIDTH", 5), D = envi("BENCH_DEPTH", 6),
            WARM = envi("BENCH_WARMUP", 3), RUNS = envi("BENCH_RUNS", 21),
            GP = envi("BENCH_GETPATH_ITERS", 2000);

        Object tree = build(W, D, 0);
        long nodes = nodecount(W, D);
        Object treeA = build(W, D, 1);
        Object treeB = build(W, D, 2);
        StringBuilder pb = new StringBuilder();
        for (int i = 0; i < D; i++) { if (i > 0) pb.append('.'); pb.append("k0"); }
        String path = pb.toString();

        Struct.WalkApply cb = (key, val, parent, p) -> { sink += p.size(); return val; };

        String[] names = {"clone", "walk", "merge", "stringify", "getpath"};
        long[] ucs = {nodes, nodes, nodes, nodes, GP};
        Fn[] fns = new Fn[]{
            () -> { if (Struct.clone(tree) != null) sink++; },
            () -> Struct.walk(tree, cb),
            () -> {
                List<Object> ml = new ArrayList<>();
                ml.add(treeA); ml.add(treeB);
                if (Struct.merge(ml) != null) sink++;
            },
            () -> { sink += Struct.stringify(tree).length(); },
            () -> {
                long s = 0;
                for (int i = 0; i < GP; i++) if (Struct.getpath(tree, path) != null) s++;
                sink += s;
            },
        };

        StringBuilder ops = new StringBuilder();
        for (int i = 0; i < names.length; i++) {
            double[] m = measure(WARM, RUNS, fns[i]);
            if (i > 0) ops.append(',');
            ops.append(String.format(
                "{\"op\":\"%s\",\"runs\":%d,\"unit_count\":%d,"
                + "\"min_ms\":%s,\"median_ms\":%s,\"mean_ms\":%s}",
                names[i], RUNS, ucs[i], m[0], m[1], m[2]));
        }

        System.err.println("java: sink=" + sink);
        System.out.println(String.format(
            "{\"lang\":\"java\",\"runtime\":\"java %s\",\"nodes\":%d,"
            + "\"params\":{\"width\":%d,\"depth\":%d,\"warmup\":%d,\"runs\":%d,"
            + "\"getpath_iters\":%d},\"ops\":[%s]}",
            System.getProperty("java.version"), nodes, W, D, WARM, RUNS, GP,
            ops.toString()));
    }
}
