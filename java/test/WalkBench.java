// Benchmark for Struct.walk() on wide and deep trees.
//
// Not run by default. Enable with the WALK_BENCH=1 environment variable:
//
//   WALK_BENCH=1 java -cp build WalkBench
//
// Compile (no package, matches Struct.java):
//   mkdir -p build
//   javac -d build src/Struct.java test/WalkBench.java
//
// When WALK_BENCH is unset or not "1", main() exits immediately.

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class WalkBench {

    // Build a balanced tree of maps with given width and depth.
    // Total nodes: (width^(depth+1) - 1) / (width - 1).
    static Object buildTree(int width, int depth) {
        if (depth == 0) {
            return Integer.valueOf(0);
        }
        Map<String, Object> out = new HashMap<>(width * 2);
        for (int i = 0; i < width; i++) {
            out.put("k" + i, buildTree(width, depth - 1));
        }
        return out;
    }

    static long countNodes(Object val) {
        if (!(val instanceof Map) && !(val instanceof List)) {
            return 1L;
        }
        long n = 1L;
        if (val instanceof Map) {
            for (Object v : ((Map<?, ?>) val).values()) {
                n += countNodes(v);
            }
        } else {
            for (Object v : ((List<?>) val)) {
                n += countNodes(v);
            }
        }
        return n;
    }

    static void measure(String label, Object tree, int runs) {
        final long[] sink = new long[] { 0L };
        Struct.WalkApply cb = (key, val, parent, path) -> {
            // Touch path length to simulate a minimal consumer.
            sink[0] += path.size();
            return val;
        };

        // Warm-up.
        for (int i = 0; i < 2; i++) {
            Struct.walk(tree, cb, null, null, null);
        }

        double[] times = new double[runs];
        for (int r = 0; r < runs; r++) {
            long t0 = System.nanoTime();
            Struct.walk(tree, cb, null, null, null);
            long t1 = System.nanoTime();
            times[r] = (t1 - t0) / 1.0e6; // ms
        }
        java.util.Arrays.sort(times);
        double median = times[times.length / 2];
        double min = times[0];
        double max = times[times.length - 1];
        double sum = 0.0;
        for (double t : times) sum += t;
        double mean = sum / times.length;

        long nodes = countNodes(tree);
        double nsPerNode = (median * 1.0e6) / nodes;

        System.out.printf(
            "[walk-bench] %s: nodes=%d runs=%d min=%.2fms median=%.2fms mean=%.2fms max=%.2fms ns/node=%.1f sink=%d%n",
            label, nodes, runs, min, median, mean, max, nsPerNode, sink[0]
        );
    }

    public static void main(String[] args) {
        String flag = System.getenv("WALK_BENCH");
        if (flag == null || !flag.equals("1")) {
            System.out.println("[walk-bench] skipped (set WALK_BENCH=1 to run)");
            return;
        }

        // ~299k nodes: width=8, depth=6.
        Object wideDeep = buildTree(8, 6);
        measure("wide+deep (w=8,d=6)", wideDeep, 7);

        // ~1,001,001 nodes: width=1000, depth=2. Shallow and very wide.
        Object wide = buildTree(1000, 2);
        measure("wide (w=1000,d=2)", wide, 7);

        // ~2,097,151 nodes: width=2, depth=20. Narrow and deep.
        Object deep = buildTree(2, 20);
        measure("deep (w=2,d=20)", deep, 5);
    }
}
