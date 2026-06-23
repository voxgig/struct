// Smoke test for the Java test provider port. Prints summary stats that must
// match the canonical TS output documented in PROVIDER.md.
//
// Run from the repo root:
//   cd test/proto/java && javac *.java && (cd /home/user/struct && java -cp test/proto/java Smoke)

import java.util.List;
import java.util.Map;
import java.util.TreeMap;

public class Smoke {

  public static void main(String[] args) {
    String path = args.length > 0 ? args[0] : "build/test/test.json";
    Provider prov = Provider.load(path);

    List<String> fns = prov.functions();
    System.out.println("functions: " + String.join(", ", fns));

    int total = 0;
    Map<String, Integer> expectKinds = new TreeMap<>();
    Map<String, Integer> inputKinds = new TreeMap<>();
    for (String fn : fns) {
      for (Provider.Entry e : prov.entries(fn, null)) {
        total++;
        String ek = e.expect.kind.name().toLowerCase();
        String ik = e.input.kind.name().toLowerCase();
        expectKinds.merge(ek, 1, Integer::sum);
        inputKinds.merge(ik, 1, Integer::sum);
      }
    }

    System.out.println("total entries: " + total);
    System.out.println("expect kinds: " + joinCounts(expectKinds));
    System.out.println("input kinds: " + joinCounts(inputKinds));

    Provider.Entry e = prov.entries("getpath", "basic").get(0);
    System.out.println(
        "getpath/basic[0]: id="
            + e.id
            + ", doc="
            + e.doc
            + ", input.kind="
            + e.input.kind.name().toLowerCase()
            + ", expect.kind="
            + e.expect.kind.name().toLowerCase()
            + ", expect.value="
            + Provider.stringify(e.expect.value));
  }

  private static String joinCounts(Map<String, Integer> counts) {
    StringBuilder sb = new StringBuilder();
    boolean first = true;
    for (Map.Entry<String, Integer> c : counts.entrySet()) {
      if (!first) {
        sb.append(", ");
      }
      first = false;
      sb.append(c.getKey()).append('=').append(c.getValue());
    }
    return sb.toString();
  }
}
