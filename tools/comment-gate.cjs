
'use strict'

const Fs = require('node:fs')
const Path = require('node:path')

const REPO = Path.join(__dirname, '..')
const Child = require('node:child_process')
const CONFIG = require('./comment-scope.json')

const SOURCE_EXTS = ['.ts', '.go', '.rs', '.aon', '.aontu']
const SKIP_DIRS = new Set([
  'node_modules', 'dist', 'dist-test', 'covdata', 'target', 'vendor', '.git',
])

const MAX_BLOCK_LINES = 5
const MAX_DENSITY = 0.12
const DENSITY_FLOOR_LINES = 8

const LICENSE_RE = /\b(?:Copyright|SPDX-License-Identifier)\b/i
const DIRECTIVE_RE =
  /^(#!|\/\/\s*(EJECT-(?:START|END)|<\[|#[A-Z][\w-]*\b|go:|nolint|@ts-|eslint|prettier|c8 |istanbul|coverage:ignore|covergate:allow|\/\s*<reference)|\/\*\s*([@#]__PURE__|[@#]__NO_SIDE_EFFECTS__|node:coverage|eslint|c8|istanbul|prettier))/

const NARRATIVE_RE = [
  /\b(we|our|ours|us)\b/i,
  /(^|[^\w])I[ ,]/,
  /\b(used to|no longer|previously|originally|at first|for years|since then|nowadays)\b/i,
  /\b(turned out|turns out|it emerged|was found|found that|discovered|noticed)\b/i,
  /\b(the plan|the first version|the second version|an earlier|a later version|the old|the new)\b/i,
  /\b(scar|worked example|worth knowing|worth reading|expect to lose|for the record|history)\b/i,
  /\b(this is why|that is why|which is why|the reason (this|it|we)|hence why)\b/i,
  /\b(deliberately|on purpose|by design|intentionally)\b/i,
  /\b(fixed by|fixes? #|broke|broken by|regression from|reverted|landed in|shipped in)\b/i,
  /\b(review|reviewer|issue|pull request|pr\b|ticket|commit)\b/i,
  /\b(todo|fixme|xxx|hack|note to self)\b/i,
]

const REQUIREMENT_RE = [
  /\b(requirement|requirements|business|policy|policies|acceptance|stakeholder|customer|user story|use case|sla|invariant of the business)\b/i,
  /\b(the rule is|the rules are|the contract is|by contract|specified as|as specified|per the spec|the spec says)\b/i,
  /\b(shall|is required to|are required to|is expected to|are expected to)\b/i,
]

const UNVERIFIABLE_RE = [
  { rule: 'dated-claim', re: /\b(19|20)\d\d-\d\d(-\d\d)?\b/ },
  { rule: 'issue-ref', re: /(^|[\s(])#\d+\b/ },
  { rule: 'version-claim', re: /\bv\d+\.\d+(\.\d+)?\b/ },
  {
    rule: 'count-claim',
    re: /\b(two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|\d+)\s+(?:[a-z][a-z-]*\s+){0,2}[a-z][a-z-]{2,}s\b/i,
  },
]

const PATH_RE = /\b((?:[\w.-]+\/)+[\w.-]+\.(?:ts|go|md|tsv|cjs|mjs|js|json|aontu|aon|abnf|yml|sh))\b/g
const ADR_RE = /\bADR-(\d{3})\b/g
const SYMBOL_RE = /`([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*)(?:\(\))?`/g

const CODE_SHAPED_RE =
  /^\s*(?:(?:const|let|var|func|function|type|class|interface|import|export|package|return|if|for|while|switch|case|await|throw|new|await)\b(?=[^\n]*[;{}()=[\]])|[\w$.[\]]+\s*(?::=|\+=|=[^=])|[\w$.]+\([^)]*\)\s*[;{]?\s*$|[})\]];?\s*$)/

const WORD_RE = /[A-Za-z_$][\w$]*/g


function gated(rel) {
  const model = /\.(aon|aontu)$/.test(rel)
  return SOURCE_EXTS.some((ext) => rel.endsWith(ext)) &&
    !rel.split('/').some((part) => SKIP_DIRS.has(part) && !(model && part === 'target' && /(^|\/)model\/target\//.test(rel))) &&
    !Object.keys({...CONFIG.exclude, ...(model ? CONFIG.excludeModels : {})}).some((prefix) => rel === prefix || rel.startsWith(prefix + '/'))
}

function sourceFiles() {
  const names = Child.execFileSync('git',
    ['ls-files', '-z', '--cached', '--others', '--exclude-standard'],
    { cwd: REPO, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }).split('\0')
  return [...new Set(names)].filter((f) => f && gated(f) &&
    Fs.existsSync(Path.join(REPO, f)) && Fs.lstatSync(Path.join(REPO, f)).isFile()).sort()
}

function language(file) {
  return /\.(aon|aontu)$/.test(file) ? 'aon' : file.endsWith('.go') ? 'go' : file.endsWith('.rs') ? 'rs' : 'ts'
}

// Track literals so their contents cannot become comment findings.
function lex(text, lang) {
  const comments = [], codeLine = new Set()
  let line = 1, i = 0, prev = ''
  const n = text.length
  function string(quote, raw = false) {
    codeLine.add(line); i++
    while (i < n) {
      if (!raw && text[i] === '\\') {
        if (text[i + 1] === '\n') line++
        i += 2; continue
      }
      if (text[i] === '\n') line++
      if (text[i++] === quote) break
    }
    prev = quote
  }
  function template() {
    codeLine.add(line); i++
    while (i < n) {
      if (text[i] === '\\') {
        if (text[i + 1] === '\n') line++
        i += 2; continue
      }
      if (text[i] === '`') { i++; break }
      if (text[i] === '$' && text[i + 1] === '{') {
        i += 2; prev = '{'; code(true); continue
      }
      if (text[i] === '\n') line++
      i++
    }
    prev = '`'
  }
  function code(interpolation = false) {
    let depth = 0
    while (i < n) {
      const c = text[i], c2 = text[i + 1]
      if (c === '\n') { line++; i++; continue }
      if (lang === 'rs' && (c === 'r' || (c === 'b' && c2 === 'r'))) {
        const match = text.slice(i).match(/^(?:br|r)(#*)"/)
        if (match) {
          codeLine.add(line)
          const end = text.indexOf('"' + match[1], i + match[0].length)
          const stop = end < 0 ? n : end + 1 + match[1].length
          line += (text.slice(i, stop).match(/\n/g) || []).length
          i = stop; prev = '"'; continue
        }
      }
      if (lang === 'rs' && c === "'" &&
        !/^'(?:[^'\\\n]|\\(?:u\{[0-9a-fA-F]+\}|x[0-9a-fA-F]{2}|.))'/.test(text.slice(i))) {
        codeLine.add(line); i++; prev = c; continue
      }
      if ((lang === 'aon' && c === '#') || (lang !== 'aon' && c === '/' && c2 === '/')) {
        const start = i
        while (i < n && text[i] !== '\n') i++
        comments.push({kind:'line', start:line, end:line, from:start, to:i, text:text.slice(start,i)})
        continue
      }
      if (lang !== 'aon' && c === '/' && c2 === '*') {
        const start = i, startLine = line
        i += 2
        let nesting = 1
        while (i < n && nesting) {
          if (lang === 'rs' && text[i] === '/' && text[i + 1] === '*') { nesting++; i += 2 }
          else if (text[i] === '*' && text[i + 1] === '/') { nesting--; i += 2 }
          else { if (text[i] === '\n') line++; i++ }
        }
        comments.push({kind:'block',start:startLine,end:line,from:start,to:i,text:text.slice(start,i)})
        continue
      }
      if (lang === 'ts' && c === '`') { template(); continue }
      if (c === '"' || c === "'" || ((lang === 'go' || lang === 'aon') && c === '`')) {
        string(c, lang === 'go' && c === '`'); continue
      }
      const regexStart = lang === 'ts' && (!/[\w$)\]]/.test(prev) ||
        /\b(?:return|throw|yield|case)\s*$/.test(text.slice(Math.max(0,i-30),i)))
      if (c === '/' && regexStart) {
        let j=i+1, inClass=false, closed=false
        while (j<n && text[j]!=='\n') {
          if (text[j]==='\\') {j+=2;continue}
          if (text[j]==='[') inClass=true
          else if(text[j]===']') inClass=false
          else if(text[j]==='/' && !inClass) {closed=true;j++;break}
          j++
        }
        if(closed) {codeLine.add(line);i=j;prev='/';continue}
      }
      if (interpolation && c === '}') {
        if (depth === 0) {i++;return}
        depth--
      } else if (interpolation && c === '{') depth++
      if (!/\s/.test(c)) {codeLine.add(line);prev=c}
      i++
    }
  }
  code()
  return {comments, codeLines:codeLine.size}
}


// Consecutive line comments at one indentation read as one comment; the
// gate measures them that way, because that is how they are written.
function blocks(scan, lines) {
  const out = []
  let open = null

  for (const c of scan.comments) {
    const before = lines[c.start - 1].slice(0, lines[c.start - 1].indexOf(c.text.split('\n')[0]))
    const inline = before.trim().length > 0

    const directive = DIRECTIVE_RE.test(c.text.trim())

    if (c.kind === 'line' && !inline && !directive && open && !open.directive
      && open.end === c.start - 1 && !open.inline) {
      open.end = c.end
      open.to = c.to
      open.text += '\n' + c.text
      continue
    }

    open = {
      kind: c.kind,
      start: c.start,
      end: c.end,
      from: c.from,
      to: c.to,
      text: c.text,
      inline,
      directive,
    }
    out.push(open)
  }

  return out
}


function blockLines(block) {
  return block.end - block.start + 1
}


function prose(block) {
  return block.text
    .split('\n')
    .map((l) => l.replace(/^\s*(#+|\/\/+|\/\*+|\*+\/?)/, '').replace(/\*\/\s*$/, '').trim())
    .join('\n')
    .trim()
}


function exempt(block) {
  const first = block.text.trim()
  return LICENSE_RE.test(first) || DIRECTIVE_RE.test(first)
}


let symbolIndex = null

function codeOnly(text, lang) {
  const { comments } = lex(text, lang)
  let out = ''
  let at = 0
  for (const c of comments) { out += text.slice(at, c.from); at = c.to }
  return out + text.slice(at)
}


// Indexed from code alone: a symbol index built over comment prose too
// would confirm every name a comment invents.
function symbols() {
  if (symbolIndex) return symbolIndex
  symbolIndex = new Set()
  for (const file of sourceFiles()) {
    const text = Fs.readFileSync(Path.join(REPO, file), 'utf8')
    const code = codeOnly(text, language(file))
    for (const word of code.match(WORD_RE) || []) symbolIndex.add(word)
  }
  return symbolIndex
}


let adrIndex = null

function adrs() {
  if (adrIndex) return adrIndex
  adrIndex = new Set()
  const path = Path.join(REPO, 'ADR.md')
  const text = Fs.existsSync(path) ? Fs.readFileSync(path, 'utf8') : ''
  for (const m of text.matchAll(/^## ADR-(\d{3})\b/gm)) adrIndex.add(m[1])
  return adrIndex
}


// A path in a comment may be written from the repository root, from
// the package root, or beside the file.
function resolves(ref, file) {
  const bases = [REPO, Path.join(REPO, file.split('/')[0]),
    Path.dirname(Path.join(REPO, file))]
  return bases.some((base) =>
    Fs.existsSync(Path.join(base, ref)) || Fs.existsSync(Path.join(base, '.' + ref)))
}


function checkFile(file, opts = {}) {
  return checkText(file, Fs.readFileSync(Path.join(REPO, file), 'utf8'), opts)
}


function checkText(file, text, opts = {}) {
  const lines = text.split('\n')
  const scan = lex(text,
    language(file))
  const all = blocks(scan, lines)
  const kept = all.filter((b) => !exempt(b))

  const commentLines = kept.reduce((sum, b) => sum + blockLines(b), 0)
  const findings = []

  const add = (block, rule, detail) => findings.push({
    file,
    line: block.start,
    rule,
    detail,
    excerpt: prose(block).split('\n')[0].slice(0, 72),
  })

  for (const block of kept) {
    const body = prose(block)
    const flat = body.replace(/\s+/g, ' ')

    if (blockLines(block) > MAX_BLOCK_LINES) {
      add(block, 'long-block', `${blockLines(block)} lines (max ${MAX_BLOCK_LINES})`)
    }

    for (const re of NARRATIVE_RE) {
      const m = flat.match(re)
      if (m) { add(block, 'narrative', `"${m[0]}"`); break }
    }

    for (const re of REQUIREMENT_RE) {
      const m = flat.match(re)
      if (m) { add(block, 'requirements', `"${m[0]}"`); break }
    }

    for (const { rule, re } of UNVERIFIABLE_RE) {
      const m = flat.match(re)
      if (m) add(block, rule, `"${m[0].trim()}"`)
    }

    for (const raw of body.split('\n')) {
      const line = raw.replace(/^\s*(?:\/\/+\s*)+/, '')
      if ((CODE_SHAPED_RE.test(line) || (language(file) === 'aon' &&
        /^(?:[\w.$-]+\s*:\s*)+(?:[\[{'"`*@]|-?\d|true\b|false\b|null\b|(?:string|number|boolean|integer)\b)/.test(line))) && line.length > 3) {
        add(block, 'commented-code', `"${line.slice(0, 48)}"`)
        break
      }
    }

    for (const m of body.matchAll(PATH_RE)) {
      if (!resolves(m[1], file)) add(block, 'stale-path', m[1])
    }

    for (const m of body.matchAll(ADR_RE)) {
      if (!adrs().has(m[1])) add(block, 'stale-adr', m[0])
    }

    if (!opts.skipSymbols) {
      for (const m of body.matchAll(SYMBOL_RE)) {
        const head = m[1].split('.')[0]
        if (!symbols().has(head)) add(block, 'stale-symbol', m[1])
      }
    }
  }

  const density = scan.codeLines === 0 ? 0 : commentLines / scan.codeLines
  if (commentLines > DENSITY_FLOOR_LINES && density > MAX_DENSITY) {
    findings.push({
      file,
      line: 1,
      rule: 'dense-file',
      detail: `${commentLines} comment lines over ${scan.codeLines} code lines`
        + ` = ${(density * 100).toFixed(1)}% (max ${(MAX_DENSITY * 100).toFixed(0)}%)`,
      excerpt: '',
    })
  }

  return {
    file,
    codeLines: scan.codeLines,
    commentLines,
    blocks: kept.length,
    longest: kept.reduce((m, b) => Math.max(m, blockLines(b)), 0),
    words: kept.reduce((sum, b) => sum + (prose(b).match(/\S+/g) || []).length, 0),
    findings,
  }
}


function checkAll(files = sourceFiles(), opts = {}) {
  return files.map((f) => checkFile(f, opts))
}


function totals(reports) {
  const t = {
    files: reports.length,
    codeLines: 0,
    commentLines: 0,
    commentWords: 0,
    blocks: 0,
    longest: 0,
    findings: 0,
    byRule: {},
    filesWithFindings: 0,
  }
  for (const r of reports) {
    t.codeLines += r.codeLines
    t.commentLines += r.commentLines
    t.commentWords += r.words
    t.blocks += r.blocks
    t.longest = Math.max(t.longest, r.longest)
    t.findings += r.findings.length
    if (r.findings.length > 0) t.filesWithFindings++
    for (const f of r.findings) t.byRule[f.rule] = (t.byRule[f.rule] || 0) + 1
  }
  t.density = t.codeLines === 0 ? 0 : t.commentLines / t.codeLines
  return t
}


module.exports = {
  sourceFiles, checkFile, checkText, checkAll, totals, lex, blocks, prose,
  MAX_BLOCK_LINES, MAX_DENSITY, exempt, language, gated,
}


if (require.main === module) {
  const args = process.argv.slice(2)
  const only = args.filter((a) => !a.startsWith('--'))
  const files = only.length > 0 ? only : sourceFiles()
  const opts = { skipSymbols: args.includes('--no-symbols') }
  const reports = checkAll(files, opts)
  const t = totals(reports)

  if (args.includes('--json')) {
    process.stdout.write(JSON.stringify({ totals: t, reports }, null, 2) + '\n')
    process.exitCode = t.findings === 0 ? 0 : 1; return
  }

  if (args.includes('--measure')) {
    process.stdout.write(
      `files ${t.files}  code ${t.codeLines}  comment ${t.commentLines}`
      + `  words ${t.commentWords}  blocks ${t.blocks}`
      + `  density ${(t.density * 100).toFixed(1)}%  longest ${t.longest}\n`)
    for (const [rule, count] of Object.entries(t.byRule).sort((a, b) => b[1] - a[1])) {
      process.stdout.write(`  ${rule}: ${count}\n`)
    }
    return
  }

  const limit = Number((args.find((a) => a.startsWith('--limit=')) || '--limit=40').slice(8))
  let shown = 0
  for (const r of reports) {
    for (const f of r.findings) {
      if (shown++ < limit) {
        process.stdout.write(`${f.file}:${f.line}: ${f.rule}: ${f.detail}\n`)
        if (f.excerpt) process.stdout.write(`    ${f.excerpt}\n`)
      }
    }
  }
  if (t.findings > limit) process.stdout.write(`... ${t.findings - limit} more\n`)
  process.stdout.write(t.findings === 0
    ? `comment gate: clean (${t.commentLines} comment lines, ${(t.density * 100).toFixed(1)}%)\n`
    : `comment gate: ${t.findings} finding(s) in ${t.filesWithFindings} file(s) — COMMENT-POLICY.md\n`)
  process.exitCode = t.findings === 0 ? 0 : 1; return
}
