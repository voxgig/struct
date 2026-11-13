require 'json'
require 'uri'

module VoxgigStruct
  # --- Debug Logging Configuration ---
  DEBUG = false

  # Lazy: the message block is only evaluated when DEBUG is on, so hot paths
  # never pay to build (and `.inspect`-serialise whole nodes into) a debug
  # string that would just be discarded.
  def self.log
    puts "[DEBUG] #{yield}" if DEBUG
  end

  # --- Helper to convert internal undefined marker to Ruby nil ---
  def self.conv(val)
    val.equal?(UNDEF) ? nil : val
  end

  # --- Constants ---
  S_MKEYPRE  = 'key:pre'.freeze
  S_MKEYPOST = 'key:post'.freeze
  S_MVAL     = 'val'.freeze
  S_MKEY     = 'key'.freeze

  S_DKEY   = '`$KEY`'.freeze
  S_DMETA  = '`$META`'.freeze
  S_DTOP   = '$TOP'.freeze
  S_DERRS  = '$ERRS'.freeze

  S_any      = 'any'.freeze
  S_array    = 'array'.freeze
  S_boolean  = 'boolean'.freeze
  S_decimal  = 'decimal'.freeze
  S_function = 'function'.freeze
  S_instance = 'instance'.freeze
  S_integer  = 'integer'.freeze
  S_list     = 'list'.freeze
  S_map      = 'map'.freeze
  S_nil      = 'nil'.freeze
  S_node     = 'node'.freeze
  S_number   = 'number'.freeze
  S_null     = 'null'.freeze
  S_object   = 'object'.freeze
  S_scalar   = 'scalar'.freeze
  S_string   = 'string'.freeze
  S_symbol   = 'symbol'.freeze
  S_MT       = ''.freeze       # empty string constant (used as a prefix)
  S_BT       = '`'.freeze
  S_DS       = '$'.freeze
  S_DT       = '.'.freeze      # delimiter for key paths
  S_CN       = ':'.freeze      # colon for unknown paths
  S_SP       = ' '.freeze
  S_VIZ      = ': '.freeze
  S_KEY      = 'KEY'.freeze

  # Types - bitfield integers matching TypeScript canonical
  _t = 31
  T_any = (1 << _t) - 1
  _t -= 1
  T_noval = 1 << _t
  _t -= 1
  T_boolean = 1 << _t
  _t -= 1
  T_decimal = 1 << _t
  _t -= 1
  T_integer = 1 << _t
  _t -= 1
  T_number = 1 << _t
  _t -= 1
  T_string = 1 << _t
  _t -= 1
  T_function = 1 << _t
  _t -= 1
  T_symbol = 1 << _t
  _t -= 1
  T_null = 1 << _t
  _t -= 8
  T_list = 1 << _t
  _t -= 1
  T_map = 1 << _t
  _t -= 1
  T_instance = 1 << _t
  _t -= 5
  T_scalar = 1 << _t
  _t -= 1
  T_node     = 1 << _t

  TYPENAME = [
    S_any, S_nil, S_boolean, S_decimal, S_integer, S_number, S_string,
    S_function, S_symbol, S_null,
    '', '', '', '', '', '', '',
    S_list, S_map, S_instance,
    '', '', '', '',
    S_scalar, S_node
  ].freeze

  SKIP = { '`$SKIP`' => true }.freeze
  DELETE = { '`$DELETE`' => true }.freeze

  # Unique undefined marker.
  UNDEF = Object.new.freeze

  # Mode constants (bitfield) matching TypeScript canonical
  M_KEYPRE = 1
  M_KEYPOST = 2
  M_VAL = 4

  MODENAME = { M_VAL => 'val', M_KEYPRE => 'key:pre', M_KEYPOST => 'key:post' }.freeze
  PLACEMENT = { M_VAL => 'value', M_KEYPRE => S_MKEY, M_KEYPOST => S_MKEY }.freeze

  MAXDEPTH = 32

  # --- Utility functions ---

  def self.sorted(val)
    case val
    when Hash
      sorted_hash = {}
      val.keys.sort.each { |k| sorted_hash[k] = sorted(val[k]) }
      sorted_hash
    when Array
      val.map { |elem| sorted(elem) }
    else
      val
    end
  end

  def self.clone(val)
    return nil if val.nil? || val.equal?(UNDEF)

    if isfunc(val)
      val
    elsif islist(val)
      val.map { |v| clone(v) }
    elsif ismap(val)
      result = {}
      val.each { |k, v| result[k] = isfunc(v) ? v : clone(v) }
      result
    else
      val
    end
  end

  def self.escre(s)
    s = '' if s.nil?
    Regexp.escape(s)
  end

  # ---------------------------------------------------------------------
  # Regex utility — uniform re_* API (see /REGEX_API.md). Ruby's Onigmo
  # engine is a strict superset of RE2.
  # ---------------------------------------------------------------------

  def self.re_compile(pattern)
    pattern.is_a?(Regexp) ? pattern : Regexp.new(pattern)
  end

  def self.re_test(pattern, input)
    !!(re_compile(pattern) =~ input.to_s)
  end

  def self.re_find(pattern, input)
    m = re_compile(pattern).match(input.to_s)
    return nil if m.nil?

    [m[0]] + m.captures.map { |c| c.nil? ? '' : c }
  end

  def self.re_find_all(pattern, input)
    out = []
    input.to_s.scan(re_compile(pattern)) do
      m = Regexp.last_match
      out << ([m[0]] + m.captures.map { |c| c.nil? ? '' : c })
    end
    out
  end

  def self.re_replace(pattern, input, replacement)
    rx = re_compile(pattern)
    if replacement.respond_to?(:call)
      input.to_s.gsub(rx) do |_match|
        m = Regexp.last_match
        replacement.call([m[0]] + m.captures.map { |c| c.nil? ? '' : c })
      end
    else
      # Translate JS-style $& / $1 to Ruby's \0 / \1
      ruby_repl = replacement.gsub(/\$([&0-9])/) do |_|
        ch = ::Regexp.last_match(1)
        ch == '&' ? '\\0' : "\\#{ch}"
      end
      input.to_s.gsub(rx, ruby_repl)
    end
  end

  def self.re_escape(s)
    escre(s)
  end

  # Keeps what encodeURIComponent keeps.
  def self.escurl(s)
    s = '' if s.nil?
    URI::DEFAULT_PARSER.escape(s, /[^A-Za-z0-9\-._~!*'()]/)
  end

  R_LIST_KEY = /\A(0|-?[1-9][0-9]*)\z/.freeze

  # A list key's index, or nil. As JavaScript reads list[key], that is an integral
  # number or the string String(n) prints for one: "1" and "-1", not "01", "+1" or "-0".
  def self._listkey(key)
    return key if key.is_a?(Integer)
    return key.to_i if key.is_a?(Float) && key.finite? && key == key.to_i
    return key.to_i if key.is_a?(String) && R_LIST_KEY.match?(key)

    nil
  end

  # The index key reads in a list of size items, or -1. With fromend, as getelem
  # reads it, a negative key counts back from the end.
  def self._listindex(key, size, fromend = false)
    index = _listkey(key)
    return -1 if index.nil?

    index += size if fromend && index.negative?
    index >= 0 && index < size ? index : -1
  end

  # --- Internal getprop ---
  # Returns the value if found; otherwise returns alt (default is UNDEF)
  def self._getprop(val, key, alt = UNDEF)
    log { "(_getprop) called with val=#{val.inspect} and key=#{key.inspect}" }
    return alt if val.nil? || key.nil?

    if islist(val)
      index = _listindex(key, val.size)
      if index.negative?
        log { "(_getprop) index #{key.inspect} out of bounds; returning alt" }
        return alt
      end
      result = val[index]
      log { "(_getprop) returning #{result.inspect} from array for key #{key}" }
      result
    elsif ismap(val)
      key_str = key.to_s
      # As in JavaScript, only a string or a number names a map entry: true and [1] do not.
      if !key.is_a?(String) && !key.is_a?(Numeric)
        log { "(_getprop) key #{key.inspect} names no entry; returning alt" }
        alt
      elsif val.key?(key_str)
        result = val[key_str]
        log { "(_getprop) found key #{key_str.inspect} in hash, returning #{result.inspect}" }
        result
      elsif key.is_a?(String) && val.key?(key.to_sym)
        result = val[key.to_sym]
        log { "(_getprop) found symbol key #{key.to_sym.inspect} in hash, returning #{result.inspect}" }
        result
      else
        log { "(_getprop) key #{key.inspect} not found; returning alt" }
        alt
      end
    else
      log { '(_getprop) value is not a node; returning alt' }
      alt
    end
  end

  # --- Public getprop ---
  # Group A reader: a stored JSON null (nil) at the key counts as "no value",
  # indistinguishable from absent, so it falls back to alt (canonical TS:
  # `if (null == out) return alt`). Group B callers that must preserve a
  # stored null use _getprop directly.
  def self.getprop(val, key, alt = nil)
    result = _getprop(val, key, UNDEF)
    result.equal?(UNDEF) || result.nil? ? alt : result
  end

  def self.isempty(val)
    return true if val.nil? || val.equal?(UNDEF) || val == ''
    return true if islist(val) && val.empty?
    return true if ismap(val) && val.empty?

    false
  end

  def self.iskey(key)
    (key.is_a?(String) && !key.empty?) || key.is_a?(Numeric)
  end

  def self.islist(val)
    val.is_a?(Array)
  end

  def self.ismap(val)
    val.is_a?(Hash)
  end

  def self.isnode(val)
    ismap(val) || islist(val)
  end

  def self.items(val, apply = nil)
    if ismap(val)
      pairs = val.keys.sort.map { |k| [k, val[k]] }
    elsif islist(val)
      pairs = val.each_with_index.map { |v, i| [i.to_s, v] }
    else
      return []
    end
    apply ? pairs.map { |item| apply.call(item) } : pairs
  end

  def self.setprop(parent, key, val = :no_val_provided)
    log { ">>> setprop called with parent=#{parent.inspect}, key=#{key.inspect}, val=#{val.inspect}" }
    return parent unless iskey(key)
    raise S_CONDENSED_IMMUTABLE if iscondensed(parent)

    if ismap(parent)
      key_str = key.to_s
      if val == :no_val_provided
        parent.delete(key_str)
      else
        parent[key_str] = val
      end
    elsif islist(parent)
      key_i = _listkey(key)
      return parent if key_i.nil?

      if val == :no_val_provided
        parent.delete_at(key_i) if key_i >= 0 && key_i < parent.length
      elsif key_i >= 0
        index = [key_i, parent.length].min
        parent[index] = val
      else
        parent.unshift(val)
      end
    end
    log { "<<< setprop result: #{parent.inspect}" }
    parent
  end

  def self.stringify(val, maxlen = nil, _pretty = nil)
    return '' if val.equal?(UNDEF)
    return 'null' if val.nil?

    if val.is_a?(String)
      valstr = val
    else
      begin
        v = sorted(val)
        valstr = JSON.generate(v)
        valstr = valstr.gsub('"', '')
      rescue StandardError
        valstr = val.to_s
      end
    end

    valstr = "#{valstr[0, maxlen - 3]}..." if !maxlen.nil? && maxlen >= 0 && (valstr.length > maxlen)

    valstr
  end

  def self.pathify(val, startin = nil, endin = nil)
    pathstr = nil

    path = if islist(val)
             val
           elsif val.is_a?(String)
             [val]
           elsif val.is_a?(Numeric)
             [val]
           end

    start = startin.nil? ? 0 : startin.negative? ? 0 : startin
    end_idx = endin.nil? ? 0 : endin.negative? ? 0 : endin

    if path && start >= 0
      path = path[start..(-end_idx - 1)] || []
      pathstr = if path.empty?
                  '<root>'
                else
                  path
                    .select { |p| iskey(p) }
                    .map do |p|
                      if p.is_a?(Numeric)
                        S_MT + p.floor.to_s
                      else
                        p.gsub('.', S_MT)
                      end
                    end
                    .join(S_DT)
                end
    end

    if pathstr.nil?
      pathstr = "<unknown-path#{S_CN + stringify(val, 47) unless val.equal?(UNDEF)}>"
    end

    pathstr
  end

  def self.strkey(key = nil)
    return '' if key.nil?
    return key if key.is_a?(String)
    return key.floor.to_s if key.is_a?(Numeric)

    ''
  end

  def self.isfunc(val)
    val.respond_to?(:call)
  end

  def self.getdef(val, alt)
    val.nil? ? alt : val
  end

  def self.size(val)
    return 0 if val.nil? || val.equal?(UNDEF)
    return val.length if val.is_a?(String) || islist(val)
    return val.keys.length if ismap(val)
    return (val == true ? 1 : 0) if [true, false].include?(val)
    return val.to_i if val.is_a?(Numeric)

    0
  end

  def self.slice(val, start_idx = nil, end_idx = nil, mutate = false)
    return val if val.nil? || val.equal?(UNDEF)

    if val.is_a?(Numeric) && !val.is_a?(TrueClass) && !val.is_a?(FalseClass)
      s = start_idx.nil? ? (-Float::INFINITY) : start_idx
      e = end_idx.nil? ? Float::INFINITY : (end_idx - 1)
      # Not Comparable#clamp: that raises when s > e, but here we want e returned.
      return [[val, s].max, e].min # rubocop:disable Style/ComparableClamp
    end

    vlen = size(val)

    start_idx = 0 if !end_idx.nil? && start_idx.nil?

    unless start_idx.nil?
      s = start_idx
      e = end_idx

      if s.negative?
        e = vlen + s
        e = 0 if e.negative?
        s = 0
      elsif !e.nil?
        if e.negative?
          e = vlen + e
          e = 0 if e.negative?
        elsif vlen < e
          e = vlen
        end
      else
        e = vlen
      end

      s = vlen if vlen < s

      if islist(val)
        result = val[s...e] || []
        if mutate
          val.replace(result)
          return val
        end
        return result
      elsif val.is_a?(String)
        return val[s...e] || ''
      end
    end

    val
  end

  def self.pad(str, padding = nil, padchar = nil)
    str = stringify(str) unless str.is_a?(String)
    padding = 44 if padding.nil?
    padchar = padchar.nil? ? ' ' : "#{padchar} "[0]
    if padding >= 0
      str.ljust(padding, padchar)
    else
      str.rjust(-padding, padchar)
    end
  end

  def self.getelem(val, key, alt = UNDEF)
    out = UNDEF
    if islist(val)
      nkey = _listindex(key, val.length, true)
      out = val[nkey] unless nkey.negative?
    end
    # A null (or absent) slot counts as "no value" — the same Group A rule
    # getprop applies (canonical TS: `if (null == out) return alt`).
    if out.equal?(UNDEF) || out.nil?
      return isfunc(alt) ? alt.call : (alt.equal?(UNDEF) ? nil : alt)
    end

    out
  end

  def self.flatten(lst, depth = nil)
    depth = 1 if depth.nil?
    return lst unless islist(lst)

    out = []
    lst.each do |item|
      if islist(item) && depth.positive?
        out.concat(flatten(item, depth - 1))
      else
        out << item unless item.nil? || item.equal?(UNDEF)
      end
    end
    out
  end

  def self.filter(val, check)
    return [] unless isnode(val)

    items(val).select { |item| check.call(item) }.map { |item| item[1] }
  end

  def self.delprop(parent, key)
    return parent unless iskey(key)
    raise S_CONDENSED_IMMUTABLE if iscondensed(parent)

    if ismap(parent)
      ks = strkey(key)
      parent.delete(ks)
    elsif islist(parent)
      ki = _listkey(key)
      parent.delete_at(ki) if !ki.nil? && ki >= 0 && ki < parent.length
    end
    parent
  end

  def self.join(arr, sep = nil, url = nil)
    return '' unless islist(arr)

    sepdef = sep.nil? ? ',' : sep.to_s
    sepre = sepdef.length == 1 ? Regexp.escape(sepdef) : nil

    # Filter to non-empty strings only
    parts = arr.select { |n| n.is_a?(String) && n != '' }

    parts = parts.map.with_index do |s, i|
      if sepre
        if url && i.zero?
          s = s.sub(/#{sepre}+$/, '')
          next s
        end
        s = s.sub(/^#{sepre}+/, '') if i.positive?
        s = s.sub(/#{sepre}+$/, '') if i < parts.length - 1 || !url
        # Collapse internal duplicate separators
        s = s.gsub(/([^#{sepre}])#{sepre}+([^#{sepre}])/, "\\1#{sepdef}\\2")
      end
      s
    end.reject(&:empty?)

    parts.join(sepdef)
  end

  def self.joinurl(sarr)
    join(sarr, '/', true)
  end

  def self.jsonify(val, flags = nil)
    str = 'null'
    unless val.nil?
      begin
        indent = (flags.is_a?(Hash) ? (flags['indent'] || flags[:indent]) : nil) || 2
        str = _json_stringify(val, indent, 0)
        str = 'null' if str.nil?
        offset = (flags.is_a?(Hash) ? (flags['offset'] || flags[:offset]) : nil) || 0
        if offset.positive?
          lines = str.split("\n")
          lines[0] || ''
          rest = lines[1..] || []
          rest_indented = rest.map { |l| (' ' * offset) + l }
          str = "{\n#{rest_indented.join("\n")}"
        end
      rescue StandardError
        str = '__JSONIFY_FAILED__'
      end
    end
    str
  end

  # Mimic JSON.stringify(val, null, indent) from JavaScript.
  # indent == 0 → compact single-line. indent > 0 → pretty printed.
  # Map keys are emitted in insertion order (matches TS canonical).
  def self._json_stringify(val, indent, depth)
    return 'null' if val.nil?
    return val.to_s if [true, false].include?(val)
    return val.to_s if val.is_a?(Numeric)
    return JSON.generate(val) if val.is_a?(String)

    compact = indent.nil? || indent <= 0
    ind = compact ? '' : ' ' * indent
    current_indent = compact ? '' : ind * (depth + 1)
    closing_indent = compact ? '' : ind * depth
    open_nl = compact ? '' : "\n"
    pair_sep = compact ? ',' : ",\n"
    kv_sep = compact ? ':' : ': '

    if islist(val)
      return '[]' if val.empty?

      items_str = val.map { |v| current_indent + _json_stringify(v, indent, depth + 1) }
      "[#{open_nl}#{items_str.join(pair_sep)}#{open_nl}#{closing_indent}]"
    elsif ismap(val)
      return '{}' if val.empty?

      pairs = val.keys.map do |k|
        "#{current_indent}#{JSON.generate(k)}#{kv_sep}#{_json_stringify(val[k], indent, depth + 1)}"
      end
      "{#{open_nl}#{pairs.join(pair_sep)}#{open_nl}#{closing_indent}}"
    elsif isfunc(val)
      'null'
    else
      'null'
    end
  end

  def self.jm(*kv)
    result = {}
    i = 0
    while i < kv.length - 1
      result[kv[i].to_s] = kv[i + 1]
      i += 2
    end
    result
  end

  def self.jt(*v)
    v.to_a
  end

  def self.replace(s, from, to)
    return s.to_s unless s.is_a?(String)

    if from.is_a?(Regexp)
      s.gsub(from, to.to_s)
    else
      s.gsub(from.to_s, to.to_s)
    end
  end

  def self.keysof(val)
    return [] unless isnode(val)

    if ismap(val)
      val.keys.sort
    elsif islist(val)
      (0...val.length).map(&:to_s)
    else
      []
    end
  end

  # Group A reader: a key whose stored value is JSON null (nil) counts as
  # "no value", same rule as getprop (canonical TS: `null != getprop(val, key)`).
  def self.haskey(val = UNDEF, key = UNDEF)
    !getprop(val, key).nil?
  end

  # NOTE: this is a second, simpler joinurl definition that intentionally
  # overrides the join-based one above; kept for cross-language source parity.
  def self.joinurl(parts) # rubocop:disable Lint/DuplicateMethods
    parts.compact.map.with_index do |s, i|
      s = s.to_s
      if i.zero?
        s.sub(%r{/+$}, '')
      else
        s.sub(%r{([^/])/+}, '\1/').sub(%r{^/+}, '').sub(%r{/+$}, '')
      end
    end.reject(&:empty?).join('/')
  end

  # Get type name string from type bitfield value.
  def self._clz32(n)
    return 32 if n <= 0

    31 - (n.bit_length - 1)
  end

  def self.typename(t)
    t = t.to_i
    idx = _clz32(t)
    return TYPENAME[0] if idx.negative? || idx >= TYPENAME.length

    r = TYPENAME[idx]
    r.nil? || r == S_MT ? TYPENAME[0] : r
  end

  # Determine the type of a value as a bitfield integer.
  def self.typify(value = UNDEF)
    return T_noval if value.equal?(UNDEF)
    return T_scalar | T_null if value.nil?

    return T_scalar | T_boolean if [true, false].include?(value)

    return T_scalar | T_function if isfunc(value)

    return T_scalar | T_number | T_integer if value.is_a?(Integer)

    if value.is_a?(Float)
      return value.nan? ? T_noval : (T_scalar | T_number | T_decimal)
    end

    return T_scalar | T_string if value.is_a?(String)

    return T_scalar | T_symbol if value.is_a?(Symbol)

    return T_node | T_list if islist(value)

    return T_node | T_map if ismap(value)

    T_any
  end

  # Walk a data structure depth first, applying a function to each value.
  # The `path` argument passed to the before/after callbacks is a single
  # mutable array per depth, shared across all callback invocations for the
  # lifetime of this top-level walk call. Callbacks that need to store the
  # path MUST clone it (e.g. `path.dup`); the contents will otherwise be
  # overwritten by subsequent visits.
  def self.walk(val, before = nil, after = nil, maxdepth = nil, key: nil, parent: nil, path: nil, pool: nil)
    pool = [[]] if pool.nil?
    path = pool[0] if path.nil?

    depth = path.length

    _before = before
    _after = after

    out = _before.nil? ? val : _before.call(key, val, parent, path)

    md = maxdepth.is_a?(Numeric) && maxdepth >= 0 ? maxdepth : MAXDEPTH
    return out if md.zero? || (md.positive? && md <= depth)

    if isnode(out)
      child_depth = depth + 1
      child_path = pool[child_depth]
      if child_path.nil?
        child_path = Array.new(child_depth)
        pool[child_depth] = child_path
      end
      # Sync prefix [0..depth-1] from the current path. Only needed once per
      # parent: siblings share the same prefix and will each overwrite slot
      # [depth] below.
      i = 0
      while i < depth
        child_path[i] = path[i]
        i += 1
      end

      items(out).each do |ckey, child|
        child_path[depth] = ckey.to_s
        result = walk(child, _before, _after, md, key: ckey, parent: out, path: child_path, pool: pool)
        if ismap(out)
          out[ckey.to_s] = result
        elsif islist(out)
          out[ckey.to_i] = result
        end
      end
    end

    out = _after.call(key, out, parent, path) unless _after.nil?

    out
  end

  # --- Deep Merge Helpers for merge ---
  #
  # deep_merge recursively combines two nodes.
  # For hashes, keys in b override those in a.
  # For arrays, merge index-by-index; b's element overrides a's at that position,
  # while preserving items that b does not provide.
  def self.deep_merge(a, b)
    if ismap(a) && ismap(b)
      merged = a.dup
      b.each do |k, v|
        merged[k] = if merged.key?(k)
                      deep_merge(merged[k], v)
                    else
                      v
                    end
      end
      merged
    elsif islist(a) && islist(b)
      max_len = [a.size, b.size].max
      merged = []
      (0...max_len).each do |i|
        merged[i] = if i < a.size && i < b.size
                      deep_merge(a[i], b[i])
                    elsif i < b.size
                      b[i]
                    else
                      a[i]
                    end
      end
      merged
    else
      # For non-node values, b wins.
      b
    end
  end

  # --- Merge function ---
  # Merge a list of values. Later values have precedence.
  # Nodes override scalars. Matching node kinds merge recursively.
  def self.merge(val, maxdepth = nil)
    md = maxdepth.nil? ? MAXDEPTH : [maxdepth, 0].max

    return val unless islist(val)

    lenlist = val.length
    return nil if lenlist.zero?
    return val[0] if lenlist == 1

    out = getprop(val, 0, {})

    (1...lenlist).each do |oI|
      obj = val[oI]

      if isnode(obj)
        cur = [out]
        dst = [out]

        before_fn = lambda { |key, v, _parent, path|
          pI = path.length

          if md <= pI
            cur << nil while cur.length <= pI
            cur[pI] = v
            setprop(cur[pI - 1], key, v) if pI.positive? && pI - 1 < cur.length
            next nil # stop descending
          elsif !isnode(v)
            cur[pI] = v
          else
            # Extend arrays as needed
            dst << nil while dst.length <= pI
            cur << nil while cur.length <= pI

            dst[pI] = pI.positive? ? getprop(dst[pI - 1], key) : dst[pI]
            tval = dst[pI]

            if (islist(v) && islist(tval)) || (ismap(v) && ismap(tval))
              cur[pI] = tval
            else
              # Otherwise the override wins: it is copied, taking nothing from
              # the destination, so no later merge writes into it.
              cur[pI] = islist(v) ? [] : {}
              dst[pI] = nil
            end
          end

          v
        }

        after_fn = lambda { |key, _v, parent, path|
          cI = path.length
          if cI < 1
            next (cur.length.positive? ? cur[0] : _v)
          end

          target = cI - 1 < cur.length ? cur[cI - 1] : nil
          value = cI < cur.length ? cur[cI] : nil

          setprop(target, key, value) if target

          # walk writes this back into the override, so it is the override's
          # own child, read raw so a nil stays nil.
          _getprop(parent, key, nil)
        }

        out = walk(obj, before_fn, after_fn)
      else
        # Non-nodes (including nil) override directly
        out = obj
      end
    end

    if md.zero?
      out = getelem(val, -1)
      out = islist(out) ? [] : ismap(out) ? {} : out
    end

    out
  end

  # Get value at a key path deep inside a store.
  # Matches TS canonical: getpath(store, path, injdef?)
  def self.getpath(store, path, injdef = nil)
    # Operate on a string array.
    if islist(path)
      parts = []
      path.each do |part|
        if part.is_a?(Numeric)
          parts << _condensestr(part)
        elsif part.is_a?(String)
          parts << part
        else
          return nil
        end
      end
    elsif path.is_a?(String)
      parts = path.split(S_DT, -1)
    elsif path.is_a?(Numeric)
      parts = [_condensestr(path)]
    else
      return nil
    end

    # A condensed store answers a path as the node it was built from does,
    # touching only the nodes on the path. A base needs the whole node.
    if iscondensed(store)
      if _injdef_prop(injdef, 'base').nil?
        # A stored null reads as absent, as through getprop.
        return condenseMaterialise(store, condenseResolve(store, store[S_condroot], parts))
      end

      store = expand(store)
    end

    val = store

    # Extract injdef properties (support both Hash and object with accessors)
    if injdef.is_a?(Hash)
      base = injdef['base'] || injdef[:base]
      dparent = injdef['dparent'] || injdef[:dparent]
      inj_meta = injdef['meta'] || injdef[:meta]
      inj_key = injdef['key'] || injdef[:key]
      dpath = injdef['dpath'] || injdef[:dpath]
      handler = injdef['handler'] || injdef[:handler]
    elsif injdef.respond_to?(:base)
      base = injdef.base
      dparent = injdef.dparent
      inj_meta = injdef.meta
      inj_key = injdef.key
      dpath = injdef.dpath
      handler = injdef.handler
    else
      base = nil
      dparent = nil
      inj_meta = nil
      inj_key = nil
      dpath = nil
      handler = nil
    end

    src = base ? _getprop(store, base, store) : store
    numparts = parts.length

    # An empty path (incl empty string) just finds the src.
    if path.nil? || store.nil? || (numparts == 1 && parts[0] == S_MT) || numparts.zero?
      val = src
    elsif numparts.positive?
      # Check for $ACTIONs
      val = _getprop(store, parts[0], UNDEF) if numparts == 1

      unless isfunc(val)
        val = src

        # Check for meta path syntax
        if parts[0].is_a?(String) && (m = parts[0].match(/^([^$]+)\$([=~])(.+)$/)) && inj_meta
          val = _getprop(inj_meta, m[1], UNDEF)
          parts[0] = m[3]
        end

        pI = 0
        while !val.equal?(UNDEF) && !val.nil? && pI < numparts
          part = parts[pI]

          if injdef && part == '$KEY'
            part = inj_key || part
          elsif part.is_a?(String) && part.start_with?('$GET:')
            part = stringify(getpath(src, part[5..-2]))
          elsif part.is_a?(String) && part.start_with?('$REF:')
            part = stringify(getpath(_getprop(store, '$SPEC', UNDEF), part[5..-2]))
          elsif injdef && part.is_a?(String) && part.start_with?('$META:')
            part = stringify(getpath(inj_meta, part[6..-2]))
          end

          # $$ escapes $ (skip the gsub allocation for the common no-`$$` part)
          part = part.gsub('$$', '$') if part.is_a?(String) && part.include?('$$')

          if part == S_MT
            ascends = 0
            while pI + 1 < parts.length && parts[pI + 1] == S_MT
              ascends += 1
              pI += 1
            end

            if injdef && ascends.positive?
              ascends -= 1 if pI == parts.length - 1
              if ascends.zero?
                val = dparent
              else
                fullpath = flatten([slice(dpath, 0 - ascends), parts[(pI + 1)..]])
                val = if dpath.is_a?(Array) && ascends <= dpath.length
                        getpath(store, fullpath)
                      else
                        UNDEF
                      end
                break
              end
            else
              val = dparent || src
            end
          else
            val = _getprop(val, part, UNDEF)
          end
          pI += 1
        end
      end
    end

    # Injdef may provide a custom handler to modify found value.
    if handler && isfunc(handler)
      ref = pathify(path)
      val = handler.call(injdef, val.equal?(UNDEF) ? nil : val, ref, store)
    end

    val.equal?(UNDEF) ? nil : val
  end

  S_BKEY = '`$KEY`'.freeze
  S_BANNO = '`$ANNO`'.freeze
  S_BEXACT = '`$EXACT`'.freeze
  S_BVAL = '`$VAL`'.freeze
  S_DSPEC = '$SPEC'.freeze

  R_FULL_INJECT = /\A`(\$[A-Z]+|[^`]*)[0-9]*`\z/.freeze
  R_CHECKER_NAME = /\A\$[A-Z]+\z/.freeze
  R_PART_INJECT = /`([^`]*)`/.freeze
  R_META_PATH = /\A([^$]+)\$([=~])(.+)\z/.freeze
  R_DOUBLE_DOLLAR = /\$\$/.freeze

  # --- _injectstr: Resolve backtick expressions in strings ---
  def self._injectstr(val, store, inj = nil)
    return S_MT unless val.is_a?(String) && val != S_MT

    out = val
    m = R_FULL_INJECT.match(val)

    # Full string injection: "`path.ref`" or "`$CMD`"
    if m
      inj.full = true if inj

      pathref = m[1]
      pathref = pathref.gsub('$BT', S_BT).gsub('$DS', S_DS) if pathref.length > 3

      out = getpath(store, pathref, inj)

    else
      # Partial string injection: "prefix`ref`suffix"
      out = val.gsub(R_PART_INJECT) do |_match|
        ref = ::Regexp.last_match(1)
        ref = ref.gsub('$BT', S_BT).gsub('$DS', S_DS) if ref.length > 3

        inj.full = false if inj

        found = getpath(store, ref, inj)

        if found.nil?
          # Check if key exists in base data (nil = JSON null, vs not-found)
          base_data = _getprop(store, S_DTOP, store)
          ref_parts = ref.split(S_DT)
          exists = !_getprop(base_data, ref_parts[0], UNDEF).equal?(UNDEF)
          exists ? 'null' : S_MT
        elsif found.is_a?(String)
          found
        elsif isfunc(found)
          found
        else
          begin
            JSON.generate(found)
          rescue StandardError
            stringify(found)
          end
        end
      end

      # Call the inj handler on the entire string for custom injection.
      if inj && isfunc(inj.handler)
        inj.full = true
        out = inj.handler.call(inj, out, val, store)
      end
    end

    out
  end

  # --- inject: Recursively inject store values into a node ---
  # Matches TS canonical: inject(val, store, injdef?)
  def self.inject(val, store, injdef = nil)
    # Reuse existing Injection state during recursion; otherwise create new one.
    if injdef.is_a?(Injection)
      inj = injdef
    else
      parent = { S_DTOP => val }
      inj = Injection.new(val, parent)
      inj.handler = method(:_injecthandler)
      inj.base = S_DTOP
      inj.modify = _injdef_prop(injdef, 'modify')
      inj.meta = _injdef_prop(injdef, 'meta') || {}
      inj.errs = getprop(store, S_DERRS, [])
      inj.dparent = store
      inj.dpath = [S_DTOP]
      inj.root = parent

      h = _injdef_prop(injdef, 'handler')
      inj.handler = h if h
      dp = _injdef_prop(injdef, 'dparent')
      inj.dparent = dp if dp
      dpth = _injdef_prop(injdef, 'dpath')
      inj.dpath = dpth if dpth
      ex = _injdef_prop(injdef, 'extra')
      inj.extra = ex if ex
    end

    inj.descend

    # Descend into node.
    if isnode(val)
      if ismap(val)
        normal = val.keys.reject { |k| k.include?(S_DS) }.sort
        transforms = val.keys.select { |k| k.include?(S_DS) }.sort
        nodekeys = normal + transforms
      else
        nodekeys = (0...val.length).to_a
      end

      nkI = 0
      while nkI < nodekeys.length
        childinj = inj.child(nkI, nodekeys)
        nodekey = childinj.key
        childinj.mode = S_MKEYPRE

        prekey = _injectstr(nodekey, store, childinj)

        nkI = childinj.keyI
        nodekeys = childinj.keys

        unless prekey.nil?
          childinj.val = getprop(val, prekey)
          childinj.mode = S_MVAL

          inject(childinj.val, store, childinj)

          nkI = childinj.keyI
          nodekeys = childinj.keys

          childinj.mode = S_MKEYPOST
          _injectstr(nodekey, store, childinj)

          nkI = childinj.keyI
          nodekeys = childinj.keys
        end

        nkI += 1
      end

    elsif val.is_a?(String)
      inj.mode = S_MVAL
      val = _injectstr(val, store, inj)
      inj.setval(val) if val != SKIP
    end

    # Custom modification.
    if inj.modify && val != SKIP
      mkey = inj.key
      mparent = inj.parent
      mval = getprop(mparent, mkey)
      inj.modify.call(mval, mkey, mparent, inj)
    end

    inj.val = val

    # Read the top literally: a null stored there is the result.
    if inj.prior.nil? && ismap(inj.root)
      top = _getprop(inj.root, S_DTOP)
      return top unless top.equal?(UNDEF)
    end
    return getprop(inj.parent, S_DTOP) if inj.key == S_DTOP && inj.parent && haskey(inj.parent, S_DTOP)

    val
  end

  # Helper to read a property from injdef (Hash or object)
  def self._injdef_prop(injdef, key)
    return nil if injdef.nil?

    if injdef.is_a?(Hash)
      injdef[key] || injdef[key.to_sym]
    elsif injdef.respond_to?(key.to_sym)
      injdef.send(key.to_sym)
    end
  end

  # Default inject handler
  def self._injecthandler(inj, val, ref, store)
    out = val
    iscmd = isfunc(val) && (ref.nil? || (ref.is_a?(String) && ref.start_with?(S_DS)))

    if iscmd
      out = val.call(inj, val, ref, store)
    elsif inj.mode == S_MVAL && inj.full
      inj.setval(val)
    end

    out
  end

  # --- Transform commands ---

  def self.transform_DELETE(inj, _val, _ref, _store)
    inj.setval(UNDEF)
    nil
  end

  def self.transform_COPY(inj, _val, _ref, _store)
    mode = inj.mode
    key = inj.key

    out = nil
    if mode.start_with?('key')
      out = key
    else
      out = if isnode(inj.dparent)
              getprop(inj.dparent, key)
            else
              inj.path.length == 2 ? nil : inj.dparent
            end
      inj.setval(out)
    end
    out
  end

  def self.transform_KEY(inj, _val, _ref, _store)
    mode = inj.mode
    path = inj.path
    parent = inj.parent

    return inj.key if mode == S_MKEYPRE
    return nil if mode != S_MVAL

    keyspec = getprop(parent, S_BKEY)
    if keyspec
      delprop(parent, S_BKEY)
      return getprop(inj.dparent, keyspec)
    end

    return getprop(inj.dparent, inj.key) if ismap(inj.dparent) && inj.key && haskey(inj.dparent, inj.key)

    meta = getprop(parent, S_BANNO)
    getprop(meta, S_KEY, getprop(path, path.length - 2))
  end

  def self.transform_ANNO(inj, _val, _ref, _store)
    delprop(inj.parent, S_BANNO)
    nil
  end

  def self.transform_META(inj, _val, _ref, _store)
    delprop(inj.parent, S_DMETA)
    nil
  end

  def self.transform_MERGE(inj, _val, _ref, _store)
    mode = inj.mode
    key = inj.key
    parent = inj.parent

    if mode == S_MKEYPRE
      return key
    elsif mode == S_MKEYPOST
      args = getprop(parent, key)
      args = [args] unless islist(args)
      inj.setval(UNDEF)
      mergelist = [parent] + args + [clone(parent)]
      merge(mergelist)
      return key
    elsif mode == S_MVAL && islist(parent)
      return getprop(parent, inj.key) unless strkey(inj.key) == '0' && size(parent).positive?

      parent.delete_at(0)
      return getprop(parent, 0)

    end

    nil
  end

  def self.transform_EACH(inj, _val, _ref, store)
    mode = inj.mode
    keys_ = inj.keys
    path = inj.path
    parent = inj.parent
    nodes_ = inj.nodes

    keys_&.replace(keys_[0, 1])

    return nil if mode != S_MVAL || !path || !nodes_

    srcpath = parent[1] if parent.length > 1
    child_template = clone(parent[2]) if parent.length > 2

    srcstore = getprop(store, inj.base, store)
    src = getpath(srcstore, srcpath, inj)

    tkey = getelem(path, -2)
    target = nodes_.length >= 2 ? nodes_[-2] : nodes_[-1]

    rval = []

    if isnode(src)
      if islist(src)
        tval = src.map { clone(child_template) }
      else
        tval = []
        src.each_key do |k|
          cc = clone(child_template)
          setprop(cc, S_BANNO, { S_KEY => k }) if ismap(cc)
          tval << cc
        end
      end
      tcurrent = ismap(src) ? src.values : src

      if size(tval).positive?
        ckey = getelem(path, -2)
        tpath = path[0...-1]

        dpath = [S_DTOP]
        if srcpath.is_a?(String) && !srcpath.empty?
          srcpath.split(S_DT).each { |p| dpath << p if p != S_MT }
        end
        dpath << "$:#{ckey}" if ckey

        tcur = { ckey => tcurrent }

        if size(tpath) > 1
          pkey = getelem(path, -3, S_DTOP)
          tcur = { pkey => tcur }
          dpath << "$:#{pkey}"
        end

        tinj = inj.child(0, ckey ? [ckey] : [])
        tinj.path = tpath
        tinj.nodes = nodes_.length.positive? ? nodes_[0...-1] : []
        tinj.parent = getelem(tinj.nodes, -1)
        setprop(tinj.parent, ckey, tval) if ckey && tinj.parent
        tinj.val = tval
        tinj.dpath = dpath
        tinj.dparent = tcur

        inject(tval, store, tinj)
        rval = tinj.val
      end
    end

    setprop(target, tkey, rval)
    islist(rval) && size(rval).positive? ? rval[0] : nil
  end

  def self.transform_PACK(inj, _val, _ref, store)
    mode = inj.mode
    key = inj.key
    path = inj.path
    parent = inj.parent
    nodes_ = inj.nodes

    return nil if mode != S_MKEYPRE || !key.is_a?(String) || !path || !nodes_

    args_val = getprop(parent, key)
    return nil if !islist(args_val) || size(args_val) < 2

    srcpath = args_val[0]
    origchildspec = args_val[1]

    tkey = getelem(path, -2)
    pathsize = size(path)
    target = getelem(nodes_, pathsize - 2, -> { getelem(nodes_, pathsize - 1) })

    srcstore = getprop(store, inj.base, store)
    src = getpath(srcstore, srcpath, inj)

    unless islist(src)
      if ismap(src)
        new_src = []
        items(src).each do |item|
          setprop(item[1], S_BANNO, { S_KEY => item[0] })
          new_src << item[1]
        end
        src = new_src
      else
        src = nil
      end
    end

    return nil if src.nil?

    keypath = getprop(origchildspec, S_BKEY)
    childspec = delprop(clone(origchildspec), S_BKEY)
    child = getprop(childspec, S_BVAL, childspec)

    tval = {}
    items(src).each do |item|
      srckey = item[0]
      srcnode = item[1]

      k = srckey
      if keypath
        k = if keypath.is_a?(String) && keypath.start_with?(S_BT)
              inject(keypath, merge([{}, store, { S_DTOP => srcnode }], 1))
            else
              getpath(srcnode, keypath, inj)
            end
      end

      tchild = clone(child)
      setprop(tval, k, tchild)

      anno = getprop(srcnode, S_BANNO)
      if anno.nil?
        delprop(tchild, S_BANNO)
      else
        setprop(tchild, S_BANNO, anno)
      end
    end

    rval = {}

    unless isempty(tval)
      tsrc = {}
      src.each_with_index do |n, i|
        kn = if keypath.nil?
               i
             elsif keypath.is_a?(String) && keypath.start_with?(S_BT)
               inject(keypath, merge([{}, store, { S_DTOP => n }], 1))
             else
               getpath(n, keypath, inj)
             end
        setprop(tsrc, kn, n)
      end

      tpath = slice(inj.path, -1)
      ckey = getelem(inj.path, -2)
      dpath = flatten([S_DTOP, srcpath.to_s.split(S_DT), "$:#{ckey}"])

      tcur = { ckey => tsrc }
      if size(tpath) > 1
        pkey = getelem(inj.path, -3, S_DTOP)
        tcur = { pkey => tcur }
        dpath << "$:#{pkey}"
      end

      tinj = inj.child(0, [ckey])
      tinj.path = tpath
      tinj.nodes = slice(inj.nodes, -1)
      tinj.parent = getelem(tinj.nodes, -1)
      tinj.val = tval
      tinj.dpath = dpath
      tinj.dparent = tcur

      inject(tval, store, tinj)
      rval = tinj.val
    end

    setprop(target, tkey, rval)
    nil
  end

  def self.transform_REF(inj, _val, _ref, store)
    return nil if inj.mode != S_MVAL

    refpath = getprop(inj.parent, 1)
    inj.keyI = size(inj.keys)

    specFn = getprop(store, S_DSPEC)
    spec = isfunc(specFn) ? specFn.call : nil

    dpath = slice(inj.path, 1)
    ref = getpath(spec, refpath, {
                    'dpath' => dpath,
                    'dparent' => getpath(spec, dpath)
                  })

    hasSubRef = false
    if isnode(ref)
      walk(ref, lambda { |_k, v, *_a|
        hasSubRef = true if v == '`$REF`'
        v
      })
    end

    # A recursive reference stops where the data does.
    tval = getpath(store, slice(inj.path, -1))
    rval = !hasSubRef || !tval.nil? ? clone(ref) : nil

    # The enclosing loop injects the referenced spec in this list's place, so
    # neither this pass nor this element leaves a value for modify to check.
    grandparent = inj.setval(rval, 2)

    prior = inj.prior
    if prior
      prior.modify = nil
      prior.keyI -= 1 if islist(grandparent) || !rval.nil?
    end

    SKIP
  end

  FORMATTER = {
    'identity' => ->(_k, v, *_a) { v },
    'upper' => ->(_k, v, *_a) { isnode(v) ? v : (v.nil? ? 'null' : v.to_s).upcase },
    'lower' => ->(_k, v, *_a) { isnode(v) ? v : (v.nil? ? 'null' : v.to_s).downcase },
    'string' => ->(_k, v, *_a) { isnode(v) ? v : (v.nil? ? 'null' : v.to_s) },
    'number' => lambda { |_k, v, *_a|
      if isnode(v)
        v
      else
        n = begin
          Float(v)
        rescue StandardError
          0
        end
        n
      end
    },
    'integer' => lambda { |_k, v, *_a|
      if isnode(v)
        v
      else
        n = begin
          Integer(Float(v))
        rescue StandardError
          0
        end
        n
      end
    },
    'concat' => lambda { |k, v, *_a|
      if k.nil? && islist(v)
        items(v, ->(n) { isnode(n[1]) ? '' : (n[1].nil? ? 'null' : n[1].to_s) }).join
      else
        v
      end
    }
  }.freeze

  def self.transform_FORMAT(inj, _val, _ref, store)
    slice(inj.keys, 0, 1, true)
    return nil if inj.mode != S_MVAL

    name = getprop(inj.parent, 1)
    child = getprop(inj.parent, 2)

    tkey = getelem(inj.path, -2)
    target = getelem(inj.nodes, -2, -> { getelem(inj.nodes, -1) })

    cinj = injectChild(child, store, inj)
    resolved = cinj.val

    formatter = T_function.anybits?(typify(name)) ? name : FORMATTER[name]

    if formatter.nil?
      inj.errs << "$FORMAT: unknown format: #{name}."
      return nil
    end

    out = walk(resolved, formatter)
    setprop(target, tkey, out)
    out
  end

  def self.transform_APPLY(inj, _val, _ref, store)
    ijname = 'APPLY'
    return nil unless checkPlacement(M_VAL, ijname, T_list, inj)

    args = slice(inj.parent, 1)
    args_list = islist(args) ? args : []
    err, apply, child = injectorArgs([T_function, T_any], args_list)
    if err
      inj.errs << "$#{ijname}: #{err}"
      return nil
    end

    tkey = getelem(inj.path, -2)
    target = getelem(inj.nodes, -2, -> { getelem(inj.nodes, -1) })

    cinj = injectChild(child, store, inj)
    resolved = cinj.val

    out = apply.call(resolved, store, cinj)
    setprop(target, tkey, out)
    out
  end

  def self.checkPlacement(modes, ijname, parentTypes, inj)
    mode_num = { S_MKEYPRE => M_KEYPRE, S_MKEYPOST => M_KEYPOST, S_MVAL => M_VAL }
    mode_int = mode_num[inj.mode] || 0
    if modes.nobits?(mode_int)
      expected = [M_KEYPRE, M_KEYPOST, M_VAL].reject { |m| modes.nobits?(m) }
      expected = expected.map { |m| PLACEMENT[m] }.join(',')
      inj.errs << "$#{ijname}: invalid placement as #{PLACEMENT[mode_int] || ''}, expected: #{expected}."
      return false
    end
    unless isempty(parentTypes)
      ptype = typify(inj.parent)
      if parentTypes.nobits?(ptype)
        inj.errs << "$#{ijname}: invalid placement in parent #{typename(ptype)}, expected: #{typename(parentTypes)}."
        return false
      end
    end
    true
  end

  def self.injectorArgs(argTypes, args)
    numargs = size(argTypes)
    found = Array.new(1 + numargs)
    found[0] = nil
    (0...numargs).each do |argI|
      arg = args[argI]
      argType = typify(arg)
      if argTypes[argI].nobits?(argType)
        found[0] =
          "invalid argument: #{stringify(arg, 22)} (#{typename(argType)} at position #{1 + argI}) " \
          "is not of type: #{typename(argTypes[argI])}."
        break
      end
      found[1 + argI] = arg
    end
    found
  end

  def self.injectChild(child, store, inj)
    cinj = inj
    if inj.prior
      if inj.prior.prior
        cinj = inj.prior.prior.child(inj.prior.keyI, inj.prior.keys)
        cinj.val = child
        setprop(cinj.parent, inj.prior.key, child)
      else
        cinj = inj.prior.child(inj.keyI, inj.keys)
        cinj.val = child
        setprop(cinj.parent, inj.key, child)
      end
    end
    inject(child, store, cinj)
    cinj
  end

  # --- transform: Transform data using spec ---
  def self.transform(data, spec, injdef = nil)
    origspec = spec
    spec = clone(spec)

    extra = _injdef_prop(injdef, 'extra')
    collect = !_injdef_prop(injdef, 'errs').nil?
    errs = collect ? _injdef_prop(injdef, 'errs') : []

    extraTransforms = {}
    extraData = {}

    if extra && isnode(extra)
      items(extra).each do |item|
        k, v = item
        if k.is_a?(String) && k.start_with?(S_DS)
          extraTransforms[k] = v
        else
          extraData[k] = v
        end
      end
    end

    data_clone = merge([
                         isempty(extraData) ? nil : clone(extraData),
                         clone(data)
                       ])

    store = {
      S_DTOP => data_clone,
      S_DSPEC => -> { origspec },
      '$BT' => ->(*_a) { S_BT },
      '$DS' => ->(*_a) { S_DS },
      '$WHEN' => ->(*_a) { Time.now.iso8601 },
      '$DELETE' => method(:transform_DELETE),
      '$COPY' => method(:transform_COPY),
      '$KEY' => method(:transform_KEY),
      '$ANNO' => method(:transform_ANNO),
      '$META' => method(:transform_META),
      '$MERGE' => method(:transform_MERGE),
      '$EACH' => method(:transform_EACH),
      '$PACK' => method(:transform_PACK),
      '$REF' => method(:transform_REF),
      '$FORMAT' => method(:transform_FORMAT),
      '$APPLY' => method(:transform_APPLY)
    }
    extraTransforms.each { |k, v| store[k] = v }
    store[S_DERRS] = errs

    injdef = {} if injdef.nil?
    injdef = {} unless injdef.is_a?(Hash)
    injdef = injdef.merge('errs' => errs)

    out = inject(spec, store, injdef)

    raise errs.join(' | ') if !errs.empty? && !collect

    out
  end

  # --- Validators ---

  def self._invalidTypeMsg(path, needtype, vt, v, _whence = nil)
    vs = v.nil? || v.equal?(UNDEF) ? 'no value' : stringify(v)
    "Expected #{if size(path) > 1
                  "field #{pathify(path,
                                   1)} to be "
                end}#{needtype}, but found #{typename(vt) + S_VIZ unless v.nil? || v.equal?(UNDEF)}#{vs}."
  end

  # Names a validate spec may use besides its checkers: transform's that it keeps, and $OPEN.
  VALIDATE_NAMES = %w[$TOP $SPEC $BT $DS $WHEN $ANNO $REF $FORMAT $APPLY $OPEN].freeze

  # Report each checker the spec names that validate lacks; $EXACT's arguments are literals.
  def self._checknames(spec, store, path, errs)
    name = _refname(spec)
    unless name.nil?
      errs << "Unknown validator #{name} at field #{pathify(path)}." if _unknownname(name, store)
      return
    end

    return if islist(spec) && _refname(spec[0]) == '$EXACT'

    keysof(spec).each do |key|
      _checknames(key, store, path, errs) if ismap(spec)
      _checknames(_getprop(spec, key), store, flatten([path, key]), errs)
    end
  end

  # The name a whole-string reference gives, when it is a checker name in any case.
  def self._refname(val)
    m = val.is_a?(String) ? R_FULL_INJECT.match(val) : nil
    !m.nil? && R_CHECKER_NAME.match?(m[1].upcase) ? m[1] : nil
  end

  # Unknown: undefined and upper case, or a defined name in another case. Null disables a name.
  def self._unknownname(name, store)
    known = ->(n) { VALIDATE_NAMES.include?(n) || !getprop(store, n).nil? }
    upper = name.upcase
    !known.call(name) && (upper == name || known.call(upper))
  end

  # The data value at a list directive's slot. The directive's own dparent was
  # read with getprop, which reports a stored null as absent.
  def self._slotval(inj)
    prior = inj.prior
    prior.nil? ? inj.dparent : _getprop(prior.dparent, prior.key)
  end

  # Replace a list directive's list with the data value. setval deletes on
  # nil, so a null is set as itself.
  def self._setslot(inj, val)
    return inj.setval(val, 2) unless val.nil?

    setprop(getelem(inj.nodes, -2), getelem(inj.path, -2), nil)
  end

  # JSON equality: numbers by value, lists in order, maps by key in any order.
  def self._deepequal(a, b)
    return true if a.equal?(b)

    atype = typify(a)
    btype = typify(b)
    return a == b if T_number.anybits?(atype) && T_number.anybits?(btype)
    return a == b if T_string.anybits?(atype) && T_string.anybits?(btype)
    return false if atype != btype || !isnode(a)

    akeys = keysof(a)
    bkeys = keysof(b)
    return false if akeys.length != bkeys.length

    akeys.each_with_index.all? do |k, kI|
      k == bkeys[kI] && _deepequal(_getprop(a, k), _getprop(b, k))
    end
  end

  # Every member val has is in out, unchanged. A member only out has is a
  # default the spec supplied, and is ignored.
  def self._keeps(val, out)
    return true if val.equal?(UNDEF)
    return _deepequal(val, out) if !isnode(val) || islist(val) != islist(out) || !isnode(out)

    keysof(val).all? { |k| _keeps(_getprop(val, k), _getprop(out, k)) }
  end

  # A spec admits a value when validating the value against it finds no error
  # and gives back the value as it is.
  def self._admits(val, spec, inj, store)
    terrs = []

    vstore = merge([{}, store], 1)
    vstore[S_DTOP] = val

    out = validate(val, spec, {
                     'extra' => vstore,
                     'errs' => terrs,
                     'meta' => inj.meta
                   })

    terrs.empty? && _keeps(val, out)
  end

  # The bounds of a $NOF count, and the words for it, which are nil when the
  # count is invalid. Without a max, the bound is the number of specs.
  def self._nofcount(count, numtvals)
    isnat = ->(n) { T_integer.anybits?(typify(n)) && n >= 0 }
    # JavaScript has one number type, so 2.0 is the count 2.
    whole = ->(n) { n.is_a?(Float) && n.finite? && n == n.to_i ? n.to_i : n }

    count = whole.call(count)
    return [count, count, count.zero? ? 'none' : "exactly #{count}"] if isnat.call(count)

    min = whole.call(_getprop(count, 'min'))
    max = whole.call(_getprop(count, 'max'))
    nomin = min.equal?(UNDEF)
    nomax = max.equal?(UNDEF)

    valid =
      ismap(count) &&
      size(count).positive? &&
      size(count) == (nomin ? 0 : 1) + (nomax ? 0 : 1) &&
      (nomin || isnat.call(min)) &&
      (nomax || isnat.call(max)) &&
      (nomin || nomax || min <= max)

    return [0, 0, nil] unless valid

    lo = nomin ? 0 : min
    hi = nomax ? numtvals : max

    desc =
      if nomax
        "at least #{lo}"
      elsif hi.zero?
        'none'
      elsif nomin
        "at most #{hi}"
      elsif lo == hi
        "exactly #{lo}"
      else
        "#{lo} to #{hi}"
      end

    [lo, hi, desc]
  end

  def self.validate_STRING(inj, _val = nil, _ref = nil, _store = nil)
    out = getprop(inj.dparent, inj.key)
    t = typify(out)
    if T_string.nobits?(t)
      inj.errs << _invalidTypeMsg(inj.path, S_string, t, out, 'V1010')
      return nil
    end
    if out == S_MT
      inj.errs << "Empty string at #{pathify(inj.path, 1)}"
      return nil
    end
    out
  end

  TYPE_CHECKS = {
    S_number => ->(v) { v.is_a?(Numeric) && ![true, false].include?(v) },
    S_integer => ->(v) { v.is_a?(Integer) && ![true, false].include?(v) },
    S_decimal => ->(v) { v.is_a?(Float) },
    S_boolean => ->(v) { [true, false].include?(v) },
    S_null => lambda(&:nil?),
    S_nil => ->(v) { v.nil? || v.equal?(UNDEF) },
    S_map => ->(v) { v.is_a?(Hash) },
    S_list => ->(v) { v.is_a?(Array) },
    S_function => ->(v) { v.respond_to?(:call) },
    S_instance => lambda { |v|
      !v.is_a?(Hash) && !v.is_a?(Array) && !v.is_a?(String) &&
        !v.is_a?(Numeric) && ![true, false].include?(v) && !v.nil? && !v.equal?(UNDEF)
    }
  }.freeze

  def self.validate_TYPE(inj, _val = nil, ref = nil, _store = nil)
    tname = ref.is_a?(String) && ref.length > 1 ? ref[1..].downcase : S_any
    idx = TYPENAME.index(tname)
    typev = idx ? (1 << (31 - idx)) : 0

    # $NIL is absent or null.
    typev |= T_null if tname == S_nil

    # Read literally: a missing field, or a trial's UNDEF root, is no value, not null.
    out = _getprop(inj.dparent, inj.key)
    t = typify(out)

    if t.nobits?(typev)
      inj.errs << _invalidTypeMsg(inj.path, tname, t, out, 'V1001')
      return nil
    end
    _keepnull(inj, out)
  end

  def self.validate_ANY(inj, _val = nil, _ref = nil, _store = nil)
    _keepnull(inj, getprop(inj.dparent, inj.key))
  end

  # A checker's accepted value, where a null the data holds stays in the output:
  # returned as nil, inject's setval would delete the slot instead.
  def self._keepnull(inj, out)
    return out unless out.nil? && inj.mode == S_MVAL && !_getprop(inj.dparent, inj.key).equal?(UNDEF)

    setprop(inj.parent, inj.key, nil)
    SKIP
  end

  def self.validate_CHILD(inj, _val = nil, _ref = nil, _store = nil)
    mode = inj.mode
    key = inj.key
    parent = inj.parent
    path = inj.path
    keys = inj.keys

    if mode == S_MKEYPRE
      childtm = getprop(parent, key)
      pkey = getelem(path, -2)
      tval = getprop(inj.dparent, pkey)

      if tval.nil?
        tval = {}
      elsif !ismap(tval)
        # _validation reports the mismatch, once.
        return nil
      end

      keysof(tval).each do |ckey|
        setprop(parent, ckey, clone(childtm))
        keys << ckey
      end

      inj.setval(UNDEF)
      return nil
    end

    if mode == S_MVAL
      unless islist(parent)
        inj.errs << 'Invalid $CHILD as value'
        return nil
      end

      childtm = getprop(parent, 1)

      if inj.dparent.nil?
        parent.clear
        return nil
      end

      unless islist(inj.dparent)
        inj.keyI = size(parent)
        return inj.dparent
      end

      items(inj.dparent).each do |n|
        setprop(parent, n[0], clone(childtm))
      end
      parent.slice!(inj.dparent.length..-1) if parent.length > inj.dparent.length

      # NOTE: modifying inj! This extends the child value loop in inject
      # to cover every cloned child.
      (size(keys)...size(parent)).each do |ckeyI|
        keys << strkey(ckeyI)
      end

      # Restart the child value loop at the first element (the loop
      # increments keyI on resume) so that the first element is also
      # validated against the child template.
      inj.keyI = -1

      # SKIP leaves the cloned child template in place at the first
      # element so the resumed loop can validate it.
      return SKIP
    end

    nil
  end

  def self.validate_EXACT(inj, _val = nil, _ref = nil, _store = nil)
    mode = inj.mode
    parent = inj.parent
    key = inj.key
    keyI = inj.keyI

    if mode == S_MVAL
      if !islist(parent) || keyI != 0
        inj.errs << "The $EXACT validator at field #{pathify(inj.path, 1, 1)} must be the first element of an array."
        return nil
      end

      cval = _slotval(inj)

      inj.keyI = size(inj.keys)

      # Replace [$EXACT, ...] with the data value; SKIP keeps inject off the detached list.
      _setslot(inj, cval)

      inj.path = inj.path[0...-1]

      tvals = parent[1..]
      if size(tvals).zero?
        inj.errs << "The $EXACT validator at field #{pathify(inj.path, 1, 1)} must have at least one argument."
        return SKIP
      end

      tvals.each do |tval|
        return SKIP if _deepequal(tval, cval)
      end

      valdesc = items(tvals).map { |n| stringify(n[1]) }.join(', ')
      valdesc = valdesc.gsub(/`\$([A-Z]+)`/) { ::Regexp.last_match(1).downcase }

      inj.errs << _invalidTypeMsg(
        inj.path,
        "#{'value ' unless size(inj.path) > 1}exactly equal to #{'one of ' unless size(tvals) == 1}#{valdesc}",
        typify(cval), cval, 'V0110'
      )

      SKIP
    else
      delprop(parent, key)
    end
  end

  # Count the specs that admit the value: ['`$NOF`', count, spec, ...], where
  # count is an integer, or a map holding min, max or both.
  def self.validate_NOF(inj, _val = nil, _ref = nil, store = nil)
    _validatecount(inj, store, '$NOF', true)
  end

  # Every spec admits the value: ['`$ALL`', spec, ...].
  def self.validate_ALL(inj, _val = nil, _ref = nil, store = nil)
    _validatecount(inj, store, '$ALL', false)
  end

  # The counting list directives. Without a count, every spec has to admit.
  def self._validatecount(inj, store, name, counted)
    parent = inj.parent

    return nil unless inj.mode == S_MVAL

    if !islist(parent) || inj.keyI != 0
      inj.errs << "The #{name} validator at field #{pathify(inj.path, 1, 1)} must be the first element of an array."
      return nil
    end

    cval = _slotval(inj)

    inj.keyI = size(inj.keys)

    # Replace the directive's list with the data value. Each return is SKIP, so
    # that inject leaves the detached list alone and validates nothing in it.
    _setslot(inj, cval)

    inj.path = slice(inj.path, -1)

    count = counted ? _getprop(parent, 1) : UNDEF
    tvals = slice(parent, counted ? 2 : 1)
    numtvals = size(tvals)
    field = "The #{name} validator at field #{pathify(inj.path, 1)}"

    if numtvals.zero?
      inj.errs << "#{field}#{counted ? ' must have a count and' : ' must have'} at least one argument."
      return SKIP
    end

    lo, hi, countdesc = counted ? _nofcount(count, numtvals) : [numtvals, numtvals, 'all']

    if countdesc.nil?
      inj.errs << "#{field} has an invalid count: #{stringify(count)}."
      return SKIP
    end

    admitted = 0
    tvals.each_with_index do |tval, tI|
      left = numtvals - tI

      # Stop once the specs left cannot change the verdict.
      break if hi < admitted || admitted + left < lo || (lo <= admitted && admitted + left <= hi)

      admitted += 1 if _admits(cval, tval, inj, store)
    end

    if admitted < lo || hi < admitted
      valdesc = items(tvals).map { |n| stringify(n[1]) }.join(', ')
      valdesc = valdesc.gsub(/`\$([A-Z]+)`/) { ::Regexp.last_match(1).downcase }

      inj.errs << _invalidTypeMsg(inj.path, "#{countdesc} of #{valdesc}", typify(cval), cval, 'V0310')
    end

    SKIP
  end

  # The value's length is within a bound: ['`$LEN`', bound, spec?], where the
  # bound is as for a $NOF count. A string's length is in code points.
  def self.validate_LEN(inj, _val = nil, _ref = nil, store = nil)
    _validatebound(inj, store, '$LEN')
  end

  # The value is a number within a bound: ['`$RANGE`', bound, spec?], where the
  # bound holds min or gt, max or lt, or one of each.
  def self.validate_RANGE(inj, _val = nil, _ref = nil, store = nil)
    _validatebound(inj, store, '$RANGE')
  end

  def self.validate_LIKE(inj, _val = nil, _ref = nil, store = nil)
    _validatebound(inj, store, '$LIKE')
  end

  # The bounding list directives: a bound or pattern, then at most one spec that also admits.
  def self._validatebound(inj, store, name)
    parent = inj.parent

    return nil unless inj.mode == S_MVAL

    if !islist(parent) || inj.keyI != 0
      inj.errs << "The #{name} validator at field #{pathify(inj.path, 1, 1)} must be the first element of an array."
      return nil
    end

    cval = _slotval(inj)

    inj.keyI = size(inj.keys)

    # As for the counting directives: SKIP keeps inject off the detached list.
    _setslot(inj, cval)

    inj.path = slice(inj.path, -1)

    field = "The #{name} validator at field #{pathify(inj.path, 1)}"
    nargs = size(parent) - 1
    islen = name == '$LEN'
    islike = name == '$LIKE'
    argname = islike ? 'pattern' : 'bound'

    if nargs < 1 || nargs > 2
      inj.errs << "#{field} must have a #{argname} and at most one spec."
      return SKIP
    end

    bound = _getprop(parent, 1)
    like = islike ? _likere(bound) : nil
    lo, hi, desc =
      if islen
        _lenbound(bound)
      elsif islike
        [0, 0, like.nil? ? nil : "like /#{bound}/"]
      else
        [0, 0, _rangedesc(bound)]
      end

    if desc.nil?
      inj.errs << "#{field} has an invalid #{argname}: #{stringify(bound)}."
      return SKIP
    end

    ctype = typify(cval)

    if nargs == 2 && !_admits(cval, _getprop(parent, 2), inj, store)
      specdesc = stringify(_getprop(parent, 2)).gsub(/`\$([A-Z]+)`/) { ::Regexp.last_match(1).downcase }
      inj.errs << _invalidTypeMsg(inj.path, specdesc, ctype, cval, 'V0410')
      return SKIP
    end

    if (islen ? T_string | T_list | T_map : islike ? T_string : T_number).nobits?(ctype)
      needtype = islen ? 'string, list or map' : islike ? S_string : S_number
      inj.errs << _invalidTypeMsg(inj.path, needtype, ctype, cval, 'V0420')
      return SKIP
    end

    length = islen ? size(cval) : 0
    inbound =
      if islen
        lo <= length && (hi == -1 || length <= hi)
      elsif islike
        re_test(like, cval)
      else
        _inrange(bound, cval)
      end

    unless inbound
      needtype = "#{'value ' unless size(inj.path) > 1}#{desc}"
      inj.errs << _invalidTypeMsg(inj.path, needtype, ctype, cval, 'V0430')
    end

    SKIP
  end

  # The bounds of a $LEN bound, with -1 for no maximum, and the words for it,
  # which are nil when the bound is invalid.
  def self._lenbound(bound)
    lo, hi, countdesc = _nofcount(bound, -1)

    return [0, 0, nil] if countdesc.nil?

    desc =
      if lo == hi
        lo.to_s
      elsif hi == -1
        "at least #{lo}"
      elsif lo.zero?
        "at most #{hi}"
      else
        "#{lo} to #{hi}"
      end

    [lo, hi, "of length #{desc}"]
  end

  # A $LIKE pattern compiled by the port's own regex engine; nil unless it compiles.
  def self._likere(pattern)
    return nil unless pattern.is_a?(String)

    re_compile(pattern)
  rescue RegexpError
    nil
  end

  # The words for a $RANGE bound, which are nil when the bound is invalid.
  def self._rangedesc(bound)
    return nil unless ismap(bound)

    min = _getprop(bound, 'min')
    max = _getprop(bound, 'max')
    gt = _getprop(bound, 'gt')
    lt = _getprop(bound, 'lt')
    sides = [min, max, gt, lt].reject { |n| n.equal?(UNDEF) }
    lower = min.equal?(UNDEF) ? gt : min
    upper = max.equal?(UNDEF) ? lt : max

    valid =
      size(bound).positive? &&
      size(bound) == sides.length &&
      (min.equal?(UNDEF) || gt.equal?(UNDEF)) &&
      (max.equal?(UNDEF) || lt.equal?(UNDEF)) &&
      sides.all? { |n| T_number.anybits?(typify(n)) } &&
      (lower.equal?(UNDEF) || upper.equal?(UNDEF) || lower <= upper)

    return nil unless valid

    parts = []

    if !min.equal?(UNDEF)
      parts << "at least #{stringify(min)}"
    elsif !gt.equal?(UNDEF)
      parts << "greater than #{stringify(gt)}"
    end

    if !max.equal?(UNDEF)
      parts << "at most #{stringify(max)}"
    elsif !lt.equal?(UNDEF)
      parts << "less than #{stringify(lt)}"
    end

    parts.join(' and ')
  end

  # A number within a valid $RANGE bound.
  def self._inrange(bound, val)
    min = _getprop(bound, 'min')
    max = _getprop(bound, 'max')
    gt = _getprop(bound, 'gt')
    lt = _getprop(bound, 'lt')

    (min.equal?(UNDEF) || min <= val) &&
      (max.equal?(UNDEF) || val <= max) &&
      (gt.equal?(UNDEF) || gt < val) &&
      (lt.equal?(UNDEF) || val < lt)
  end

  # --- _validation: Modify callback for validate ---
  def self._validation(pval, key, parent, inj)
    return if inj.nil?
    return if pval == SKIP

    exact = getprop(inj.meta, S_BEXACT, false)
    cval = getprop(inj.dparent, key)

    return if !exact && cval.nil?

    ptype = typify(pval)
    return if T_string.anybits?(ptype) && pval.is_a?(String) && pval.include?(S_DS)

    ctype = typify(cval)

    if ptype != ctype && !pval.nil?
      inj.errs << _invalidTypeMsg(inj.path, typename(ptype), ctype, cval, 'V0010')
      return
    end

    if ismap(cval)
      unless ismap(pval)
        inj.errs << _invalidTypeMsg(inj.path, typename(ptype), ctype, cval, 'V0020')
        return
      end

      ckeys = keysof(cval)
      pkeys = keysof(pval)

      if pkeys.length.positive? && getprop(pval, '`$OPEN`') != true
        # Literal presence: the shape DECLARES ck even when its value is nil.
        # Canonical uses `NONE === _lookup`; `haskey` is Group A (value-based)
        # and would drop records with a nil field from an open ($AND) select.
        badkeys = ckeys.reject { |ck| pval.is_a?(Hash) && pval.key?(strkey(ck)) }
        if badkeys.length.positive?
          inj.errs << "Unexpected keys at field #{pathify(inj.path, 1)}#{S_VIZ}#{join(badkeys, ', ')}"
        end
      else
        merge([pval, cval])
        delprop(pval, '`$OPEN`') if isnode(pval)
      end

    elsif islist(cval)
      inj.errs << _invalidTypeMsg(inj.path, typename(ptype), ctype, cval, 'V0030') unless islist(pval)

    elsif exact
      # In exact mode, check key existence for nil values
      if cval.nil? && pval.nil?
        # Both nil: only match if key actually exists in data
        if ismap(inj.dparent) && !inj.dparent.key?(key.to_s)
          inj.errs << "Value at field #{pathify(inj.path, 1)}: key not present."
        end
      elsif cval != pval
        pathmsg = size(inj.path) > 1 ? "at field #{pathify(inj.path, 1)}: " : ''
        inj.errs << "Value #{pathmsg}#{cval} should equal #{pval}."
      end

    else
      setprop(parent, key, cval)
    end
  end

  def self._validatehandler(inj, val, ref, store)
    out = val
    m = ref.is_a?(String) ? R_META_PATH.match(ref) : nil

    if m
      if m[2] == '='
        inj.setval([S_BEXACT, val])
      else
        inj.setval(val)
      end
      inj.keyI = -1
      out = SKIP
    else
      out = _injecthandler(inj, val, ref, store)
    end

    out
  end

  # --- validate: Validate data against shape spec ---
  def self.validate(data, spec, injdef = nil)
    extra = _injdef_prop(injdef, 'extra')
    collect = !_injdef_prop(injdef, 'errs').nil?
    errs = collect ? _injdef_prop(injdef, 'errs') : []

    store = merge([
                    {
                      '$DELETE' => nil, '$COPY' => nil, '$KEY' => nil, '$META' => nil,
                      '$MERGE' => nil, '$EACH' => nil, '$PACK' => nil,

                      '$STRING' => method(:validate_STRING),
                      '$NUMBER' => method(:validate_TYPE),
                      '$INTEGER' => method(:validate_TYPE),
                      '$DECIMAL' => method(:validate_TYPE),
                      '$BOOLEAN' => method(:validate_TYPE),
                      '$NULL' => method(:validate_TYPE),
                      '$NIL' => method(:validate_TYPE),
                      '$MAP' => method(:validate_TYPE),
                      '$LIST' => method(:validate_TYPE),
                      '$FUNCTION' => method(:validate_TYPE),
                      '$INSTANCE' => method(:validate_TYPE),
                      '$ANY' => method(:validate_ANY),
                      '$CHILD' => method(:validate_CHILD),
                      '$EXACT' => method(:validate_EXACT),
                      '$NOF' => method(:validate_NOF),
                      '$ALL' => method(:validate_ALL),
                      '$LEN' => method(:validate_LEN),
                      '$RANGE' => method(:validate_RANGE),
                      '$LIKE' => method(:validate_LIKE)
                    },
                    (extra.nil? ? {} : extra),
                    { S_DERRS => errs }
                  ], 1)

    meta = _injdef_prop(injdef, 'meta') || {}
    setprop(meta, S_BEXACT, getprop(meta, S_BEXACT, false)) if ismap(meta)

    # A spec that names an unknown checker validates nothing.
    numerrs = errs.length
    _checknames(spec, store, [], errs)

    out =
      if numerrs < errs.length
        clone(data)
      else
        transform(data, spec, {
                    'meta' => meta,
                    'extra' => store,
                    'modify' => method(:_validation),
                    'handler' => method(:_validatehandler),
                    'errs' => errs
                  })
      end

    raise errs.join(' | ') if !errs.empty? && !collect

    out
  end

  # --- Select operators ---

  def self.select_AND(inj, _val, _ref, store)
    if inj.mode == S_MKEYPRE
      terms = getprop(inj.parent, inj.key)
      ppath = slice(inj.path, -1)
      point = getpath(store, ppath)

      vstore = merge([{}, store], 1)
      vstore[S_DTOP] = point

      terms.each do |term|
        terrs = []
        validate(point, term, {
                   'extra' => vstore,
                   'errs' => terrs,
                   'meta' => inj.meta
                 })
        inj.errs << "AND:#{pathify(ppath)}\u2A2F#{stringify(point)} fail:#{stringify(terms)}" unless terrs.empty?
      end

      gkey = getelem(inj.path, -2)
      gp = getelem(inj.nodes, -2)
      setprop(gp, gkey, point)
    end
    nil
  end

  def self.select_OR(inj, _val, _ref, store)
    if inj.mode == S_MKEYPRE
      terms = getprop(inj.parent, inj.key)
      ppath = slice(inj.path, -1)
      point = getpath(store, ppath)

      vstore = merge([{}, store], 1)
      vstore[S_DTOP] = point

      terms.each do |term|
        terrs = []
        validate(point, term, {
                   'extra' => vstore,
                   'errs' => terrs,
                   'meta' => inj.meta
                 })
        next unless terrs.empty?

        gkey = getelem(inj.path, -2)
        gp = getelem(inj.nodes, -2)
        setprop(gp, gkey, point)
        return nil
      end

      inj.errs << "OR:#{pathify(ppath)}\u2A2F#{stringify(point)} fail:#{stringify(terms)}"
    end
    nil
  end

  def self.select_NOT(inj, _val, _ref, store)
    if inj.mode == S_MKEYPRE
      term = getprop(inj.parent, inj.key)
      ppath = slice(inj.path, -1)
      point = getpath(store, ppath)

      vstore = merge([{}, store], 1)
      vstore[S_DTOP] = point

      terrs = []
      validate(point, term, {
                 'extra' => vstore,
                 'errs' => terrs,
                 'meta' => inj.meta
               })

      inj.errs << "NOT:#{pathify(ppath)}\u2A2F#{stringify(point)} fail:#{stringify(term)}" if terrs.empty?

      gkey = getelem(inj.path, -2)
      gp = getelem(inj.nodes, -2)
      setprop(gp, gkey, point)
    end
    nil
  end

  def self.select_CMP(inj, _val, ref, store)
    # The list form of $LIKE is validate's checker; the key form is this operator.
    return validate_LIKE(inj, _val, ref, store) if inj.mode == S_MVAL && ref == '$LIKE'

    if inj.mode == S_MKEYPRE
      term = getprop(inj.parent, inj.key)
      gkey = getelem(inj.path, -2)
      ppath = slice(inj.path, -1)
      point = getpath(store, ppath)

      pass_test = false

      begin
        if ref == '$GT' && point > term
          pass_test = true
        elsif ref == '$LT' && point < term
          pass_test = true
        elsif ref == '$GTE' && point >= term
          pass_test = true
        elsif ref == '$LTE' && point <= term
          pass_test = true
        elsif ref == '$LIKE'
          pass_test = true if stringify(point).match?(Regexp.new(term.to_s))
        end
      rescue StandardError
      end

      if pass_test
        gp = getelem(inj.nodes, -2)
        setprop(gp, gkey, point)
      else
        inj.errs << "CMP: #{pathify(ppath)}\u2A2F#{stringify(point)} fail:#{ref} #{stringify(term)}"
      end
    end
    nil
  end

  # --- select: Select children matching query ---
  def self.select(children, query)
    return [] unless isnode(children)

    children = if ismap(children)
                 items(children).map do |item|
                   v = item[1]
                   setprop(v, '$KEY', item[0]) if ismap(v)
                   v
                 end
               else
                 children.each_with_index.map do |n, i|
                   setprop(n, '$KEY', i) if ismap(n)
                   n
                 end
               end

    results = []
    q = clone(query)

    _openquery(q)

    select_extra = {
      '$AND' => method(:select_AND),
      '$OR' => method(:select_OR),
      '$NOT' => method(:select_NOT),
      '$GT' => method(:select_CMP),
      '$LT' => method(:select_CMP),
      '$GTE' => method(:select_CMP),
      '$LTE' => method(:select_CMP),
      '$LIKE' => method(:select_CMP)
    }

    children.each do |child|
      terrs = []
      validate(child, clone(q), {
                 'errs' => terrs,
                 'meta' => { S_BEXACT => true },
                 'extra' => select_extra
               })
      results << child if terrs.empty?
    end

    results
  end

  # Open every map in a select query, so a child may hold keys the query does
  # not name, but leave a directive's literals as written: what $EXACT
  # compares, and the count or bound of $NOF, $LEN and $RANGE.
  def self._openquery(q)
    if ismap(q)
      setprop(q, '`$OPEN`', getprop(q, '`$OPEN`', true))
      keysof(q).each { |key| _openquery(q[key]) }
    elsif islist(q)
      head = q[0]
      exact = head == '`$EXACT`'
      bounded = ['`$NOF`', '`$LEN`', '`$RANGE`'].include?(head)
      q.each_with_index do |item, i|
        _openquery(item) if i.zero? || !(exact || (bounded && i == 1))
      end
    end
  end

  # --- setpath ---
  def self.setpath(store, path, val, injdef = nil)
    # Same contract as setprop/delprop: a condensed store is immutable.
    raise S_CONDENSED_IMMUTABLE if iscondensed(store)

    pt = typify(path)
    if T_list.anybits?(pt)
      parts = path
    elsif T_string.anybits?(pt)
      parts = path.split(S_DT)
    elsif T_number.anybits?(pt)
      parts = [path]
    else
      return nil
    end

    base = _injdef_prop(injdef, 'base')
    numparts = size(parts)
    parent = base ? getprop(store, base, store) : store

    (0...(numparts - 1)).each do |pI|
      part_key = getelem(parts, pI)
      next_parent = getprop(parent, part_key)
      unless isnode(next_parent)
        next_part = getelem(parts, pI + 1)
        next_parent = T_number.anybits?(typify(next_part)) ? [] : {}
        setprop(parent, part_key, next_parent)
      end
      parent = next_parent
    end

    if val == DELETE
      delprop(parent, getelem(parts, -1))
    else
      setprop(parent, getelem(parts, -1), val)
    end

    parent
  end

  # --- Condensed structures ---

  CONDENSE_VERSION = 1

  CONDENSE_MAP = 0
  CONDENSE_LIST = 1
  CONDENSE_STR = 2
  CONDENSE_NUM = 3
  CONDENSE_TRUE = 4
  CONDENSE_FALSE = 5
  CONDENSE_NULL = 6

  S_condense = '$condense'.freeze
  S_condsym = 'sym'.freeze
  S_condnode = 'node'.freeze
  S_condroot = 'root'.freeze

  S_CONDENSED_IMMUTABLE =
    'struct: condensed structures are immutable - expand() first, then modify the copy'.freeze

  # The item at index i, or nil. A negative or fractional i is no item, as in JavaScript.
  def self._condenseat(list, i)
    i = i.to_i if i.is_a?(Float) && i.finite? && i == i.to_i
    return nil unless islist(list) && i.is_a?(Integer) && i >= 0 && i < list.length

    list[i]
  end

  # A path part's string form, as JavaScript writes it: nil is 'null', 1.0 is '1'.
  def self._condensestr(key)
    return key if key.is_a?(String)
    return 'null' if key.nil?
    return key.to_i.to_s if key.is_a?(Float) && key.finite? && key == key.to_i

    key.to_s
  end

  # Reads with fetch, which never runs a Hash default proc.
  def self.iscondensed(val = UNDEF)
    return false unless ismap(val)

    # The version must MATCH, not merely be numeric: a future profile would
    # otherwise be decoded under this one's schema.
    version = val.fetch(S_condense, nil)
    version.is_a?(Numeric) && version == CONDENSE_VERSION &&
      islist(val.fetch(S_condsym, nil)) &&
      islist(val.fetch(S_condnode, nil)) &&
      val.fetch(S_condroot, nil).is_a?(Numeric)
  end

  # Condense any JSON-shaped node. Pure: the same input always produces a
  # byte-identical result, on every port.
  def self.condense(val = UNDEF)
    # Pass one: every distinct map key and string value, once, sorted.
    symset = {}
    collect = lambda do |n|
      if ismap(n)
        keysof(n).each do |k|
          symset[k] = true
          collect.call(n[k])
        end
      elsif islist(n)
        n.each { |item| collect.call(item) }
      elsif n.is_a?(String)
        symset[n] = true
      end
    end
    collect.call(val)

    # Ruby sorts strings by byte, which for UTF-8 is code point order.
    sym = symset.keys.sort
    symid = {}
    sym.each_with_index { |s, i| symid[s] = i }

    # Pass two: build post-order, interning on the encoding. Because children
    # are built first, identical subtrees have already been interned by the
    # time a parent references them, so sharing costs nothing extra.
    node = []
    seen = {}
    intern = lambda do |enc, enckey = enc|
      hit = seen[enckey]
      return hit unless hit.nil?

      idx = node.length
      node << enc
      seen[enckey] = idx
      idx
    end

    build = lambda do |n|
      if ismap(n)
        enc = [CONDENSE_MAP]
        # keysof sorts, so the key ids ascend and lookup can bisect.
        keysof(n).each do |k|
          enc << symid[k]
          enc << build.call(n[k])
        end
        intern.call(enc)
      elsif islist(n)
        intern.call([CONDENSE_LIST] + n.map { |item| build.call(item) })
      elsif n.is_a?(String)
        intern.call([CONDENSE_STR, symid[n]])
      elsif n.is_a?(Numeric)
        # Keyed by value, so 1 and 1.0 are one number.
        numkey = n.is_a?(Float) && n.finite? && n == n.to_i ? n.to_i : n
        intern.call([CONDENSE_NUM, n], [CONDENSE_NUM, numkey])
      elsif n == true
        intern.call([CONDENSE_TRUE])
      elsif n == false
        intern.call([CONDENSE_FALSE])
      else
        intern.call([CONDENSE_NULL])
      end
    end

    root = build.call(val)

    out = {}
    out[S_condense] = CONDENSE_VERSION
    out[S_condsym] = sym
    out[S_condnode] = node
    out[S_condroot] = root
    out
  end

  # Resolve a symbol to its id by bisecting the sorted symbol table. -1 when
  # the string does not occur anywhere in the structure, which is itself a fast
  # negative answer for a key lookup.
  def self.condenseSymId(cond, key)
    sym = _getprop(cond, S_condsym, nil)
    lo = 0
    hi = islist(sym) ? sym.length - 1 : -1
    while lo <= hi
      mid = (lo + hi) >> 1
      s = sym[mid]
      return mid if s == key

      if s.is_a?(String) && s < key
        lo = mid + 1
      else
        hi = mid - 1
      end
    end
    -1
  end

  # The node index of `key` inside node `idx`, or -1. Touches only this node.
  def self.condenseChild(cond, idx, key)
    enc = _condenseat(_getprop(cond, S_condnode, nil), idx)
    kind = _condenseat(enc, 0)

    if kind == CONDENSE_MAP
      return -1 unless key.is_a?(String) || key.is_a?(Numeric)

      symid = condenseSymId(cond, _condensestr(key))
      return -1 if symid.negative?

      # Pairs live at [1,2], [3,4], ... with keys ascending: bisect the pairs.
      lo = 0
      hi = ((enc.length - 1) / 2) - 1
      while lo <= hi
        mid = (lo + hi) >> 1
        k = enc[1 + (mid * 2)]
        return enc[2 + (mid * 2)] if k == symid

        if k.is_a?(Numeric) && k < symid
          lo = mid + 1
        else
          hi = mid - 1
        end
      end
      return -1
    end

    if kind == CONDENSE_LIST
      # Read as an ordinary list is, so condensing never changes which value a path selects.
      i = _listindex(key, enc.length - 1)
      return i.negative? ? -1 : enc[1 + i]
    end

    -1
  end

  # Walk a path from a starting node, returning the node index or -1.
  def self.condenseResolve(cond, idx, path)
    parts =
      if islist(path)
        path
      elsif path.is_a?(String)
        path == S_MT ? [] : path.split(S_DT, -1)
      elsif path.nil? || path.equal?(UNDEF)
        []
      else
        [_condensestr(path)]
      end

    at = idx
    parts.each do |part|
      return -1 unless at.is_a?(Numeric) && !at.negative?
      next if part == S_MT

      at = condenseChild(cond, at, part)
    end
    # A child index that is not a number names no node.
    at.is_a?(Numeric) ? at : -1
  end

  # A missing node materialises as nil, so no UNDEF reaches a container.
  def self.condenseMaterialise(cond, idx)
    sym = _getprop(cond, S_condsym, nil)
    node = _getprop(cond, S_condnode, nil)

    rebuild = lambda do |i|
      enc = _condenseat(node, i)
      return nil if enc.nil?

      case _condenseat(enc, 0)
      when CONDENSE_MAP
        out = {}
        (1...enc.length).step(2) { |j| out[_condenseat(sym, enc[j])] = rebuild.call(_condenseat(enc, j + 1)) }
        out
      when CONDENSE_LIST
        (1...enc.length).map { |j| rebuild.call(enc[j]) }
      when CONDENSE_STR
        _condenseat(sym, _condenseat(enc, 1))
      when CONDENSE_NUM
        _condenseat(enc, 1)
      when CONDENSE_TRUE
        true
      when CONDENSE_FALSE
        false
      end
    end

    rebuild.call(idx)
  end

  # Fully materialise a condensed structure. The escape hatch: correct for any
  # caller, but it gives up every benefit of condensing, so prefer a view or a
  # path read.
  def self.expand(cond = UNDEF)
    return cond unless iscondensed(cond)

    condenseMaterialise(cond, cond[S_condroot])
  end

  # The keys of node `idx`, WITHOUT materialising any of its values. This is
  # the point of the whole exercise for enumeration: listing the names in a
  # large collection should cost a symbol-table read, not a full decode.
  def self.condenseKeys(cond, idx)
    enc = _condenseat(_getprop(cond, S_condnode, nil), idx)
    case _condenseat(enc, 0)
    when CONDENSE_MAP
      sym = _getprop(cond, S_condsym, nil)
      (1...enc.length).step(2).map { |j| _condenseat(sym, enc[j]) }
    when CONDENSE_LIST
      (1...enc.length).map { |j| (j - 1).to_s }
    else
      []
    end
  end

  # A cursor into a condensed structure. Reads resolve by integer index and
  # touch only the nodes on the path, so the cost of a lookup is proportional
  # to path depth and result size, never to total structure size.
  class CondenseView
    def initialize(cond, start, refmemo)
      @cond = cond
      @start = start
      # Shared materialisations, handed out ONLY by ref(). Threaded through
      # at() so every cursor into the same structure shares one memo.
      @refmemo = refmemo
    end

    # The value at path, materialised. Scalars come back directly; a
    # container comes back as an independent copy.
    def get(path = nil)
      VoxgigStruct.condenseMaterialise(@cond, VoxgigStruct.condenseResolve(@cond, @start, path))
    end

    # Key names at path, with no value decoding at all.
    def keys(path = nil)
      at = VoxgigStruct.condenseResolve(@cond, @start, path)
      at.negative? ? [] : VoxgigStruct.condenseKeys(@cond, at)
    end

    def has(path = nil)
      !VoxgigStruct.condenseResolve(@cond, @start, path).negative?
    end

    # Chainable cursor. Cheap: no decoding happens here.
    def at(path = nil)
      VoxgigStruct.condenseview(@cond, VoxgigStruct.condenseResolve(@cond, @start, path), @refmemo)
    end

    def value
      VoxgigStruct.condenseMaterialise(@cond, @start)
    end

    def size
      enc = VoxgigStruct._condenseat(VoxgigStruct._getprop(@cond, S_condnode, nil), @start)
      case VoxgigStruct._condenseat(enc, 0)
      when CONDENSE_MAP then (enc.length - 1) / 2
      when CONDENSE_LIST then enc.length - 1
      else 0
      end
    end

    def exists
      !@start.negative?
    end

    # DANGER, and named to say so. Returns a SHARED materialisation: the same
    # object for the same node, every time. Mutating it corrupts every other
    # reader of that node, including ones reached by a different path,
    # because the structure is a DAG. Use value() unless a profile says this
    # matters.
    def ref
      @refmemo[@start] = VoxgigStruct.condenseMaterialise(@cond, @start) unless @refmemo.key?(@start)
      @refmemo[@start]
    end
  end

  private_constant :CondenseView

  def self.condenseview(cond = UNDEF, idx = nil, memo = nil)
    start = idx.nil? || idx.equal?(UNDEF) ? (iscondensed(cond) ? cond[S_condroot] : -1) : idx
    # A start that is not a number reads as no node, as it does in JavaScript.
    CondenseView.new(cond, start.is_a?(Numeric) ? start : -1, memo.nil? ? {} : memo)
  end

  # --- Injection class ---
  class Injection
    attr_accessor :mode, :full, :keyI, :keys, :key, :val, :parent,
                  :path, :nodes, :handler, :errs, :meta, :base,
                  :modify, :extra, :prior, :dparent, :dpath, :root

    def initialize(val, parent)
      @mode = VoxgigStruct::S_MVAL
      @full = false
      @keyI = 0
      @keys = [VoxgigStruct::S_DTOP]
      @key = VoxgigStruct::S_DTOP
      @val = val
      @parent = parent
      @path = [VoxgigStruct::S_DTOP]
      @nodes = [parent]
      @handler = nil
      @errs = []
      @meta = {}
      @base = nil
      @modify = nil
      @extra = nil
      @prior = nil
      @dparent = nil
      @dpath = [VoxgigStruct::S_DTOP]
      @root = nil
    end

    def descend
      @meta['__d'] = (@meta['__d'] || 0) + 1

      parentkey = VoxgigStruct.getelem(@path, -2)

      if @dparent.nil?
        @dpath += [parentkey] if VoxgigStruct.size(@dpath) > 1
      elsif parentkey
        @dparent = VoxgigStruct.getprop(@dparent, parentkey)
        lastpart = VoxgigStruct.getelem(@dpath, -1)
        @dpath = if lastpart == "$:#{parentkey}"
                   VoxgigStruct.slice(@dpath, -1)
                 else
                   @dpath + [parentkey]
                 end
      end

      @dparent
    end

    def child(keyI, keys)
      key = VoxgigStruct.strkey(keys[keyI])
      val = @val

      cinj = Injection.new(VoxgigStruct.getprop(val, key), val)
      cinj.mode = @mode
      cinj.full = @full
      cinj.keyI = keyI
      cinj.keys = keys
      cinj.key = key
      cinj.path = @path + [key]
      cinj.nodes = @nodes + [val]
      cinj.handler = @handler
      cinj.errs = @errs
      cinj.meta = @meta
      cinj.base = @base
      cinj.modify = @modify
      cinj.prior = self
      cinj.dpath = @dpath.dup
      cinj.dparent = @dparent
      cinj.extra = @extra
      cinj.root = @root

      cinj
    end

    def setval(val, ancestor = nil)
      # Mirrors the canonical TS Injection.setval: UNDEF (sentinel) and
      # nil (Ruby collapses both onto the same "no value" slot) delete
      # the slot at every ancestor level; any other value sets it. The
      # delete-on-undef shortcut is used by injectors (transform_DELETE,
      # transform_MERGE, validate_CHILD) to signal "drop this slot" via
      # their return value rather than calling delprop explicitly.
      if ancestor.nil? || (ancestor.is_a?(Numeric) && ancestor < 2)
        target = @parent
        key = @key
      else
        target = VoxgigStruct.getelem(@nodes, 0 - ancestor)
        key = VoxgigStruct.getelem(@path, 0 - ancestor)
      end

      if val.nil? || val.equal?(VoxgigStruct::UNDEF)
        VoxgigStruct.delprop(target, key)
      else
        VoxgigStruct.setprop(target, key, val)
      end
    end

    def to_s(prefix = nil)
      "INJ#{"/#{prefix}" if prefix}:#{VoxgigStruct.pad(VoxgigStruct.pathify(@path, 1))}" \
        "#{VoxgigStruct::MODENAME[VoxgigStruct::M_VAL] || ''}#{'/full' if @full}:key=#{@keyI}/#{@key}"
    end
  end
end
