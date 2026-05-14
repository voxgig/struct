// Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
// VERSION: @voxgig/struct 0.1.0
//
// String, type-bitflag, mode, and regex constants — port of the top of
// StructUtility.ts. The bitfield type is `u32` (TS uses `(1<<31)-1` which
// overflows a signed 32-bit int).

#![allow(non_upper_case_globals)] // S_* string constants mirror the TS names

use crate::re::Regex;
use std::sync::LazyLock as Lazy;

// ---- mode flags (bitfield) for inject steps ---------------------------
pub const M_KEYPRE: i64 = 1;
pub const M_KEYPOST: i64 = 2;
pub const M_VAL: i64 = 4;

// ---- special strings --------------------------------------------------
pub const S_BKEY: &str = "`$KEY`";
pub const S_BANNO: &str = "`$ANNO`";
pub const S_BEXACT: &str = "`$EXACT`";
pub const S_BVAL: &str = "`$VAL`";
pub const S_BOPEN: &str = "`$OPEN`";

pub const S_DKEY: &str = "$KEY";
pub const S_DTOP: &str = "$TOP";
pub const S_DERRS: &str = "$ERRS";
pub const S_DSPEC: &str = "$SPEC";

// general
pub const S_base: &str = "base";
pub const S_key: &str = "key";
pub const S_nil: &str = "nil";
pub const S_null: &str = "null";
pub const S_string: &str = "string";
pub const S_object: &str = "object";
pub const S_list: &str = "list";
pub const S_map: &str = "map";

// chars
pub const S_BT: &str = "`";
pub const S_CN: &str = ":";
pub const S_DS: &str = "$";
pub const S_DT: &str = ".";
pub const S_FS: &str = "/";
pub const S_KEY: &str = "KEY";
pub const S_MT: &str = "";
pub const S_SP: &str = " ";
pub const S_CM: &str = ",";
pub const S_VIZ: &str = ": ";

// ---- type bit codes (u32) ---------------------------------------------
// let t = 31; T_any = (1<<t--)-1; ... (see StructUtility.ts).
pub const T_ANY: u32 = (1u32 << 31) - 1; // 0x7FFF_FFFF
pub const T_NOVAL: u32 = 1 << 30; // property absent, undefined. NOT a scalar.
pub const T_BOOLEAN: u32 = 1 << 29;
pub const T_DECIMAL: u32 = 1 << 28;
pub const T_INTEGER: u32 = 1 << 27;
pub const T_NUMBER: u32 = 1 << 26;
pub const T_STRING: u32 = 1 << 25;
pub const T_FUNCTION: u32 = 1 << 24;
pub const T_SYMBOL: u32 = 1 << 23;
pub const T_NULL: u32 = 1 << 22; // the actual JSON null value.
                                 // t -= 7  => t = 14
pub const T_LIST: u32 = 1 << 14;
pub const T_MAP: u32 = 1 << 13;
pub const T_INSTANCE: u32 = 1 << 12;
// t -= 4  => t = 7
pub const T_SCALAR: u32 = 1 << 7;
pub const T_NODE: u32 = 1 << 6;

// TYPENAME indexed by Math.clz32(t). 26 entries (0..=25).
pub const TYPENAME: [&str; 26] = [
    "any",      // 0
    "nil",      // 1   clz32(T_noval=1<<30)
    "boolean",  // 2   clz32(1<<29)
    "decimal",  // 3   clz32(1<<28)
    "integer",  // 4   clz32(1<<27)
    "number",   // 5   clz32(1<<26)
    "string",   // 6   clz32(1<<25)
    "function", // 7   clz32(1<<24)
    "symbol",   // 8   clz32(1<<23)
    "null",     // 9   clz32(1<<22)
    "", "", "", "", "", "", "",         // 10..=16
    "list",     // 17  clz32(1<<14)
    "map",      // 18  clz32(1<<13)
    "instance", // 19  clz32(1<<12)
    "", "", "", "",       // 20..=23
    "scalar", // 24  clz32(1<<7)
    "node",   // 25  clz32(1<<6)
];

pub const MAXDEPTH: i64 = 32;

// ---- regexes ----------------------------------------------------------
pub static R_INTEGER_KEY: Lazy<Regex> = Lazy::new(|| Regex::new(r"^[-0-9]+$").unwrap());
pub static R_ESCAPE_REGEXP: Lazy<Regex> = Lazy::new(|| Regex::new(r"[.*+?^${}()|\[\]\\]").unwrap());
pub static R_QUOTES: Lazy<Regex> = Lazy::new(|| Regex::new(r#"""#).unwrap());
pub static R_DOT: Lazy<Regex> = Lazy::new(|| Regex::new(r"\.").unwrap());
pub static R_CLONE_REF: Lazy<Regex> = Lazy::new(|| Regex::new(r"^`\$REF:([0-9]+)`$").unwrap());
pub static R_META_PATH: Lazy<Regex> = Lazy::new(|| Regex::new(r"^([^$]+)\$([=~])(.+)$").unwrap());
pub static R_TRANSFORM_NAME: Lazy<Regex> = Lazy::new(|| Regex::new(r"`\$([A-Z]+)`").unwrap());
pub static R_INJECTION_FULL: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"^`(\$[A-Z]+|[^`]*)[0-9]*`$").unwrap());
pub static R_INJECTION_PARTIAL: Lazy<Regex> = Lazy::new(|| Regex::new(r"`([^`]+)`").unwrap());

pub fn mode_name(mode: i64) -> &'static str {
    match mode {
        M_VAL => "val",
        M_KEYPRE => "key:pre",
        M_KEYPOST => "key:post",
        _ => "",
    }
}

pub fn placement_name(mode: i64) -> &'static str {
    match mode {
        M_VAL => "value",
        M_KEYPRE | M_KEYPOST => "key",
        _ => "",
    }
}
