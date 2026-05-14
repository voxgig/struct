// Constants — mirror typescript/src/StructUtility.ts. Kept in canonical
// SCREAMING_SNAKE so cross-port grepping is easy.

import Foundation

// MARK: - Injection modes

public let M_KEYPRE = 1
public let M_KEYPOST = 2
public let M_VAL = 4

public let MODENAME: [Int: String] = [
  M_KEYPRE: "key:pre",
  M_KEYPOST: "key:post",
  M_VAL: "val",
]

// MARK: - Backtick-quoted command names

public let S_BKEY = "`$KEY`"
public let S_BANNO = "`$ANNO`"
public let S_BEXACT = "`$EXACT`"
public let S_BVAL = "`$VAL`"
public let S_BOPEN = "`$OPEN`"

// MARK: - Annotation keys

public let S_DKEY = "$KEY"
public let S_DTOP = "$TOP"
public let S_DERRS = "$ERRS"
public let S_DSPEC = "$SPEC"
public let S_DMETA = "$META"

// MARK: - Type names (used by typename / typify)

public let S_list = "list"
public let S_base = "base"
public let S_boolean = "boolean"
public let S_function = "function"
public let S_symbol = "symbol"
public let S_instance = "instance"
public let S_key = "key"
public let S_any = "any"
public let S_nil = "nil"
public let S_null = "null"
public let S_number = "number"
public let S_object = "object"
public let S_string = "string"
public let S_decimal = "decimal"
public let S_integer = "integer"
public let S_map = "map"
public let S_scalar = "scalar"
public let S_node = "node"

// MARK: - Single-character / punctuation strings

public let S_BT = "`"
public let S_CN = ":"
public let S_CS = "]"
public let S_DS = "$"
public let S_DT = "."
public let S_FS = "/"
public let S_KEY = "KEY"
public let S_MT = ""
public let S_OS = "["
public let S_SP = " "
public let S_CM = ","
public let S_VIZ = ": "

// MARK: - Type bit-flags
//
// Same numeric layout as the canonical TS: T_any is all-bits-below set;
// the others are distinct bits decreasing down the list (the order
// matches TYPENAME below for table-driven lookup).

public let T_any: Int = (1 << 13) - 1
public let T_noval: Int = 1 << 13
public let T_boolean: Int = 1 << 12
public let T_decimal: Int = 1 << 11
public let T_integer: Int = 1 << 10
public let T_number: Int = 1 << 9
public let T_string: Int = 1 << 8
public let T_function: Int = 1 << 7
public let T_symbol: Int = 1 << 6
public let T_null: Int = 1 << 5
public let T_list: Int = 1 << 4
public let T_map: Int = 1 << 3
public let T_instance: Int = 1 << 2
public let T_scalar: Int = 1 << 1
public let T_node: Int = 1 << 0

public let TYPENAME: [Int: String] = [
  T_noval: S_nil,
  T_boolean: S_boolean,
  T_decimal: S_decimal,
  T_integer: S_integer,
  T_number: S_number,
  T_string: S_string,
  T_function: S_function,
  T_symbol: S_symbol,
  T_null: S_null,
  T_list: S_list,
  T_map: S_map,
  T_instance: S_instance,
  T_scalar: S_scalar,
  T_node: S_node,
]

// MARK: - Regex patterns

public let R_INTEGER_KEY = try! NSRegularExpression(pattern: #"^-?[0-9]+$"#)
public let R_META_PATH = try! NSRegularExpression(pattern: #"^([^$]+)\$([=~])(.+)$"#)
public let R_INJECTION_FULL = try! NSRegularExpression(pattern: #"^`(\$[A-Z]+|[^`]*)[0-9]*`$"#)
public let R_INJECTION_PARTIAL = try! NSRegularExpression(pattern: #"`([^`]+)`"#)
public let R_TRANSFORM_NAME = try! NSRegularExpression(pattern: #"`\$([A-Z]+)`"#)

public let MAXDEPTH = 32
