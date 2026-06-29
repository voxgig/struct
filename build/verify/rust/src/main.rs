use std::process::exit;

use voxgig_struct::{get_path, Value};

fn main() {
    let store = Value::map_of([(
        "db".to_string(),
        Value::map_of([("host".to_string(), Value::str("localhost"))]),
    )]);

    let got = get_path(&store, &Value::str("db.host"), None);

    if got == Value::str("localhost") {
        println!("OK rust: getpath(db.host) = localhost");
        exit(0);
    }

    println!("FAIL rust: getpath(db.host) = {:?} (want localhost)", got);
    exit(1);
}
