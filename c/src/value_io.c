/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE. */

#include "value_io.h"

#include <cjson/cJSON.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static vs_value* from_cjson(const cJSON* j) {
  if (!j)
    return vs_new_undef();
  if (cJSON_IsNull(j))
    return vs_new_null();
  if (cJSON_IsBool(j))
    return vs_new_bool(cJSON_IsTrue(j));
  if (cJSON_IsNumber(j)) {
    double d = j->valuedouble;
    /* Distinguish integer-valued from non-integer. */
    if (isfinite(d) && floor(d) == d && d >= (double)INT64_MIN && d <= (double)INT64_MAX) {
      return vs_new_int((int64_t)d);
    }
    return vs_new_double(d);
  }
  if (cJSON_IsString(j)) {
    return vs_new_string(j->valuestring ? j->valuestring : "");
  }
  if (cJSON_IsArray(j)) {
    vs_value* lv = vs_new_list();
    const cJSON* it = NULL;
    cJSON_ArrayForEach(it, j) {
      vs_list_push(vs_as_list(lv), from_cjson(it));
    }
    return lv;
  }
  if (cJSON_IsObject(j)) {
    vs_value* mv = vs_new_map();
    const cJSON* it = NULL;
    cJSON_ArrayForEach(it, j) {
      vs_map_set(vs_as_map(mv), it->string ? it->string : "", from_cjson(it));
    }
    return mv;
  }
  return vs_new_undef();
}

vs_value* vs_parse_json(const char* text, size_t len) {
  (void)len;
  cJSON* j = cJSON_Parse(text ? text : "null");
  if (!j)
    return vs_new_undef();
  vs_value* v = from_cjson(j);
  cJSON_Delete(j);
  return v;
}

vs_value* vs_parse_json_file(const char* path) {
  FILE* f = fopen(path, "rb");
  if (!f)
    return vs_new_undef();
  fseek(f, 0, SEEK_END);
  long sz = ftell(f);
  fseek(f, 0, SEEK_SET);
  if (sz < 0) {
    fclose(f);
    return vs_new_undef();
  }
  char* buf = (char*)malloc((size_t)sz + 1);
  if (!buf) {
    fclose(f);
    return vs_new_undef();
  }
  size_t rd = fread(buf, 1, (size_t)sz, f);
  buf[rd] = '\0';
  fclose(f);
  vs_value* v = vs_parse_json(buf, rd);
  free(buf);
  return v;
}

static cJSON* to_cjson(const vs_value* v) {
  if (!v)
    return cJSON_CreateNull();
  switch (v->kind) {
  case VS_VAL_UNDEF:
    return cJSON_CreateNull();
  case VS_VAL_NULL:
    return cJSON_CreateNull();
  case VS_VAL_BOOL:
    return cJSON_CreateBool(vs_as_bool(v));
  case VS_VAL_INT: {
    cJSON* j = cJSON_CreateNumber((double)vs_as_int(v));
    if (j)
      j->valueint = (int)vs_as_int(v);
    return j;
  }
  case VS_VAL_DOUBLE:
    return cJSON_CreateNumber(vs_as_double(v));
  case VS_VAL_STRING:
    return cJSON_CreateString(vs_as_string(v));
  case VS_VAL_LIST: {
    cJSON* arr = cJSON_CreateArray();
    vs_list* l = vs_as_list(v);
    for (size_t i = 0; i < vs_list_len(l); i++) {
      cJSON_AddItemToArray(arr, to_cjson(vs_list_get(l, i)));
    }
    return arr;
  }
  case VS_VAL_MAP: {
    cJSON* obj = cJSON_CreateObject();
    vs_map* m = vs_as_map(v);
    for (size_t i = 0; i < vs_map_len(m); i++) {
      cJSON_AddItemToObject(obj, vs_map_key_at(m, i), to_cjson(vs_map_val_at(m, i)));
    }
    return obj;
  }
  case VS_VAL_FUNC:
    return cJSON_CreateString("[Function]");
  case VS_VAL_SENTINEL: {
    cJSON* obj = cJSON_CreateObject();
    const vs_sentinel* s = vs_as_sentinel(v);
    char key[32];
    snprintf(key, sizeof(key), "`$%s`", s->name);
    cJSON_AddBoolToObject(obj, key, true);
    return obj;
  }
  }
  return cJSON_CreateNull();
}

char* vs_to_json(const vs_value* v) {
  cJSON* j = to_cjson(v);
  char* out = cJSON_PrintUnformatted(j);
  cJSON_Delete(j);
  return out;
}
