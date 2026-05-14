// Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
// VERSION: @voxgig/struct 0.1.0
//
// Voxgig Struct — Rust port of the canonical TypeScript implementation
// (ts/src/StructUtility.ts). See rs/PLAN.md for the porting plan and the
// list of deliberate divergences (idiomatic snake_case names, Rc<RefCell>
// reference-stable nodes, merge as a direct recursion, ...).

#![allow(clippy::too_many_arguments)]

pub mod consts;
pub mod re;
pub mod value;

mod major;
mod mini;

pub use value::{Sentinel, Value, DELETE, SKIP};

pub use consts::{
    M_KEYPOST, M_KEYPRE, M_VAL, T_ANY, T_BOOLEAN, T_DECIMAL, T_FUNCTION, T_INSTANCE, T_INTEGER,
    T_LIST, T_MAP, T_NODE, T_NOVAL, T_NULL, T_NUMBER, T_SCALAR, T_STRING, T_SYMBOL,
};

pub use mini::{
    clone, del_prop, esc_re, esc_url, filter, filter_vals, flatten, get_def, get_elem,
    get_elem_or_else, get_prop, has_key, is_empty, is_func, is_key, is_list, is_map, is_node,
    items, jm, join, join_vals, jsonify, jt, keys_of, keysof_vec, pad, pathify, set_prop, size,
    slice, str_key, stringify, type_name, typify,
};

pub use major::{
    check_placement, get_path, get_path_inj, inject, inject_child, injector_args, merge, select,
    set_path, transform, validate, walk, Inj, InjectDef, Injection, Modify, NativeFn, WalkClosure,
};

pub use mini::JsonFlags;

/// Error raised by `transform` / `validate` when no error collector was
/// supplied (mirrors the TS `throw new Error(errs.join(' | '))`).
#[derive(Debug, Clone)]
pub struct StructError {
    pub message: String,
}

impl std::fmt::Display for StructError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}

impl std::error::Error for StructError {}

/// Bundle of all functions, mirroring the TS `StructUtility` class. Useful
/// for the test harness (which looks subjects up by name).
pub struct StructUtility;

impl StructUtility {
    pub fn new() -> Self {
        StructUtility
    }
}

impl Default for StructUtility {
    fn default() -> Self {
        StructUtility
    }
}
