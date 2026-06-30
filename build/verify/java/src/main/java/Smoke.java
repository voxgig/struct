// Universal struct smoke: getpath({ db: { host: "localhost" } }, "db.host").
import voxgig.struct.Struct;

import java.util.Map;

public final class Smoke {
  private Smoke() {
  }

  public static void main(String[] args) {
    Object got = Struct.getpath(Map.of("db", Map.of("host", "localhost")), "db.host");
    if ("localhost".equals(got)) {
      System.out.println("OK java: getpath(db.host) = localhost");
      return;
    }
    // A throw (not System.exit) so `mvn exec:java` reports a non-zero build.
    throw new IllegalStateException("FAIL java: getpath(db.host) = " + got + " (want localhost)");
  }
}
