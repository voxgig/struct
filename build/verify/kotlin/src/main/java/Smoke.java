// Universal struct smoke: getpath({ db: { host: "localhost" } }, "db.host").
// Struct is a Kotlin `object`, so from Java it's reached via INSTANCE.
import voxgig.struct.Struct;

import java.util.Map;

public final class Smoke {
  private Smoke() {
  }

  public static void main(String[] args) {
    Object got = Struct.INSTANCE.getpath(Map.of("db", Map.of("host", "localhost")), "db.host");
    if ("localhost".equals(got)) {
      System.out.println("OK kotlin: getpath(db.host) = localhost");
      return;
    }
    throw new IllegalStateException("FAIL kotlin: getpath(db.host) = " + got + " (want localhost)");
  }
}
