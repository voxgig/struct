// Smoke client for the PUBLISHED Swift port, built against the source
// vendored from the git tag swift/v<VERSION>. The Makefile compiles this
// together with the vendored swift/Sources/VoxgigStruct/*.swift into one
// executable (no module import needed since everything is one module).
//
// Compiling multiple files together means top-level statements are not
// allowed, so the entry point is an @main struct.

import Foundation

@main
struct Smoke {
    static func main() {
        // store = { db: { host: "localhost" } }
        let store: Value = .map([("db", .map([("host", .string("localhost"))]))])
        let got = getpath(store, .string("db.host"))

        if got == .string("localhost") {
            print("OK swift: getpath(db.host) = localhost")
            exit(0)
        }

        FileHandle.standardError.write(
            "FAIL swift: getpath(db.host) = \(got) (want localhost)\n".data(using: .utf8)!)
        exit(1)
    }
}
