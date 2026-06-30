// Universal struct smoke: getpath({ db: { host: "localhost" } }, "db.host").
// The Scala port's getpath works on its Value ADT, so build VMap/VStr Values
// and unwrap the result. The struct-scala dep is passed by the verify target.
//> using scala 3

import voxgig.struct.*
import scala.collection.mutable.LinkedHashMap

@main def run(): Unit =
  val store = VMap(LinkedHashMap("db" -> VMap(LinkedHashMap("host" -> VStr("localhost")))))
  getpath(store, VStr("db.host")) match
    case VStr("localhost") =>
      println("OK scala: getpath(db.host) = localhost")
    case other =>
      println(s"FAIL scala: getpath(db.host) = $other (want localhost)")
      System.exit(1)
