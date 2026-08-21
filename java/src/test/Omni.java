/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE. */

package voxgig.struct;

// The shared test runner comes from voxgig/omni, consumed as a local checkout
// - omni is deliberately not published to Maven Central (yet). The checkout is
// resolved the same way voxgig/sekreto's ports resolve it: $OMNI_HOME first,
// then sibling paths, taking the first directory that carries spec/fib.json.
//
// Only the tests depend on omni. The library never does: omni is a test-scoped
// Maven dependency on a system path, so `mvn package` and anything published
// from `src/Struct.java` are untouched (register 4.13).
//
// ---------------------------------------------------------------------------
// The bridge is thin, and deliberately so
// ---------------------------------------------------------------------------
//
// The two value models are ALREADY the same. struct/java parses the corpus
// with Gson and omni-java with its own parser, and both produce
// `Map<String,Object>`, `List<Object>`, `String`, `Boolean`, `Double` and
// null. Numbers agree - unlike go and csharp, where one side had integers -
// so nothing needs renormalising.
//
// One thing differs: omni marks an absent value with `Json.ABSENT` and this
// port with `Struct.UNDEF`.
//
// That matters more than it looks, because it means CONTAINERS CROSS BY
// IDENTITY. The subject receives omni's own map, not a copy of it - so when
// `setpath` rewrites the store in place, omni sees the rewrite and
// `match.args` can assert on it. Eight of `minor/setpath`'s nine entries turn
// on that, and every other statically-typed port had to write the mutation
// back by hand (go, csharp) or could not observe it at all (php, and rust
// until omni gained a mutable-argument subject).
//
// The only conversion is the sentinel, and only where it can actually appear:
// ABSENT reaches a subject just once, as a whole argument, when an entry
// carries no `in` at all. It never appears INSIDE a parsed corpus value -
// parsing produces null, never absent - so there is nothing to walk.

import com.voxgig.omni.Json;
import com.voxgig.omni.Runner;
import com.voxgig.omni.Util;

import java.io.File;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** omni's runner, in the shape this port's tests use. */
public final class Omni {

  private Omni() {}

  /** Value is JSON null. */
  public static final String NULLMARK = "__NULL__";

  /** Value is not present. */
  public static final String UNDEFMARK = "__UNDEF__";

  /** Value exists. */
  public static final String EXISTSMARK = "__EXISTS__";

  /** Locate the voxgig/omni checkout, for the error message if nothing else. */
  public static String omnihome() {
    List<String> candidates = new ArrayList<>();

    String env = System.getenv("OMNI_HOME");
    if (null != env && !env.isEmpty()) {
      candidates.add(env);
    }
    candidates.add("../../omni");
    candidates.add("../../../omni");
    candidates.add("/workspace/omni");
    candidates.add("/home/user/omni");

    for (String candidate : candidates) {
      if (new File(candidate, "spec/fib.json").isFile()) {
        return candidate;
      }
    }

    throw new IllegalStateException("struct: voxgig/omni checkout not found - set OMNI_HOME");
  }

  /** The shared corpus, relative to the port directory as this port's tests run. */
  public static String corpuspath() {
    return new File("..", "build/test/test.json").getPath();
  }

  /**
   * omni's model -> this port's. Only the absent sentinel differs, and it can
   * only be the whole value: a parsed corpus value never contains one.
   */
  public static Object tostruct(Object val) {
    return Util.isabsent(val) ? Struct.UNDEF : val;
  }

  /**
   * This port's model -> omni's. Walked, because {@code Struct.UNDEF} CAN sit
   * inside a result - `getpath` leaves it in a partially-resolved node - and a
   * container built by the port is its own, so rewriting it harms nothing.
   */
  @SuppressWarnings("unchecked")
  public static Object toomni(Object val) {
    if (Struct.UNDEF == val) {
      return Json.ABSENT;
    }
    if (val instanceof Map) {
      Map<String, Object> out = new LinkedHashMap<>();
      for (Map.Entry<String, Object> entry : ((Map<String, Object>) val).entrySet()) {
        out.put(entry.getKey(), toomni(entry.getValue()));
      }
      return out;
    }
    if (val instanceof List) {
      List<Object> out = new ArrayList<>();
      for (Object entry : (List<Object>) val) {
        out.add(toomni(entry));
      }
      return out;
    }
    return val;
  }

  /** A subject in this port's shape: one argument in, one value out. */
  public interface StructSubject {
    Object apply(Object input);
  }

  /** What the runner returns for one named spec section. */
  public static final class Run {
    private final Runner.RunPack pack;

    /** The resolved spec section. */
    public final Object spec;

    private Run(Runner.RunPack pack) {
      this.pack = pack;
      this.spec = pack.spec;
    }

    /** A runner over one section of the shared corpus. */
    public static Run of(String name, Runner.Provider provider) {
      Runner.RunnerPack runner = Runner.makeRunner(corpuspath(), provider);
      return new Run(runner.runner(name));
    }

    /** A runner over the `struct` section, with no provider hooks. */
    public static Run of(String name) {
      return of(name, new Runner.Provider());
    }

    /** A named group of the resolved spec. */
    public Object set(String name) {
      return pack.set(name);
    }

    /** Run one set of entries with omni's default flags. */
    public void runset(Object testspec, StructSubject subject) {
      runsetflags(testspec, null, subject);
    }

    /** Run one set of entries with an explicit `null` flag. */
    public void runsetnull(Object testspec, boolean donull, StructSubject subject) {
      runsetflags(testspec, Runner.flags("null", donull), subject);
    }

    /** Run one set of entries with explicit flags. */
    public void runsetflags(Object testspec, Map<String, Object> flags, StructSubject subject) {
      Runner.Subject wrapped =
          null == subject
              ? null
              : args -> toomni(subject.apply(tostruct(0 < args.length ? args[0] : Json.ABSENT)));
      pack.runsetflags(testspec, null == flags ? new HashMap<>() : flags, wrapped);
    }

    /** Run one set against the subject the spec itself names - the client path. */
    public void runsetnamed(Object testspec, Map<String, Object> flags) {
      pack.runsetflags(testspec, null == flags ? new HashMap<>() : flags, null);
    }
  }
}
