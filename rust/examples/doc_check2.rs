use voxgig_struct::{
    jsonify, select, stringify, transform, validate, walk, InjectDef, JsonFlags, Value,
};

fn main() {
    let data = Value::map_of([
        ("name".into(), Value::str("Ada")),
        ("age".into(), Value::Num(36.0)),
    ]);

    // transform example
    let spec = Value::map_of([("name".into(), Value::str("`name`"))]);
    let _ = transform(&data, &spec, None).unwrap();

    // validate + errs collector via InjectDef
    let errs = Value::empty_list();
    let def = InjectDef {
        errs: Some(errs.clone()),
        ..Default::default()
    };
    let vspec = Value::map_of([
        ("name".into(), Value::str("`$STRING`")),
        ("age".into(), Value::str("`$INTEGER`")),
    ]);
    validate(&data, &vspec, Some(&def)).ok();

    // walk with after callback
    let tree = Value::map_of([("k".into(), Value::Null)]);
    let mut after = |_k: &Value, val: &Value, _p: &Value, _path: &[String]| {
        if val.is_null() {
            Value::str("DEFAULT")
        } else {
            val.clone()
        }
    };
    let _ = walk(tree, None, Some(&mut after), None);

    // select
    let children = Value::list(vec![Value::map_of([("age".into(), Value::Num(30.0))])]);
    let _ = select(
        &children,
        &Value::map_of([("age".into(), Value::Num(30.0))]),
    );

    // jsonify / stringify
    let _ = jsonify(&data, None);
    let _ = jsonify(
        &data,
        Some(&JsonFlags {
            indent: 0,
            offset: 0,
        }),
    );
    let _ = stringify(&data, Some(80), false);

    // custom transform func via extra
    let sum = Value::func(|_inj, val, _ref, _store| val.clone());
    let def2 = InjectDef {
        extra: Some(Value::map_of([("sum".into(), sum)])),
        ..Default::default()
    };
    let _ = transform(&data, &spec, Some(&def2)).unwrap();

    // get_path with array path
    let store = Value::map_of([("a.b".into(), Value::map_of([("c".into(), Value::Num(1.0))]))]);
    let _ = voxgig_struct::get_path(
        &store,
        &Value::list(vec![Value::str("a.b"), Value::str("c")]),
        None,
    );

    println!("doc_check2 OK");
}
