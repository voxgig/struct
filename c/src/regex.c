/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
 *
 * Voxgig Struct — RE2-subset regex engine.
 *
 * Approach: parser builds a postfix instruction list, compiler converts to a
 * Thompson NFA, matcher runs two state sets (current/next) per input char.
 * Quantifier bounds (a{n,m}) are unrolled at compile time; captures are
 * tracked via Save instructions tagged with group/slot. Lazy quantifiers
 * swap the order of split branches.
 *
 * No external deps, no host regex.
 *
 * References:
 *   - Russ Cox, "Regular expression matching can be simple and fast"
 *     (the Thompson VM idea this implementation is built around).
 */

#define _POSIX_C_SOURCE 200809L
#include "regex.h"

#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char* re_strdup(const char* s) {
  size_t n = strlen(s);
  char* o = (char*)malloc(n + 1);
  if (!o)
    abort();
  memcpy(o, s, n + 1);
  return o;
}

/* ===========================================================================
 * Instructions
 * ===========================================================================*/

typedef enum {
  OP_CHAR,  /* match one literal char  (data.c)          */
  OP_ANY,   /* . (any char, byte for now)                 */
  OP_CLASS, /* character class                            */
  OP_MATCH, /* accept                                      */
  OP_JMP,   /* unconditional jump to data.x                */
  OP_SPLIT, /* branch: try data.x first, else data.y       */
  OP_SAVE,  /* record offset at slot data.i                */
  OP_BOL,   /* ^                                            */
  OP_EOL,   /* $                                            */
  OP_WB,    /* \b                                           */
  OP_NWB    /* \B                                           */
} voxgig_op;

/* Character class: a bitmap of 256 bits (32 bytes). Negation toggled at
 * compile time by inverting. */
typedef struct {
  uint8_t bits[32];
} voxgig_charclass;

typedef struct voxgig_insn {
  voxgig_op op;
  union {
    int c;    /* char for OP_CHAR */
    int slot; /* slot index for OP_SAVE */
    int jmp;  /* target index for OP_JMP */
    struct {
      int x, y; /* SPLIT targets */
    } split;
    voxgig_charclass cc;
  } data;
} voxgig_insn;

/* ===========================================================================
 * Compiled regex
 * ===========================================================================*/

struct voxgig_regex {
  voxgig_insn* code;
  int code_len;
  int code_cap;
  int ngroups; /* including group 0 */
  /* Pre-computed: does the pattern start with ^? If so we don't try
     each input offset as a potential start. */
  bool anchored_start;
};

static void code_reserve(voxgig_regex* re, int extra) {
  if (re->code_len + extra <= re->code_cap)
    return;
  int nc = re->code_cap == 0 ? 32 : re->code_cap;
  while (nc < re->code_len + extra)
    nc *= 2;
  re->code = (voxgig_insn*)realloc(re->code, (size_t)nc * sizeof(voxgig_insn));
  if (!re->code)
    abort();
  re->code_cap = nc;
}

static int code_emit(voxgig_regex* re, voxgig_op op) {
  code_reserve(re, 1);
  re->code[re->code_len].op = op;
  memset(&re->code[re->code_len].data, 0, sizeof(re->code[0].data));
  return re->code_len++;
}

/* ===========================================================================
 * Character-class helpers
 * ===========================================================================*/

static void cc_zero(voxgig_charclass* cc) {
  memset(cc->bits, 0, sizeof(cc->bits));
}
static void cc_set(voxgig_charclass* cc, int ch) {
  ch &= 0xFF;
  cc->bits[ch >> 3] |= (uint8_t)(1u << (ch & 7));
}
static void cc_set_range(voxgig_charclass* cc, int lo, int hi) {
  if (lo > hi) {
    int t = lo;
    lo = hi;
    hi = t;
  }
  for (int c = lo; c <= hi; c++)
    cc_set(cc, c);
}
static bool cc_has(const voxgig_charclass* cc, int ch) {
  ch &= 0xFF;
  return (cc->bits[ch >> 3] >> (ch & 7)) & 1u;
}
static void cc_negate(voxgig_charclass* cc) {
  for (int i = 0; i < 32; i++)
    cc->bits[i] = (uint8_t)~cc->bits[i];
}
static void cc_predef(voxgig_charclass* cc, int c) {
  switch (c) {
  case 'd':
    cc_set_range(cc, '0', '9');
    break;
  case 'D':
    cc_set_range(cc, 0, 255);
    for (int x = '0'; x <= '9'; x++)
      cc->bits[x >> 3] &= (uint8_t) ~(1u << (x & 7));
    break;
  case 's':
    cc_set(cc, ' ');
    cc_set(cc, '\t');
    cc_set(cc, '\n');
    cc_set(cc, '\r');
    cc_set(cc, '\f');
    cc_set(cc, '\v');
    break;
  case 'S':
    cc_set_range(cc, 0, 255);
    cc->bits[' ' >> 3] &= (uint8_t) ~(1u << (' ' & 7));
    cc->bits['\t' >> 3] &= (uint8_t) ~(1u << ('\t' & 7));
    cc->bits['\n' >> 3] &= (uint8_t) ~(1u << ('\n' & 7));
    cc->bits['\r' >> 3] &= (uint8_t) ~(1u << ('\r' & 7));
    cc->bits['\f' >> 3] &= (uint8_t) ~(1u << ('\f' & 7));
    cc->bits['\v' >> 3] &= (uint8_t) ~(1u << ('\v' & 7));
    break;
  case 'w':
    cc_set_range(cc, '0', '9');
    cc_set_range(cc, 'A', 'Z');
    cc_set_range(cc, 'a', 'z');
    cc_set(cc, '_');
    break;
  case 'W':
    cc_set_range(cc, 0, 255);
    for (int x = '0'; x <= '9'; x++)
      cc->bits[x >> 3] &= (uint8_t) ~(1u << (x & 7));
    for (int x = 'A'; x <= 'Z'; x++)
      cc->bits[x >> 3] &= (uint8_t) ~(1u << (x & 7));
    for (int x = 'a'; x <= 'z'; x++)
      cc->bits[x >> 3] &= (uint8_t) ~(1u << (x & 7));
    cc->bits['_' >> 3] &= (uint8_t) ~(1u << ('_' & 7));
    break;
  default:
    break;
  }
}

/* ===========================================================================
 * Parser
 * ===========================================================================*/

typedef struct {
  const char* src;
  size_t slen;
  size_t pos;
  int next_group; /* group id allocator (0 = whole match) */
  char* err;
  voxgig_regex* re;
} parser;

static void perr(parser* p, const char* msg) {
  if (!p->err) {
    p->err = (char*)malloc(64 + strlen(msg));
    if (p->err)
      snprintf(p->err, 64 + strlen(msg), "regex parse error at %zu: %s", p->pos, msg);
  }
}

static int hexval(int c) {
  if (c >= '0' && c <= '9')
    return c - '0';
  if (c >= 'a' && c <= 'f')
    return 10 + c - 'a';
  if (c >= 'A' && c <= 'F')
    return 10 + c - 'A';
  return -1;
}

/* Parse an escape, returning the byte produced, or -1 if it's a predefined
 * class (and *predef_ch is set to the class letter). For \b / \B the
 * function returns -2 and sets *predef_ch to 'b' / 'B'. */
static int parse_escape(parser* p, int* predef_ch) {
  if (p->pos >= p->slen) {
    perr(p, "trailing backslash");
    return 0;
  }
  int c = (unsigned char)p->src[p->pos++];
  switch (c) {
  case 'n':
    return '\n';
  case 't':
    return '\t';
  case 'r':
    return '\r';
  case 'f':
    return '\f';
  case 'v':
    return '\v';
  case '0':
    return '\0';
  case 'a':
    return '\a';
  case 'e':
    return 27;
  case 'x': {
    if (p->pos + 1 >= p->slen) {
      perr(p, "bad \\xNN");
      return 0;
    }
    int h1 = hexval((unsigned char)p->src[p->pos]);
    int h2 = hexval((unsigned char)p->src[p->pos + 1]);
    if (h1 < 0 || h2 < 0) {
      perr(p, "bad \\xNN");
      return 0;
    }
    p->pos += 2;
    return (h1 << 4) | h2;
  }
  case 'd':
  case 'D':
  case 's':
  case 'S':
  case 'w':
  case 'W':
    *predef_ch = c;
    return -1;
  case 'b':
  case 'B':
    *predef_ch = c;
    return -2;
  default:
    /* Literal escape for metacharacters: \. \* \\ \+ \? \( \) \[ \] \{ \} \| \^ \$ */
    return c;
  }
}

/* Forward decls. */
static int parse_alt(parser* p);

/* Parse a [...] class. Position is just after '['. */
static void parse_class(parser* p, voxgig_charclass* out) {
  cc_zero(out);
  bool neg = false;
  if (p->pos < p->slen && p->src[p->pos] == '^') {
    neg = true;
    p->pos++;
  }
  bool first = true;
  while (p->pos < p->slen && (first || p->src[p->pos] != ']')) {
    first = false;
    int c;
    int predef = 0;
    if (p->src[p->pos] == '\\') {
      p->pos++;
      c = parse_escape(p, &predef);
      if (c == -1) {
        /* predefined class — merge into this class. */
        voxgig_charclass sub;
        cc_zero(&sub);
        cc_predef(&sub, predef);
        for (int i = 0; i < 32; i++)
          out->bits[i] |= sub.bits[i];
        continue;
      }
      if (c == -2) {
        /* \b/\B not valid inside a class; treat as literal 0x08 to mirror
           some engines. */
        c = 8;
      }
    } else {
      c = (unsigned char)p->src[p->pos++];
    }
    /* Possibly a range. */
    if (p->pos + 1 < p->slen && p->src[p->pos] == '-' && p->src[p->pos + 1] != ']') {
      p->pos++; /* eat '-' */
      int hi;
      if (p->src[p->pos] == '\\') {
        p->pos++;
        int hpred = 0;
        hi = parse_escape(p, &hpred);
        if (hi < 0)
          hi = '-';
      } else {
        hi = (unsigned char)p->src[p->pos++];
      }
      cc_set_range(out, c, hi);
    } else {
      cc_set(out, c);
    }
  }
  if (p->pos >= p->slen || p->src[p->pos] != ']') {
    perr(p, "unclosed [");
    return;
  }
  p->pos++;
  if (neg)
    cc_negate(out);
}

/* Parse one atom into the code stream; return index of the first emitted insn. */
static int parse_atom(parser* p) {
  if (p->pos >= p->slen)
    return p->re->code_len;
  int start = p->re->code_len;
  char c = p->src[p->pos];
  if (c == '(') {
    p->pos++;
    bool capture = true;
    int group = 0;
    if (p->pos + 1 < p->slen && p->src[p->pos] == '?' && p->src[p->pos + 1] == ':') {
      capture = false;
      p->pos += 2;
    } else if (p->pos + 2 < p->slen && p->src[p->pos] == '?' && p->src[p->pos + 1] == 'P' &&
               p->src[p->pos + 2] == '<') {
      /* (?P<name>...) — named group. We don't expose names but still capture. */
      p->pos += 3;
      while (p->pos < p->slen && p->src[p->pos] != '>')
        p->pos++;
      if (p->pos < p->slen)
        p->pos++; /* eat '>' */
    }
    if (capture) {
      group = p->next_group++;
      int s1 = code_emit(p->re, OP_SAVE);
      p->re->code[s1].data.slot = group * 2;
    }
    parse_alt(p);
    if (p->pos >= p->slen || p->src[p->pos] != ')') {
      perr(p, "unclosed (");
      return start;
    }
    p->pos++;
    if (capture) {
      int s2 = code_emit(p->re, OP_SAVE);
      p->re->code[s2].data.slot = group * 2 + 1;
    }
  } else if (c == '[') {
    p->pos++;
    int ix = code_emit(p->re, OP_CLASS);
    parse_class(p, &p->re->code[ix].data.cc);
  } else if (c == '.') {
    p->pos++;
    code_emit(p->re, OP_ANY);
  } else if (c == '^') {
    p->pos++;
    code_emit(p->re, OP_BOL);
  } else if (c == '$') {
    p->pos++;
    code_emit(p->re, OP_EOL);
  } else if (c == '\\') {
    p->pos++;
    int predef = 0;
    int e = parse_escape(p, &predef);
    if (e == -1) {
      int ix = code_emit(p->re, OP_CLASS);
      cc_zero(&p->re->code[ix].data.cc);
      cc_predef(&p->re->code[ix].data.cc, predef);
    } else if (e == -2) {
      code_emit(p->re, predef == 'b' ? OP_WB : OP_NWB);
    } else {
      int ix = code_emit(p->re, OP_CHAR);
      p->re->code[ix].data.c = e;
    }
  } else if (c == ')' || c == '|') {
    /* Empty atom — caller handles. */
    return start;
  } else {
    p->pos++;
    int ix = code_emit(p->re, OP_CHAR);
    p->re->code[ix].data.c = (unsigned char)c;
  }
  return start;
}

/* Duplicate the slice [from..to) of code at the current end of the code
 * stream. Returns the new start index. SAVE slots are NOT remapped, but RE2
 * also doesn't capture inside an unrolled iteration cleanly — the typical
 * convention is "last iteration's captures win", which falls out naturally. */
static int code_clone(voxgig_regex* re, int from, int to) {
  int delta = re->code_len - from;
  int start = re->code_len;
  code_reserve(re, to - from);
  for (int i = from; i < to; i++) {
    re->code[re->code_len] = re->code[i];
    /* Patch JMP / SPLIT targets that pointed inside the cloned range. */
    if (re->code[re->code_len].op == OP_JMP) {
      int t = re->code[re->code_len].data.jmp;
      if (t >= from && t < to)
        re->code[re->code_len].data.jmp = t + delta;
    } else if (re->code[re->code_len].op == OP_SPLIT) {
      int x = re->code[re->code_len].data.split.x;
      int y = re->code[re->code_len].data.split.y;
      if (x >= from && x < to)
        re->code[re->code_len].data.split.x = x + delta;
      if (y >= from && y < to)
        re->code[re->code_len].data.split.y = y + delta;
    }
    re->code_len++;
  }
  return start;
}

/* Apply quantifier to the atom occupying code[start..end). end is current
 * code_len when called. The quantifier syntax has been consumed. */
static void apply_quant(parser* p, int start, char q, int n_lo, int n_hi, bool lazy) {
  voxgig_regex* re = p->re;
  int end = re->code_len;
  int alen = end - start;
  if (alen <= 0)
    return;

  if (q == '*' || q == '+' || q == '?') {
    if (q == '?') {
      /* SPLIT before atom, falling through after. */
      /* Insert SPLIT at `start` by shifting. */
      code_reserve(re, 1);
      memmove(&re->code[start + 1], &re->code[start], (size_t)alen * sizeof(voxgig_insn));
      re->code_len++;
      re->code[start].op = OP_SPLIT;
      re->code[start].data.split.x = lazy ? re->code_len : start + 1;
      re->code[start].data.split.y = lazy ? start + 1 : re->code_len;
      /* Patch jmp/split inside the moved block. */
      for (int i = start + 1; i < re->code_len; i++) {
        if (re->code[i].op == OP_JMP)
          re->code[i].data.jmp += 1;
        else if (re->code[i].op == OP_SPLIT) {
          re->code[i].data.split.x += 1;
          re->code[i].data.split.y += 1;
        }
      }
    } else if (q == '*') {
      /* L0: SPLIT L1 L2; atom; JMP L0; L2: */
      code_reserve(re, 2);
      memmove(&re->code[start + 1], &re->code[start], (size_t)alen * sizeof(voxgig_insn));
      re->code_len++;
      re->code[start].op = OP_SPLIT;
      re->code[start].data.split.x = lazy ? re->code_len + 1 : start + 1;
      re->code[start].data.split.y = lazy ? start + 1 : re->code_len + 1;
      for (int i = start + 1; i < re->code_len; i++) {
        if (re->code[i].op == OP_JMP)
          re->code[i].data.jmp += 1;
        else if (re->code[i].op == OP_SPLIT) {
          re->code[i].data.split.x += 1;
          re->code[i].data.split.y += 1;
        }
      }
      int jmpix = code_emit(re, OP_JMP);
      re->code[jmpix].data.jmp = start;
    } else { /* '+' */
      /* atom; SPLIT L0 L1 */
      int spix = code_emit(re, OP_SPLIT);
      re->code[spix].data.split.x = lazy ? re->code_len : start;
      re->code[spix].data.split.y = lazy ? start : re->code_len;
    }
  } else { /* {n,m} unrolling */
    /* Emit n_lo mandatory copies (we have already one — the original atom). */
    /* Use code_clone to duplicate. The original is in [start..end). */
    for (int i = 1; i < n_lo; i++) {
      code_clone(re, start, end);
    }
    if (n_hi == -1) {
      /* {n,} => after n_lo mandatory copies, emit a Kleene star of the atom:
       *   L0: SPLIT(atom, exit)   (swapped for lazy)
       *   L1: <atom clone>
       *       JMP L0
       *   L2: (exit)
       */
      int split_ix = code_emit(re, OP_SPLIT);
      int atom_start = re->code_len;
      code_clone(re, start, end);
      int jmp_ix = code_emit(re, OP_JMP);
      re->code[jmp_ix].data.jmp = split_ix;
      int exit_ix = re->code_len;
      re->code[split_ix].data.split.x = lazy ? exit_ix : atom_start;
      re->code[split_ix].data.split.y = lazy ? atom_start : exit_ix;
    } else if (n_hi > n_lo) {
      /* (n_hi - n_lo) optional copies */
      for (int i = 0; i < n_hi - n_lo; i++) {
        int blk_start = re->code_len;
        int sp = code_emit(re, OP_SPLIT);
        int clone_start = re->code_len;
        code_clone(re, start, end);
        re->code[sp].data.split.x = lazy ? re->code_len : clone_start;
        re->code[sp].data.split.y = lazy ? clone_start : re->code_len;
        (void)blk_start;
      }
    }
  }
}

/* Parse one concatenation (sequence of atoms with quantifiers) until ')' or '|' or end. */
static int parse_concat(parser* p) {
  int start = p->re->code_len;
  while (p->pos < p->slen && p->src[p->pos] != ')' && p->src[p->pos] != '|') {
    int atom_start = parse_atom(p);
    if (p->err)
      return start;
    /* Quantifier? */
    if (p->pos < p->slen) {
      char q = p->src[p->pos];
      if (q == '*' || q == '+' || q == '?') {
        p->pos++;
        bool lazy = false;
        if (p->pos < p->slen && p->src[p->pos] == '?') {
          lazy = true;
          p->pos++;
        }
        apply_quant(p, atom_start, q, 0, 0, lazy);
      } else if (q == '{') {
        size_t save = p->pos;
        p->pos++;
        int n_lo = 0;
        bool got_lo = false;
        while (p->pos < p->slen && isdigit((unsigned char)p->src[p->pos])) {
          n_lo = n_lo * 10 + (p->src[p->pos] - '0');
          got_lo = true;
          p->pos++;
        }
        int n_hi = n_lo;
        bool open = false;
        if (!got_lo) {
          /* Not actually a quantifier; treat '{' as literal. Back off. */
          p->pos = save;
          /* The '{' was not consumed in atom — actually atom_start emitted '{' as literal.
             Since we never reach here with a literal '{' (parse_atom would have processed
             it), this fallback rarely triggers. */
        } else {
          if (p->pos < p->slen && p->src[p->pos] == ',') {
            p->pos++;
            n_hi = -1;
            int hi = 0;
            bool got_hi = false;
            while (p->pos < p->slen && isdigit((unsigned char)p->src[p->pos])) {
              hi = hi * 10 + (p->src[p->pos] - '0');
              got_hi = true;
              p->pos++;
            }
            if (got_hi)
              n_hi = hi;
            else
              open = true;
          }
          if (p->pos < p->slen && p->src[p->pos] == '}') {
            p->pos++;
            bool lazy = false;
            if (p->pos < p->slen && p->src[p->pos] == '?') {
              lazy = true;
              p->pos++;
            }
            apply_quant(p, atom_start, '{', n_lo, open ? -1 : n_hi, lazy);
          } else {
            perr(p, "bad {n,m}");
          }
        }
      }
    }
  }
  return start;
}

static int parse_alt(parser* p) {
  voxgig_regex* re = p->re;
  int start = parse_concat(p);
  if (p->err)
    return start;
  while (p->pos < p->slen && p->src[p->pos] == '|') {
    /* Insert SPLIT at `start`, with x=start+1 and y=after-current. */
    /* Emit a JMP after the first branch to skip over the second branch. */
    int jmp_ix = code_emit(re, OP_JMP);
    int branch2_start = re->code_len;
    /* Shift to insert SPLIT at `start`. */
    code_reserve(re, 1);
    memmove(&re->code[start + 1], &re->code[start],
            (size_t)(re->code_len - start) * sizeof(voxgig_insn));
    re->code_len++;
    /* Patch jumps inside the moved block. */
    for (int i = start + 1; i < re->code_len; i++) {
      if (re->code[i].op == OP_JMP) {
        if (re->code[i].data.jmp >= start)
          re->code[i].data.jmp += 1;
      } else if (re->code[i].op == OP_SPLIT) {
        if (re->code[i].data.split.x >= start)
          re->code[i].data.split.x += 1;
        if (re->code[i].data.split.y >= start)
          re->code[i].data.split.y += 1;
      }
    }
    re->code[start].op = OP_SPLIT;
    re->code[start].data.split.x = start + 1;
    re->code[start].data.split.y = branch2_start + 1;
    jmp_ix += 1;
    re->code[jmp_ix].data.jmp = -1; /* placeholder, patched after parsing second branch */
    p->pos++;
    parse_concat(p);
    re->code[jmp_ix].data.jmp = re->code_len;
  }
  return start;
}

/* ===========================================================================
 * Public compile
 * ===========================================================================*/

voxgig_regex* voxgig_regex_compile(const char* pattern, char** err) {
  if (err)
    *err = NULL;
  if (!pattern)
    return NULL;
  voxgig_regex* re = (voxgig_regex*)calloc(1, sizeof(voxgig_regex));
  if (!re)
    return NULL;
  parser p = {0};
  p.src = pattern;
  p.slen = strlen(pattern);
  p.pos = 0;
  p.next_group = 1; /* group 0 reserved for whole-match */
  p.re = re;
  /* Wrap the whole pattern in an implicit group 0. */
  int s = code_emit(re, OP_SAVE);
  re->code[s].data.slot = 0;
  /* Detect leading ^ to set anchored_start (allows the matcher to skip
     scanning starts; ^ is also emitted normally). */
  if (p.slen > 0 && p.src[0] == '^')
    re->anchored_start = true;
  parse_alt(&p);
  if (p.err) {
    if (err)
      *err = p.err;
    else
      free(p.err);
    voxgig_regex_free(re);
    return NULL;
  }
  if (p.pos < p.slen) {
    if (err) {
      const char* msg = "unexpected )";
      *err = (char*)malloc(64);
      snprintf(*err, 64, "regex parse error at %zu: %s", p.pos, msg);
    }
    voxgig_regex_free(re);
    return NULL;
  }
  int e = code_emit(re, OP_SAVE);
  re->code[e].data.slot = 1;
  code_emit(re, OP_MATCH);
  re->ngroups = p.next_group;
  return re;
}

void voxgig_regex_free(voxgig_regex* re) {
  if (!re)
    return;
  free(re->code);
  free(re);
}

int voxgig_regex_ngroups(const voxgig_regex* re) {
  return re ? re->ngroups : 0;
}

/* ===========================================================================
 * Matcher — Thompson NFA via two state sets
 * ===========================================================================*/

/* Thread: PC + capture slots. We allocate slots on demand; total slots are
 * 2*ngroups. */
typedef struct {
  int pc;
  int* slots; /* length = 2*ngroups; -1 = unset */
} thread_t;

typedef struct {
  thread_t* threads;
  int len;
  int cap;
  int* visited; /* per-pc gen counter to suppress duplicates */
} threadlist;

static int g_gen = 0;

static thread_t* tl_add(threadlist* tl, int pc, const int* slots, int nslots, int sp,
                        const voxgig_regex* re, const char* input, size_t ilen) {
  if (pc < 0 || pc >= re->code_len)
    return NULL;
  if (tl->visited[pc] == g_gen)
    return NULL;
  tl->visited[pc] = g_gen;

  /* Follow epsilon-edges (JMP, SPLIT, SAVE, anchors) eagerly. */
  voxgig_insn* in = &re->code[pc];
  if (in->op == OP_JMP) {
    return tl_add(tl, in->data.jmp, slots, nslots, sp, re, input, ilen);
  }
  if (in->op == OP_SPLIT) {
    tl_add(tl, in->data.split.x, slots, nslots, sp, re, input, ilen);
    return tl_add(tl, in->data.split.y, slots, nslots, sp, re, input, ilen);
  }
  if (in->op == OP_SAVE) {
    int* ns = (int*)malloc((size_t)nslots * sizeof(int));
    if (!ns)
      abort();
    memcpy(ns, slots, (size_t)nslots * sizeof(int));
    ns[in->data.slot] = sp;
    thread_t* t = tl_add(tl, pc + 1, ns, nslots, sp, re, input, ilen);
    (void)t;
    free(ns);
    return NULL;
  }
  if (in->op == OP_BOL) {
    if (sp != 0 && input[sp - 1] != '\n')
      return NULL;
    return tl_add(tl, pc + 1, slots, nslots, sp, re, input, ilen);
  }
  if (in->op == OP_EOL) {
    if ((size_t)sp != ilen && input[sp] != '\n')
      return NULL;
    return tl_add(tl, pc + 1, slots, nslots, sp, re, input, ilen);
  }
  if (in->op == OP_WB || in->op == OP_NWB) {
    bool left =
        sp > 0 && (isalnum((unsigned char)input[sp - 1]) || (unsigned char)input[sp - 1] == '_');
    bool right =
        (size_t)sp < ilen && (isalnum((unsigned char)input[sp]) || (unsigned char)input[sp] == '_');
    bool at_boundary = left != right;
    bool want = in->op == OP_WB;
    if (at_boundary != want)
      return NULL;
    return tl_add(tl, pc + 1, slots, nslots, sp, re, input, ilen);
  }
  /* Char-consuming op: queue the thread. */
  if (tl->len + 1 > tl->cap) {
    int nc = tl->cap == 0 ? 16 : tl->cap * 2;
    tl->threads = (thread_t*)realloc(tl->threads, (size_t)nc * sizeof(thread_t));
    if (!tl->threads)
      abort();
    tl->cap = nc;
  }
  thread_t* t = &tl->threads[tl->len++];
  t->pc = pc;
  t->slots = (int*)malloc((size_t)nslots * sizeof(int));
  if (!t->slots)
    abort();
  memcpy(t->slots, slots, (size_t)nslots * sizeof(int));
  return t;
}

/* Free thread slot arrays. */
static void tl_clear(threadlist* tl) {
  for (int i = 0; i < tl->len; i++)
    free(tl->threads[i].slots);
  tl->len = 0;
}

static bool match_at(const voxgig_regex* re, const char* input, size_t ilen, int start,
                     int* out_slots, int nslots) {
  threadlist cur = {0};
  threadlist nxt = {0};
  cur.visited = (int*)calloc((size_t)re->code_len, sizeof(int));
  nxt.visited = (int*)calloc((size_t)re->code_len, sizeof(int));
  int* init_slots = (int*)malloc((size_t)nslots * sizeof(int));
  for (int i = 0; i < nslots; i++)
    init_slots[i] = -1;

  g_gen++;
  memset(cur.visited, 0, (size_t)re->code_len * sizeof(int));
  tl_add(&cur, 0, init_slots, nslots, start, re, input, ilen);
  free(init_slots);

  bool found = false;
  int* best_slots = (int*)malloc((size_t)nslots * sizeof(int));
  for (int i = 0; i < nslots; i++)
    best_slots[i] = -1;

  int sp = start;
  while (cur.len > 0) {
    g_gen++;
    memset(nxt.visited, 0, (size_t)re->code_len * sizeof(int));
    int c = (size_t)sp < ilen ? (unsigned char)input[sp] : -1;
    for (int i = 0; i < cur.len; i++) {
      thread_t* th = &cur.threads[i];
      voxgig_insn* in = &re->code[th->pc];
      if (in->op == OP_CHAR) {
        if (c == in->data.c)
          tl_add(&nxt, th->pc + 1, th->slots, nslots, sp + 1, re, input, ilen);
      } else if (in->op == OP_ANY) {
        if (c >= 0 && c != '\n')
          tl_add(&nxt, th->pc + 1, th->slots, nslots, sp + 1, re, input, ilen);
      } else if (in->op == OP_CLASS) {
        if (c >= 0 && cc_has(&in->data.cc, c))
          tl_add(&nxt, th->pc + 1, th->slots, nslots, sp + 1, re, input, ilen);
      } else if (in->op == OP_MATCH) {
        /* Always overwrite: threads are priority-ordered (highest first),
         * and lower-priority threads after this one don't get processed
         * (we break below). Across sp, a later MATCH can only arrive from
         * descendants of HIGHER-priority threads (threads[k+1..]'s
         * descendants are never added to nxt once we break here). So
         * overwriting unconditionally implements leftmost-longest /
         * leftmost-first correctly. The earlier `if (!found)` made greedy
         * quantifiers behave lazily — e.g. `a*` on "abc" matched "" not "a".
         */
        found = true;
        memcpy(best_slots, th->slots, (size_t)nslots * sizeof(int));
        break;
      }
    }
    tl_clear(&cur);
    threadlist tmp = cur;
    cur = nxt;
    nxt = tmp;
    sp++;
    if (cur.len == 0)
      break;
  }
  /* Handle EOI: drain the remaining current threads (some may have advanced
     past the last char and now point at MATCH via epsilons). At this point
     the threads are still priority-ordered, and the first MATCH (highest
     priority) is the canonical leftmost-first within this generation —
     but any earlier-recorded MATCH at a prior sp was from a LOWER-priority
     thread (those at higher indices that came BEFORE the surviving high-
     priority threads got to consume an extra char), so an EOI MATCH here
     should always overwrite. */
  for (int i = 0; i < cur.len; i++) {
    thread_t* th = &cur.threads[i];
    if (re->code[th->pc].op == OP_MATCH) {
      found = true;
      memcpy(best_slots, th->slots, (size_t)nslots * sizeof(int));
      break;
    }
  }

  tl_clear(&cur);
  tl_clear(&nxt);
  free(cur.threads);
  free(nxt.threads);
  free(cur.visited);
  free(nxt.visited);
  if (found && out_slots) {
    memcpy(out_slots, best_slots, (size_t)nslots * sizeof(int));
  }
  free(best_slots);
  return found;
}

bool voxgig_regex_find(const voxgig_regex* re, const char* input, size_t ilen, int* caps,
                       int ncaps) {
  if (!re || !input)
    return false;
  int nslots = re->ngroups * 2;
  int* slots = (int*)malloc((size_t)nslots * sizeof(int));
  if (!slots)
    return false;
  bool ok = false;
  for (size_t start = 0; start <= ilen; start++) {
    if (match_at(re, input, ilen, (int)start, slots, nslots)) {
      ok = true;
      break;
    }
    if (re->anchored_start)
      break;
  }
  if (ok && caps) {
    int copy = ncaps < re->ngroups ? ncaps : re->ngroups;
    for (int g = 0; g < copy; g++) {
      caps[2 * g] = slots[2 * g];
      caps[2 * g + 1] = slots[2 * g + 1];
    }
    for (int g = copy; g < ncaps; g++) {
      caps[2 * g] = -1;
      caps[2 * g + 1] = -1;
    }
  }
  free(slots);
  return ok;
}

bool voxgig_regex_test(const voxgig_regex* re, const char* input, size_t ilen) {
  return voxgig_regex_find(re, input, ilen, NULL, 0);
}

int voxgig_regex_find_all(const voxgig_regex* re, const char* input, size_t ilen, int* caps,
                          int max_matches) {
  if (!re || !input)
    return 0;
  int per = 2 * VOXGIG_REGEX_MAX_GROUPS;
  int count = 0;
  size_t pos = 0;
  int nslots = re->ngroups * 2;
  int* slots = (int*)malloc((size_t)nslots * sizeof(int));
  while (count < max_matches && pos <= ilen) {
    bool ok = false;
    size_t start;
    for (start = pos; start <= ilen; start++) {
      if (match_at(re, input, ilen, (int)start, slots, nslots)) {
        ok = true;
        break;
      }
      if (re->anchored_start && start > pos)
        break;
    }
    if (!ok)
      break;
    if (caps) {
      int* row = caps + count * per;
      int copy = re->ngroups;
      if (copy > VOXGIG_REGEX_MAX_GROUPS)
        copy = VOXGIG_REGEX_MAX_GROUPS;
      for (int g = 0; g < copy; g++) {
        row[2 * g] = slots[2 * g];
        row[2 * g + 1] = slots[2 * g + 1];
      }
      for (int g = copy; g < VOXGIG_REGEX_MAX_GROUPS; g++) {
        row[2 * g] = -1;
        row[2 * g + 1] = -1;
      }
    }
    count++;
    /* Advance: if match was empty, step by 1 to avoid infinite loop. */
    if (slots[1] == slots[0])
      pos = (size_t)slots[1] + 1;
    else
      pos = (size_t)slots[1];
  }
  free(slots);
  return count;
}

/* ===========================================================================
 * Replacement helpers
 * ===========================================================================*/

static void sb_push(char** buf, size_t* len, size_t* cap, const char* s, size_t n) {
  if (*len + n + 1 > *cap) {
    size_t nc = *cap == 0 ? 64 : *cap;
    while (nc < *len + n + 1)
      nc *= 2;
    *buf = (char*)realloc(*buf, nc);
    if (!*buf)
      abort();
    *cap = nc;
  }
  memcpy(*buf + *len, s, n);
  *len += n;
  (*buf)[*len] = '\0';
}

static char* expand_replacement(const char* repl, const int* caps, const char* input) {
  char* out = NULL;
  size_t len = 0, cap = 0;
  size_t rlen = strlen(repl);
  size_t i = 0;
  while (i < rlen) {
    if (repl[i] == '$' && i + 1 < rlen) {
      char nc = repl[i + 1];
      if (nc == '&') {
        int s = caps[0], e = caps[1];
        if (s >= 0 && e >= s)
          sb_push(&out, &len, &cap, input + s, (size_t)(e - s));
        i += 2;
        continue;
      }
      if (nc >= '0' && nc <= '9') {
        int g = nc - '0';
        int s = caps[2 * g], e = caps[2 * g + 1];
        if (s >= 0 && e >= s)
          sb_push(&out, &len, &cap, input + s, (size_t)(e - s));
        i += 2;
        continue;
      }
      if (nc == '$') {
        sb_push(&out, &len, &cap, "$", 1);
        i += 2;
        continue;
      }
    }
    sb_push(&out, &len, &cap, &repl[i], 1);
    i++;
  }
  if (!out)
    out = re_strdup("");
  return out;
}

char* voxgig_regex_replace(const voxgig_regex* re, const char* input, size_t ilen,
                           const char* replacement) {
  if (!re || !input)
    return NULL;
  int nslots = re->ngroups * 2;
  int* slots = (int*)malloc((size_t)nslots * sizeof(int));
  char* out = NULL;
  size_t len = 0, cap = 0;
  size_t pos = 0;
  while (pos <= ilen) {
    bool ok = false;
    size_t start;
    for (start = pos; start <= ilen; start++) {
      if (match_at(re, input, ilen, (int)start, slots, nslots)) {
        ok = true;
        break;
      }
      if (re->anchored_start && start > pos)
        break;
    }
    if (!ok) {
      sb_push(&out, &len, &cap, input + pos, ilen - pos);
      break;
    }
    /* Copy chars before the match. */
    sb_push(&out, &len, &cap, input + pos, start - pos);
    char* exp = expand_replacement(replacement, slots, input);
    sb_push(&out, &len, &cap, exp, strlen(exp));
    free(exp);
    /* Advance. */
    size_t mend = (size_t)slots[1];
    if ((int)mend == slots[0]) {
      if (mend < ilen)
        sb_push(&out, &len, &cap, input + mend, 1);
      pos = mend + 1;
    } else {
      pos = mend;
    }
  }
  if (!out)
    out = re_strdup("");
  free(slots);
  return out;
}

char* voxgig_regex_replace_cb_fn(const voxgig_regex* re, const char* input, size_t ilen,
                                 voxgig_regex_replace_cb cb, void* ud) {
  if (!re || !input)
    return NULL;
  int nslots = re->ngroups * 2;
  int* slots = (int*)malloc((size_t)nslots * sizeof(int));
  char* out = NULL;
  size_t len = 0, cap = 0;
  size_t pos = 0;
  while (pos <= ilen) {
    bool ok = false;
    size_t start;
    for (start = pos; start <= ilen; start++) {
      if (match_at(re, input, ilen, (int)start, slots, nslots)) {
        ok = true;
        break;
      }
      if (re->anchored_start && start > pos)
        break;
    }
    if (!ok) {
      sb_push(&out, &len, &cap, input + pos, ilen - pos);
      break;
    }
    sb_push(&out, &len, &cap, input + pos, start - pos);
    char* rep = cb(slots, re->ngroups, input, ud);
    sb_push(&out, &len, &cap, rep, strlen(rep));
    free(rep);
    size_t mend = (size_t)slots[1];
    if ((int)mend == slots[0]) {
      if (mend < ilen)
        sb_push(&out, &len, &cap, input + mend, 1);
      pos = mend + 1;
    } else {
      pos = mend;
    }
  }
  if (!out)
    out = re_strdup("");
  free(slots);
  return out;
}
