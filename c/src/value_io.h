/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
 *
 * Voxgig Struct — JSON I/O bridge.
 *
 * Uses cJSON only as a text parser/serialiser. Runtime values use vs_value.
 */

#ifndef VOXGIG_STRUCT_VALUE_IO_H
#define VOXGIG_STRUCT_VALUE_IO_H

#include "value.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Parse a JSON text. Returns a new vs_value (owned by caller). */
vs_value* vs_parse_json(const char* text, size_t len);

/* Parse a JSON file. */
vs_value* vs_parse_json_file(const char* path);

/* Serialise to JSON text. Returns malloc'd string the caller must free(). */
char* vs_to_json(const vs_value* v);

#ifdef __cplusplus
}
#endif

#endif
