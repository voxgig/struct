require 'json'
require 'uri'

module VoxgigStruct
  # --- Debug Logging Configuration ---
  DEBUG = false
  
  def self.log(msg)
    puts "[DEBUG] #{msg}" if DEBUG
  end

  # --- Helper to convert internal undefined marker to Ruby nil ---
  def self.conv(val)
    val.equal?(UNDEF) ? nil : val
  end

  # --- Constants ---
  S_MKEYPRE  = 'key:pre'
  S_MKEYPOST = 'key:post'
  S_MVAL     = 'val'
  S_MKEY     = 'key'

  S_DKEY   = '`$KEY`'
  S_DMETA  = '`$META`'
  S_DTOP   = '$TOP'
  S_DERRS  = '$ERRS'

  S_any      = 'any'
  S_array    = 'array'
  S_boolean  = 'boolean'
  S_decimal  = 'decimal'
  S_function = 'function'
  S_instance = 'instance'
  S_integer  = 'integer'
  S_list     = 'list'
  S_map      = 'map'
  S_nil      = 'nil'
  S_node     = 'node'
  S_number   = 'number'
  S_null     = 'null'
  S_object   = 'object'
  S_scalar   = 'scalar'
  S_string   = 'string'
  S_symbol   = 'symbol'
  S_MT       = ''       # empty string constant (used as a prefix)
  S_BT       = '`'
  S_DS       = '$'
  S_DT       = '.'      # delimiter for key paths
  S_CN       = ':'      # colon for unknown paths
  S_SP       = ' '
  S_VIZ      = ': '
  S_KEY      = 'KEY'

  # Types - bitfield integers matching TypeScript canonical
  _t = 31
  T_any      = (1 << _t) - 1;     _t -= 1
  T_noval    = 1 << _t;           _t -= 1
  T_boolean  = 1 << _t;           _t -= 1
  T_decimal  = 1 << _t;           _t -= 1
  T_integer  = 1 << _t;           _t -= 1
  T_number   = 1 << _t;           _t -= 1
  T_string   = 1 << _t;           _t -= 1
  T_function = 1 << _t;           _t -= 1
  T_symbol   = 1 << _t;           _t -= 1
  T_null     = 1 << _t;           _t -= 8
  T_list     = 1 << _t;           _t -= 1
  T_map      = 1 << _t;           _t -= 1
  T_instance = 1 << _t;           _t -= 5
  T_scalar   = 1 << _t;           _t -= 1
  T_node     = 1 << _t

  TYPENAME = [
    S_any, S_nil, S_boolean, S_decimal, S_integer, S_number, S_string,
    S_function, S_symbol, S_null,
    '', '', '', '', '', '', '',
    S_list, S_map, S_instance,
    '', '', '', '',
    S_scalar, S_node,
  ]

  SKIP = { '`$SKIP`' => true }
  DELETE = { '`$DELETE`' => true }

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
    s = s.nil? ? "" : s
    Regexp.escape(s)
  end

  def self.escurl(s)
    s = s.nil? ? "" : s
    URI::DEFAULT_PARSER.escape(s, /[^A-Za-z0-9\-\.\_\~]/)
  end

  # --- Internal getprop ---
  # Returns the value if found; otherwise returns alt (default is UNDEF)
  def self._getprop(val, key, alt = UNDEF)
    log("(_getprop) called with val=#{val.inspect} and key=#{key.inspect}")
    return alt if val.nil? || key.nil?
    if islist(val)
      key = (key.to_s =~ /\A\d+\z/) ? key.to_i : key
      unless key.is_a?(Numeric) && key >= 0 && key < val.size
        log("(_getprop) index #{key.inspect} out of bounds; returning alt")
        return alt
      end
      result = val[key]
      log("(_getprop) returning #{result.inspect} from array for key #{key}")
      return result
    elsif ismap(val)
      key_str = key.to_s
      if val.key?(key_str)
        result = val[key_str]
        log("(_getprop) found key #{key_str.inspect} in hash, returning #{result.inspect}")
        return result
      elsif key.is_a?(String) && val.key?(key.to_sym)
        result = val[key.to_sym]
        log("(_getprop) found symbol key #{key.to_sym.inspect} in hash, returning #{result.inspect}")
        return result
      else
        log("(_getprop) key #{key.inspect} not found; returning alt")
        return alt
      end
    else
      log("(_getprop) value is not a node; returning alt")
      alt
    end
  end

  # --- Public getprop ---
  # Wraps _getprop. If the result equals UNDEF, returns the provided alt.
  def self.getprop(val, key, alt = nil)
    result = _getprop(val, key, alt.nil? ? UNDEF : alt)
    result.equal?(UNDEF) ? alt : result
  end

  def self.isempty(val)
    return true if val.nil? || val.equal?(UNDEF) || val == ""
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
    log(">>> setprop called with parent=#{parent.inspect}, key=#{key.inspect}, val=#{val.inspect}")
    return parent unless iskey(key)
    if ismap(parent)
      key_str = key.to_s
      if val == :no_val_provided
        parent.delete(key_str)
      else
        parent[key_str] = val
      end
    elsif islist(parent)
      begin
        key_i = Integer(key)
      rescue ArgumentError
        return parent
      end
      if val == :no_val_provided
        parent.delete_at(key_i) if key_i >= 0 && key_i < parent.length
      else
        if key_i >= 0
          index = key_i >= parent.length ? parent.length : key_i
          parent[index] = val
        else
          parent.unshift(val)
        end
      end
    end
    log("<<< setprop result: #{parent.inspect}")
    parent
  end

  def self.stringify(val, maxlen = nil, pretty = nil)
    return '' if val.equal?(UNDEF)
    return 'null' if val.nil?

    if val.is_a?(String)
      valstr = val
    else
      begin
        v = val.is_a?(Hash) ? sorted(val) : val
        valstr = JSON.generate(v)
        valstr = valstr.gsub('"', '')
      rescue StandardError
        valstr = val.to_s
      end
    end

    if !maxlen.nil? && maxlen >= 0
      if valstr.length > maxlen
        valstr = valstr[0, maxlen - 3] + '...'
      end
    end

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
    else
      nil
    end

    start = startin.nil? ? 0 : startin < 0 ? 0 : startin
    end_idx = endin.nil? ? 0 : endin < 0 ? 0 : endin

    if path && start >= 0
      path = path[start..-end_idx-1] || []
      if path.empty?
        pathstr = '<root>'
      else
        pathstr = path
          .select { |p| iskey(p) }
          .map { |p|
            if p.is_a?(Numeric)
              S_MT + p.floor.to_s
            else
              p.gsub('.', S_MT)
            end
          }
          .join(S_DT)
      end
    end

    if pathstr.nil?
      pathstr = '<unknown-path' + (val.equal?(UNDEF) ? '' : S_CN + stringify(val, 47)) + '>'
    end

    pathstr
  end

  def self.strkey(key = nil)
    return "" if key.nil?
    return key if key.is_a?(String)
    return key.floor.to_s if key.is_a?(Numeric)
    ""
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
    return (val == true ? 1 : 0) if val == true || val == false
    return val.to_i if val.is_a?(Numeric)
    0
  end

  def self.slice(val, start_idx = nil, end_idx = nil, mutate = false)
    return val if val.nil? || val.equal?(UNDEF)

    if val.is_a?(Numeric) && !val.is_a?(TrueClass) && !val.is_a?(FalseClass)
      s = start_idx.nil? ? (-Float::INFINITY) : start_idx
      e = end_idx.nil? ? Float::INFINITY : (end_idx - 1)
      return [[val, s].max, e].min
    end

    vlen = size(val)

    start_idx = 0 if !end_idx.nil? && start_idx.nil?

    if !start_idx.nil?
      s = start_idx
      e = end_idx

      if s < 0
        e = vlen + s
        e = 0 if e < 0
        s = 0
      elsif !e.nil?
        if e < 0
          e = vlen + e
          e = 0 if e < 0
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
    str = str.is_a?(String) ? str : stringify(str)
    padding = padding.nil? ? 44 : padding
    padchar = padchar.nil? ? ' ' : (padchar.to_s + ' ')[0]
    if padding >= 0
      str.ljust(padding, padchar)
    else
      str.rjust(-padding, padchar)
    end
  end

  def self.getelem(val, key, alt = UNDEF)
    out = UNDEF
    if islist(val) && !key.nil? && !key.equal?(UNDEF)
      begin
        nkey = key.to_i
        if key.to_s.strip.match?(/\A-?\d+\z/)
          nkey = val.length + nkey if nkey < 0
          out = (0 <= nkey && nkey < val.length) ? val[nkey] : UNDEF
        end
      rescue
      end
    end
    if out.equal?(UNDEF)
      return isfunc(alt) ? alt.call : (alt.equal?(UNDEF) ? nil : alt)
    end
    out
  end

  def self.flatten(lst, depth = nil)
    depth = 1 if depth.nil?
    return lst unless islist(lst)
    out = []
    lst.each do |item|
      if islist(item) && depth > 0
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
    if ismap(parent)
      ks = strkey(key)
      parent.delete(ks)
    elsif islist(parent)
      return parent unless key.to_s.match?(/\A-?\d+\z/)
      begin
        ki = key.to_i
        if 0 <= ki && ki < parent.length
          parent.delete_at(ki)
        end
      rescue
      end
    end
    parent
  end

  def self.join(arr, sep = nil, url = nil)
    return '' unless islist(arr)
    sepdef = sep.nil? ? ',' : sep.to_s
    sepre = (sepdef.length == 1) ? Regexp.escape(sepdef) : nil

    # Filter to non-empty strings only
    parts = arr.select { |n| n.is_a?(String) && n != '' }

    parts = parts.map.with_index { |s, i|
      if sepre
        if url && i == 0
          s = s.sub(/#{sepre}+$/, '')
          next s
        end
        s = s.sub(/^#{sepre}+/, '') if i > 0
        s = s.sub(/#{sepre}+$/, '') if i < parts.length - 1 || !url
        # Collapse internal duplicate separators
        s = s.gsub(/([^#{sepre}])#{sepre}+([^#{sepre}])/, "\\1#{sepdef}\\2")
      end
      s
    }.reject(&:empty?)

    parts.join(sepdef)
  end

  def self.joinurl(sarr)
    join(sarr, '/', true)
  end

  def self.jsonify(val, flags = nil)
    str = 'null'
    if !val.nil?
      begin
        indent = (flags.is_a?(Hash) ? (flags['indent'] || flags[:indent]) : nil) || 2
        str = _json_stringify(val, indent, 0)
        if str.nil?
          str = 'null'
        end
        offset = (flags.is_a?(Hash) ? (flags['offset'] || flags[:offset]) : nil) || 0
        if offset > 0
          lines = str.split("\n")
          first = lines[0] || ''
          rest = lines[1..-1] || []
          rest_indented = rest.map { |l| (' ' * offset) + l }
          str = "{\n" + rest_indented.join("\n")
        end
      rescue => e
        str = '__JSONIFY_FAILED__'
      end
    end
    str
  end

  # Mimic JSON.stringify(val, null, indent) from JavaScript
  def self._json_stringify(val, indent, depth)
    return 'null' if val.nil?
    return val.to_s if val == true || val == false
    return val.is_a?(Float) ? val.to_s : val.to_s if val.is_a?(Numeric)
    return JSON.generate(val) if val.is_a?(String)

    ind = ' ' * indent
    current_indent = ind * (depth + 1)
    closing_indent = ind * depth

    if islist(val)
      return '[]' if val.empty?
      items_str = val.map { |v| current_indent + _json_stringify(v, indent, depth + 1) }
      "[\n" + items_str.join(",\n") + "\n" + closing_indent + "]"
    elsif ismap(val)
      return '{}' if val.empty?
      pairs = val.keys.sort.map { |k|
        current_indent + JSON.generate(k) + ': ' + _json_stringify(val[k], indent, depth + 1)
      }
      "{\n" + pairs.join(",\n") + "\n" + closing_indent + "}"
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

  # Public haskey uses getprop (so that missing keys yield nil)
  def self.haskey(val = UNDEF, key = UNDEF)
    _getprop(val, key, UNDEF) != UNDEF
  end

  def self.joinurl(parts)
    parts.compact.map.with_index do |s, i|
      s = s.to_s
      if i.zero?
        s.sub(/\/+$/, '')
      else
        s.sub(/([^\/])\/+/, '\1/').sub(/^\/+/, '').sub(/\/+$/, '')
      end
    end.reject { |s| s.empty? }.join('/')
  end

  # Get type name string from type bitfield value.
  def self._clz32(n)
    return 32 if n <= 0
    31 - (n.bit_length - 1)
  end

  def self.typename(t)
    t = t.to_i
    idx = _clz32(t)
    return TYPENAME[0] if idx < 0 || idx >= TYPENAME.length
    r = TYPENAME[idx]
    (r.nil? || r == S_MT) ? TYPENAME[0] : r
  end

  # Determine the type of a value as a bitfield integer.
  def self.typify(value = UNDEF)
    return T_noval if value.equal?(UNDEF)
    return T_scalar | T_null if value.nil?

    if value == true || value == false
      return T_scalar | T_boolean
    end

    if isfunc(value)
      return T_scalar | T_function
    end

    if value.is_a?(Integer)
      return T_scalar | T_number | T_integer
    end

    if value.is_a?(Float)
      return value.nan? ? T_noval : (T_scalar | T_number | T_decimal)
    end

    if value.is_a?(String)
      return T_scalar | T_string
    end

    if value.is_a?(Symbol)
      return T_scalar | T_symbol
    end

    if islist(value)
      return T_node | T_list
    end

    if ismap(value)
      return T_node | T_map
    end

    T_any
  end

  # Walk a data structure depth first, applying a function to each value.
  # The `path` argument passed to the before/after callbacks is a single
  # mutable array per depth, shared across all callback invocations for the
  # lifetime of this top-level walk call. Callbacks that need to store the
  # path MUST clone it (e.g. `path.dup`); the contents will otherwise be
  # overwritten by subsequent visits.
  def self.walk(val, before = nil, after = nil, maxdepth = nil, key: nil, parent: nil, path: nil, pool: nil)
    if pool.nil?
      pool = [[]]
    end
    if path.nil?
      path = pool[0]
    end

    depth = path.length

    _before = before
    _after = after

    out = _before.nil? ? val : _before.call(key, val, parent, path)

    md = (maxdepth.is_a?(Numeric) && maxdepth >= 0) ? maxdepth : MAXDEPTH
    if md == 0 || (md > 0 && md <= depth)
      return out
    end

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
        if merged.key?(k)
          merged[k] = deep_merge(merged[k], v)
        else
          merged[k] = v
        end
      end
      merged
    elsif islist(a) && islist(b)
      max_len = [a.size, b.size].max
      merged = []
      (0...max_len).each do |i|
        if i < a.size && i < b.size
          merged[i] = deep_merge(a[i], b[i])
        elsif i < b.size
          merged[i] = b[i]
        else
          merged[i] = a[i]
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
    return nil if lenlist == 0
    return val[0] if lenlist == 1

    out = getprop(val, 0, {})

    (1...lenlist).each do |oI|
      obj = val[oI]

      if !isnode(obj)
        # Non-nodes (including nil) override directly
        out = obj
      else
        cur = [out]
        dst = [out]

        before_fn = lambda { |key, v, _parent, path|
          pI = path.length

          if md <= pI
            while cur.length <= pI; cur << nil; end
            cur[pI] = v
            setprop(cur[pI - 1], key, v) if pI > 0 && pI - 1 < cur.length
            next nil  # stop descending
          elsif !isnode(v)
            cur[pI] = v
          else
            # Extend arrays as needed
            while dst.length <= pI; dst << nil; end
            while cur.length <= pI; cur << nil; end

            dst[pI] = pI > 0 ? getprop(dst[pI - 1], key) : dst[pI]
            tval = dst[pI]

            if tval.nil?
              cur[pI] = islist(v) ? [] : {}
            elsif (islist(v) && islist(tval)) || (ismap(v) && ismap(tval))
              cur[pI] = tval
            else
              cur[pI] = v
              v = nil  # stop descending
            end
          end

          v
        }

        after_fn = lambda { |key, _v, _parent, path|
          cI = path.length
          if cI < 1
            next (cur.length > 0 ? cur[0] : _v)
          end

          target = (cI - 1 < cur.length) ? cur[cI - 1] : nil
          value = (cI < cur.length) ? cur[cI] : nil

          setprop(target, key, value) if target
          value
        }

        out = walk(obj, before_fn, after_fn)
      end
    end

    if md == 0
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
      parts = path.dup
    elsif path.is_a?(String)
      parts = path.split(S_DT, -1)
    elsif path.is_a?(Numeric)
      parts = [strkey(path)]
    else
      return nil
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
      base = nil; dparent = nil; inj_meta = nil; inj_key = nil; dpath = nil; handler = nil
    end

    src = base ? _getprop(store, base, store) : store
    numparts = parts.length

    # An empty path (incl empty string) just finds the src.
    if path.nil? || store.nil? || (numparts == 1 && parts[0] == S_MT) || numparts == 0
      val = src
    elsif numparts > 0
      # Check for $ACTIONs
      if numparts == 1
        val = _getprop(store, parts[0], UNDEF)
      end

      if !isfunc(val)
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

          # $$ escapes $
          part = part.gsub('$$', '$') if part.is_a?(String)

          if part == S_MT
            ascends = 0
            while pI + 1 < parts.length && parts[pI + 1] == S_MT
              ascends += 1
              pI += 1
            end

            if injdef && ascends > 0
              ascends -= 1 if pI == parts.length - 1
              if ascends == 0
                val = dparent
              else
                fullpath = flatten([slice(dpath, 0 - ascends), parts[(pI + 1)..-1]])
                if dpath.is_a?(Array) && ascends <= dpath.length
                  val = getpath(store, fullpath)
                else
                  val = UNDEF
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


  S_BKEY = '`$KEY`'
  S_BANNO = '`$ANNO`'
  S_BEXACT = '`$EXACT`'
  S_BVAL = '`$VAL`'
  S_DSPEC = '$SPEC'

  R_FULL_INJECT = /\A`(\$[A-Z]+|[^`]*)[0-9]*`\z/
  R_PART_INJECT = /`([^`]*)`/
  R_META_PATH = /\A([^$]+)\$([=~])(.+)\z/
  R_DOUBLE_DOLLAR = /\$\$/

  # --- _injectstr: Resolve backtick expressions in strings ---
  def self._injectstr(val, store, inj = nil)
    return S_MT unless val.is_a?(String) && val != S_MT

    out = val
    m = R_FULL_INJECT.match(val)

    # Full string injection: "`path.ref`" or "`$CMD`"
    if m
      inj.full = true if inj

      pathref = m[1]
      if pathref.length > 3
        pathref = pathref.gsub('$BT', S_BT).gsub('$DS', S_DS)
      end

      out = getpath(store, pathref, inj)

    else
      # Partial string injection: "prefix`ref`suffix"
      out = val.gsub(R_PART_INJECT) do |_match|
        ref = $1
        if ref.length > 3
          ref = ref.gsub('$BT', S_BT).gsub('$DS', S_DS)
        end

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
          rescue
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
        normal = val.keys.select { |k| !k.include?(S_DS) }.sort
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

        if !prekey.nil?
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

    if inj.prior.nil? && inj.root && haskey(inj.root, S_DTOP)
      return getprop(inj.root, S_DTOP)
    end
    if inj.key == S_DTOP && inj.parent && haskey(inj.parent, S_DTOP)
      return getprop(inj.parent, S_DTOP)
    end
    val
  end

  # Helper to read a property from injdef (Hash or object)
  def self._injdef_prop(injdef, key)
    return nil if injdef.nil?
    if injdef.is_a?(Hash)
      injdef[key] || injdef[key.to_sym]
    elsif injdef.respond_to?(key.to_sym)
      injdef.send(key.to_sym)
    else
      nil
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
    inj.setval(nil)
    nil
  end

  def self.transform_COPY(inj, _val, _ref, _store)
    mode = inj.mode
    key = inj.key

    out = nil
    if mode.start_with?('key')
      out = key
    else
      if !isnode(inj.dparent)
        out = (inj.path.length != 2) ? inj.dparent : nil
      else
        out = getprop(inj.dparent, key)
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

    if ismap(inj.dparent) && inj.key && haskey(inj.dparent, inj.key)
      return getprop(inj.dparent, inj.key)
    end

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
      args = islist(args) ? args : [args]
      inj.setval(nil)
      mergelist = [parent] + args + [clone(parent)]
      merge(mergelist)
      return key
    elsif mode == S_MVAL && islist(parent)
      if strkey(inj.key) == '0' && size(parent) > 0
        parent.delete_at(0)
        return getprop(parent, 0)
      else
        return getprop(parent, inj.key)
      end
    end
    nil
  end

  def self.transform_EACH(inj, _val, _ref, store)
    mode = inj.mode
    keys_ = inj.keys
    path = inj.path
    parent = inj.parent
    nodes_ = inj.nodes

    keys_.replace(keys_[0, 1]) if keys_

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
        src.each do |k, v|
          cc = clone(child_template)
          setprop(cc, S_BANNO, { S_KEY => k }) if ismap(cc)
          tval << cc
        end
      end
      tcurrent = ismap(src) ? src.values : src

      if size(tval) > 0
        ckey = getelem(path, -2)
        tpath = path[0...-1]

        dpath = [S_DTOP]
        if srcpath.is_a?(String) && !srcpath.empty?
          srcpath.split(S_DT).each { |p| dpath << p if p != S_MT }
        end
        dpath << ('$:' + ckey.to_s) if ckey

        tcur = { ckey => tcurrent }

        if size(tpath) > 1
          pkey = getelem(path, -3, S_DTOP)
          tcur = { pkey => tcur }
          dpath << ('$:' + pkey.to_s)
        end

        tinj = inj.child(0, ckey ? [ckey] : [])
        tinj.path = tpath
        tinj.nodes = nodes_.length > 0 ? nodes_[0...-1] : []
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
    islist(rval) && size(rval) > 0 ? rval[0] : nil
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
    target = getelem(nodes_, pathsize - 2, lambda { getelem(nodes_, pathsize - 1) })

    srcstore = getprop(store, inj.base, store)
    src = getpath(srcstore, srcpath, inj)

    if !islist(src)
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
        if keypath.is_a?(String) && keypath.start_with?(S_BT)
          k = inject(keypath, merge([{}, store, { S_DTOP => srcnode }], 1))
        else
          k = getpath(srcnode, keypath, inj)
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

    if !isempty(tval)
      tsrc = {}
      src.each_with_index do |n, i|
        if keypath.nil?
          kn = i
        elsif keypath.is_a?(String) && keypath.start_with?(S_BT)
          kn = inject(keypath, merge([{}, store, { S_DTOP => n }], 1))
        else
          kn = getpath(n, keypath, inj)
        end
        setprop(tsrc, kn, n)
      end

      tpath = slice(inj.path, -1)
      ckey = getelem(inj.path, -2)
      dpath = flatten([S_DTOP, srcpath.to_s.split(S_DT), '$:' + ckey.to_s])

      tcur = { ckey => tsrc }
      if size(tpath) > 1
        pkey = getelem(inj.path, -3, S_DTOP)
        tcur = { pkey => tcur }
        dpath << ('$:' + pkey.to_s)
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
    nodes_ = inj.nodes
    return nil if S_MVAL != inj.mode

    refpath = getprop(inj.parent, 1)
    inj.keyI = size(inj.keys)

    specFn = getprop(store, S_DSPEC)
    spec = isfunc(specFn) ? specFn.call : nil

    dpath = slice(inj.path, 1)
    ref = getpath(spec, refpath, {
      'dpath' => dpath,
      'dparent' => getpath(spec, dpath),
    })

    tref = clone(ref)

    cpath = slice(inj.path, -3)
    tpath = slice(inj.path, -1)
    tcur = getpath(store, cpath)
    tval = getpath(store, tpath)
    rval = nil

    if tval || !isnode(ref)
      tinj = inj.child(0, [getelem(tpath, -1)])
      tinj.path = tpath
      tinj.nodes = slice(inj.nodes, -1)
      tinj.parent = getelem(nodes_, -2)
      tinj.val = tref

      tinj.dpath = flatten([cpath])
      tinj.dparent = tcur

      inject(tref, store, tinj)
      rval = tinj.val
    end

    tkey = getelem(inj.path, -2)
    target = getelem(nodes_, -2, lambda { getelem(nodes_, -1) })
    if rval.nil?
      delprop(target, tkey)
    else
      setprop(target, tkey, rval)
    end

    if islist(target) && inj.prior
      inj.prior.keyI -= 1
    end

    _val
  end

  FORMATTER = {
    'identity' => lambda { |_k, v, *_a| v },
    'upper' => lambda { |_k, v, *_a| isnode(v) ? v : (v.nil? ? 'null' : '' + v.to_s).upcase },
    'lower' => lambda { |_k, v, *_a| isnode(v) ? v : (v.nil? ? 'null' : '' + v.to_s).downcase },
    'string' => lambda { |_k, v, *_a| isnode(v) ? v : (v.nil? ? 'null' : '' + v.to_s) },
    'number' => lambda { |_k, v, *_a|
      if isnode(v)
        v
      else
        n = Float(v) rescue 0
        n
      end
    },
    'integer' => lambda { |_k, v, *_a|
      if isnode(v)
        v
      else
        n = Integer(Float(v)) rescue 0
        n
      end
    },
    'concat' => lambda { |k, v, *_a|
      if k.nil? && islist(v)
        items(v, lambda { |n| isnode(n[1]) ? '' : (n[1].nil? ? 'null' : '' + n[1].to_s) }).join('')
      else
        v
      end
    },
  }

  def self.transform_FORMAT(inj, _val, _ref, store)
    slice(inj.keys, 0, 1, true)
    return nil if S_MVAL != inj.mode

    name = getprop(inj.parent, 1)
    child = getprop(inj.parent, 2)

    tkey = getelem(inj.path, -2)
    target = getelem(inj.nodes, -2, lambda { getelem(inj.nodes, -1) })

    cinj = injectChild(child, store, inj)
    resolved = cinj.val

    formatter = (0 < (T_function & typify(name))) ? name : FORMATTER[name]

    if formatter.nil?
      inj.errs << ('$FORMAT: unknown format: ' + name.to_s + '.')
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
      inj.errs << ('$' + ijname + ': ' + err)
      return nil
    end

    tkey = getelem(inj.path, -2)
    target = getelem(inj.nodes, -2, lambda { getelem(inj.nodes, -1) })

    cinj = injectChild(child, store, inj)
    resolved = cinj.val

    out = apply.call(resolved, store, cinj)
    setprop(target, tkey, out)
    out
  end

  def self.checkPlacement(modes, ijname, parentTypes, inj)
    mode_num = { S_MKEYPRE => M_KEYPRE, S_MKEYPOST => M_KEYPOST, S_MVAL => M_VAL }
    mode_int = mode_num[inj.mode] || 0
    if 0 == (modes & mode_int)
      inj.errs << '$' + ijname + ': invalid placement as ' + (PLACEMENT[mode_int] || '') +
        ', expected: ' + [M_KEYPRE, M_KEYPOST, M_VAL].select { |m| modes & m != 0 }.map { |m| PLACEMENT[m] }.join(',') + '.'
      return false
    end
    if !isempty(parentTypes)
      ptype = typify(inj.parent)
      if 0 == (parentTypes & ptype)
        inj.errs << '$' + ijname + ': invalid placement in parent ' + typename(ptype) +
          ', expected: ' + typename(parentTypes) + '.'
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
      if 0 == (argTypes[argI] & argType)
        found[0] = 'invalid argument: ' + stringify(arg, 22) +
          ' (' + typename(argType) + ' at position ' + (1 + argI).to_s +
          ') is not of type: ' + typename(argTypes[argI]) + '.'
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
      S_DSPEC => lambda { origspec },
      '$BT' => lambda { |*_a| S_BT },
      '$DS' => lambda { |*_a| S_DS },
      '$WHEN' => lambda { |*_a| Time.now.iso8601 },
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
      '$APPLY' => method(:transform_APPLY),
    }
    extraTransforms.each { |k, v| store[k] = v }
    store[S_DERRS] = errs

    injdef = {} if injdef.nil?
    injdef = {} unless injdef.is_a?(Hash)
    injdef = injdef.merge('errs' => errs)

    out = inject(spec, store, injdef)

    if !errs.empty? && !collect
      raise errs.join(' | ')
    end

    out
  end

  # --- Validators ---

  def self._invalidTypeMsg(path, needtype, vt, v, _whence = nil)
    vs = (v.nil? || v.equal?(UNDEF)) ? 'no value' : stringify(v)
    'Expected ' +
      (size(path) > 1 ? ('field ' + pathify(path, 1) + ' to be ') : '') +
      needtype.to_s + ', but found ' +
      ((v.nil? || v.equal?(UNDEF)) ? '' : typename(vt) + S_VIZ) + vs + '.'
  end

  def self.validate_STRING(inj, _val = nil, _ref = nil, _store = nil)
    out = getprop(inj.dparent, inj.key)
    t = typify(out)
    if 0 == (T_string & t)
      inj.errs << _invalidTypeMsg(inj.path, S_string, t, out, 'V1010')
      return nil
    end
    if out == S_MT
      inj.errs << ('Empty string at ' + pathify(inj.path, 1))
      return nil
    end
    out
  end

  TYPE_CHECKS = {
    S_number => lambda { |v| v.is_a?(Numeric) && !(v == true || v == false) },
    S_integer => lambda { |v| v.is_a?(Integer) && !(v == true || v == false) },
    S_decimal => lambda { |v| v.is_a?(Float) },
    S_boolean => lambda { |v| v == true || v == false },
    S_null => lambda { |v| v.nil? },
    S_nil => lambda { |v| v.equal?(UNDEF) },
    S_map => lambda { |v| v.is_a?(Hash) },
    S_list => lambda { |v| v.is_a?(Array) },
    S_function => lambda { |v| v.respond_to?(:call) },
    S_instance => lambda { |v|
      !v.is_a?(Hash) && !v.is_a?(Array) && !v.is_a?(String) &&
      !v.is_a?(Numeric) && !(v == true || v == false) && !v.nil? && !v.equal?(UNDEF)
    },
  }

  def self.validate_TYPE(inj, _val = nil, ref = nil, _store = nil)
    tname = (ref.is_a?(String) && ref.length > 1) ? ref[1..-1].downcase : S_any
    idx = TYPENAME.index(tname)
    typev = idx ? (1 << (31 - idx)) : 0
    typev = typev | T_null if tname == S_nil

    out = getprop(inj.dparent, inj.key)
    t = typify(out)

    if 0 == (t & typev)
      inj.errs << _invalidTypeMsg(inj.path, tname, t, out, 'V1001')
      return nil
    end
    out
  end

  def self.validate_ANY(inj, _val = nil, _ref = nil, _store = nil)
    getprop(inj.dparent, inj.key)
  end

  def self.validate_CHILD(inj, _val = nil, _ref = nil, _store = nil)
    mode = inj.mode
    key = inj.key
    parent = inj.parent
    path = inj.path
    keys = inj.keys

    if S_MKEYPRE == mode
      childtm = getprop(parent, key)
      pkey = getelem(path, -2)
      tval = getprop(inj.dparent, pkey)

      if tval.nil?
        tval = {}
      elsif !ismap(tval)
        inj.errs << _invalidTypeMsg(path[0...-1], S_object, typify(tval), tval, 'V0220')
        return nil
      end

      keysof(tval).each do |ckey|
        setprop(parent, ckey, clone(childtm))
        keys << ckey
      end

      inj.setval(nil)
      return nil
    end

    if S_MVAL == mode
      if !islist(parent)
        inj.errs << 'Invalid $CHILD as value'
        return nil
      end

      childtm = getprop(parent, 1)

      if inj.dparent.nil?
        parent.clear
        return nil
      end

      if !islist(inj.dparent)
        inj.errs << _invalidTypeMsg(path[0...-1], S_list, typify(inj.dparent), inj.dparent, 'V0230')
        inj.keyI = size(parent)
        return inj.dparent
      end

      items(inj.dparent).each do |n|
        setprop(parent, n[0], clone(childtm))
      end
      parent.slice!(inj.dparent.length..-1) if parent.length > inj.dparent.length
      inj.keyI = 0
      return getprop(inj.dparent, 0)
    end

    nil
  end

  def self.validate_ONE(inj, _val = nil, _ref = nil, store = nil)
    mode = inj.mode
    parent = inj.parent
    keyI = inj.keyI

    if S_MVAL == mode
      if !islist(parent) || 0 != keyI
        inj.errs << ('The $ONE validator at field ' + pathify(inj.path, 1, 1) +
          ' must be the first element of an array.')
        return nil
      end

      inj.keyI = size(inj.keys)
      inj.setval(inj.dparent, 2)
      inj.path = inj.path[0...-1]
      inj.key = getelem(inj.path, -1)

      tvals = parent[1..-1]
      if size(tvals) == 0
        inj.errs << ('The $ONE validator at field ' + pathify(inj.path, 1, 1) +
          ' must have at least one argument.')
        return nil
      end

      tvals.each do |tval|
        terrs = []
        vstore = merge([{}, store], 1)
        vstore[S_DTOP] = inj.dparent

        vcurrent = validate(inj.dparent, tval, {
          'extra' => vstore,
          'errs' => terrs,
          'meta' => inj.meta,
        })

        inj.setval(vcurrent, -2)
        return nil if size(terrs) == 0
      end

      valdesc = items(tvals).map { |n| stringify(n[1]) }.join(', ')
      valdesc = valdesc.gsub(/`\$([A-Z]+)`/) { $1.downcase }

      inj.errs << _invalidTypeMsg(
        inj.path,
        (size(tvals) > 1 ? 'one of ' : '') + valdesc,
        typify(inj.dparent), inj.dparent, 'V0210')
    end
  end

  def self.validate_EXACT(inj, _val = nil, _ref = nil, _store = nil)
    mode = inj.mode
    parent = inj.parent
    key = inj.key
    keyI = inj.keyI

    if S_MVAL == mode
      if !islist(parent) || 0 != keyI
        inj.errs << ('The $EXACT validator at field ' + pathify(inj.path, 1, 1) +
          ' must be the first element of an array.')
        return nil
      end

      inj.keyI = size(inj.keys)
      inj.setval(inj.dparent, 2)
      inj.path = inj.path[0...-1]
      inj.key = getelem(inj.path, -1)

      tvals = parent[1..-1]
      if size(tvals) == 0
        inj.errs << ('The $EXACT validator at field ' + pathify(inj.path, 1, 1) +
          ' must have at least one argument.')
        return nil
      end

      currentstr = nil
      tvals.each do |tval|
        exactmatch = (tval == inj.dparent)
        if !exactmatch && isnode(tval)
          currentstr ||= stringify(inj.dparent)
          exactmatch = stringify(tval) == currentstr
        end
        return nil if exactmatch
      end

      valdesc = items(tvals).map { |n| stringify(n[1]) }.join(', ')
      valdesc = valdesc.gsub(/`\$([A-Z]+)`/) { $1.downcase }

      inj.errs << _invalidTypeMsg(
        inj.path,
        (size(inj.path) > 1 ? '' : 'value ') +
        'exactly equal to ' + (size(tvals) == 1 ? '' : 'one of ') + valdesc,
        typify(inj.dparent), inj.dparent, 'V0110')
    else
      delprop(parent, key)
    end
  end

  # --- _validation: Modify callback for validate ---
  def self._validation(pval, key, parent, inj)
    return if inj.nil?
    return if pval == SKIP

    exact = getprop(inj.meta, S_BEXACT, false)
    cval = getprop(inj.dparent, key)

    return if !exact && cval.nil?

    ptype = typify(pval)
    return if 0 < (T_string & ptype) && pval.is_a?(String) && pval.include?(S_DS)

    ctype = typify(cval)

    if ptype != ctype && !pval.nil?
      inj.errs << _invalidTypeMsg(inj.path, typename(ptype), ctype, cval, 'V0010')
      return
    end

    if ismap(cval)
      if !ismap(pval)
        inj.errs << _invalidTypeMsg(inj.path, typename(ptype), ctype, cval, 'V0020')
        return
      end

      ckeys = keysof(cval)
      pkeys = keysof(pval)

      if pkeys.length > 0 && getprop(pval, '`$OPEN`') != true
        badkeys = ckeys.select { |ck| !haskey(pval, ck) }
        if badkeys.length > 0
          inj.errs << ('Unexpected keys at field ' + pathify(inj.path, 1) + S_VIZ + join(badkeys, ', '))
        end
      else
        merge([pval, cval])
        delprop(pval, '`$OPEN`') if isnode(pval)
      end

    elsif islist(cval)
      if !islist(pval)
        inj.errs << _invalidTypeMsg(inj.path, typename(ptype), ctype, cval, 'V0030')
      end

    elsif exact
      # In exact mode, check key existence for nil values
      if cval.nil? && pval.nil?
        # Both nil: only match if key actually exists in data
        if ismap(inj.dparent) && !inj.dparent.key?(key.to_s)
          inj.errs << ('Value at field ' + pathify(inj.path, 1) + ': key not present.')
        end
      elsif cval != pval
        pathmsg = size(inj.path) > 1 ? ('at field ' + pathify(inj.path, 1) + ': ') : ''
        inj.errs << ('Value ' + pathmsg + cval.to_s + ' should equal ' + pval.to_s + '.')
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
        '$ONE' => method(:validate_ONE),
        '$EXACT' => method(:validate_EXACT),
      },
      (extra.nil? ? {} : extra),
      { S_DERRS => errs },
    ], 1)

    meta = _injdef_prop(injdef, 'meta') || {}
    setprop(meta, S_BEXACT, getprop(meta, S_BEXACT, false)) if ismap(meta)

    out = transform(data, spec, {
      'meta' => meta,
      'extra' => store,
      'modify' => method(:_validation),
      'handler' => method(:_validatehandler),
      'errs' => errs,
    })

    if !errs.empty? && !collect
      raise errs.join(' | ')
    end

    out
  end

  # --- Select operators ---

  def self.select_AND(inj, _val, _ref, store)
    if S_MKEYPRE == inj.mode
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
          'meta' => inj.meta,
        })
        if !terrs.empty?
          inj.errs << ('AND:' + pathify(ppath) + "\u2A2F" + stringify(point) +
            ' fail:' + stringify(terms))
        end
      end

      gkey = getelem(inj.path, -2)
      gp = getelem(inj.nodes, -2)
      setprop(gp, gkey, point)
    end
    nil
  end

  def self.select_OR(inj, _val, _ref, store)
    if S_MKEYPRE == inj.mode
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
          'meta' => inj.meta,
        })
        if terrs.empty?
          gkey = getelem(inj.path, -2)
          gp = getelem(inj.nodes, -2)
          setprop(gp, gkey, point)
          return nil
        end
      end

      inj.errs << ('OR:' + pathify(ppath) + "\u2A2F" + stringify(point) +
        ' fail:' + stringify(terms))
    end
    nil
  end

  def self.select_NOT(inj, _val, _ref, store)
    if S_MKEYPRE == inj.mode
      term = getprop(inj.parent, inj.key)
      ppath = slice(inj.path, -1)
      point = getpath(store, ppath)

      vstore = merge([{}, store], 1)
      vstore[S_DTOP] = point

      terrs = []
      validate(point, term, {
        'extra' => vstore,
        'errs' => terrs,
        'meta' => inj.meta,
      })

      if terrs.empty?
        inj.errs << ('NOT:' + pathify(ppath) + "\u2A2F" + stringify(point) +
          ' fail:' + stringify(term))
      end

      gkey = getelem(inj.path, -2)
      gp = getelem(inj.nodes, -2)
      setprop(gp, gkey, point)
    end
    nil
  end

  def self.select_CMP(inj, _val, ref, store)
    if S_MKEYPRE == inj.mode
      term = getprop(inj.parent, inj.key)
      gkey = getelem(inj.path, -2)
      ppath = slice(inj.path, -1)
      point = getpath(store, ppath)

      pass_test = false

      begin
        if '$GT' == ref && point > term
          pass_test = true
        elsif '$LT' == ref && point < term
          pass_test = true
        elsif '$GTE' == ref && point >= term
          pass_test = true
        elsif '$LTE' == ref && point <= term
          pass_test = true
        elsif '$LIKE' == ref
          pass_test = true if stringify(point).match?(Regexp.new(term.to_s))
        end
      rescue
      end

      if pass_test
        gp = getelem(inj.nodes, -2)
        setprop(gp, gkey, point)
      else
        inj.errs << ('CMP: ' + pathify(ppath) + "\u2A2F" + stringify(point) +
          ' fail:' + ref.to_s + ' ' + stringify(term))
      end
    end
    nil
  end

  # --- select: Select children matching query ---
  def self.select(children, query)
    return [] unless isnode(children)

    if ismap(children)
      children = items(children).map { |item|
        v = item[1]
        setprop(v, '$KEY', item[0]) if ismap(v)
        v
      }
    else
      children = children.each_with_index.map { |n, i|
        setprop(n, '$KEY', i) if ismap(n)
        n
      }
    end

    results = []
    q = clone(query)

    # Add $OPEN to all maps in query
    walk(q, lambda { |_k, v, _p, _t|
      setprop(v, '`$OPEN`', getprop(v, '`$OPEN`', true)) if ismap(v)
      v
    })

    select_extra = {
      '$AND' => method(:select_AND),
      '$OR' => method(:select_OR),
      '$NOT' => method(:select_NOT),
      '$GT' => method(:select_CMP),
      '$LT' => method(:select_CMP),
      '$GTE' => method(:select_CMP),
      '$LTE' => method(:select_CMP),
      '$LIKE' => method(:select_CMP),
    }

    children.each do |child|
      terrs = []
      validate(child, clone(q), {
        'errs' => terrs,
        'meta' => { S_BEXACT => true },
        'extra' => select_extra,
      })
      results << child if terrs.empty?
    end

    results
  end

  # --- setpath ---
  def self.setpath(store, path, val, injdef = nil)
    pt = typify(path)
    if 0 < (T_list & pt)
      parts = path
    elsif 0 < (T_string & pt)
      parts = path.split(S_DT)
    elsif 0 < (T_number & pt)
      parts = [path]
    else
      return nil
    end

    base = _injdef_prop(injdef, 'base')
    numparts = size(parts)
    parent = base ? getprop(store, base, store) : store

    (0...numparts - 1).each do |pI|
      part_key = getelem(parts, pI)
      next_parent = getprop(parent, part_key)
      unless isnode(next_parent)
        next_part = getelem(parts, pI + 1)
        next_parent = (0 < (T_number & typify(next_part))) ? [] : {}
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
        if VoxgigStruct.size(@dpath) > 1
          @dpath = @dpath + [parentkey]
        end
      else
        if parentkey
          @dparent = VoxgigStruct.getprop(@dparent, parentkey)
          lastpart = VoxgigStruct.getelem(@dpath, -1)
          if lastpart == '$:' + parentkey.to_s
            @dpath = VoxgigStruct.slice(@dpath, -1)
          else
            @dpath = @dpath + [parentkey]
          end
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
      if val.nil? && (ancestor.nil? || (ancestor.is_a?(Numeric) && ancestor < 2))
        # nil without ancestor: delete from parent (matches TS undefined)
        VoxgigStruct.delprop(@parent, @key)
      elsif val.nil? && ancestor.is_a?(Numeric) && ancestor >= 2
        # nil with ancestor: set to nil in grandparent (preserves key for $ONE/$EXACT)
        VoxgigStruct.setprop(
          VoxgigStruct.getelem(@nodes, 0 - ancestor),
          VoxgigStruct.getelem(@path, 0 - ancestor),
          val
        )
      elsif ancestor.nil? || (ancestor.is_a?(Numeric) && ancestor < 2)
        VoxgigStruct.setprop(@parent, @key, val)
      else
        VoxgigStruct.setprop(
          VoxgigStruct.getelem(@nodes, 0 - ancestor),
          VoxgigStruct.getelem(@path, 0 - ancestor),
          val
        )
      end
    end

    def to_s(prefix = nil)
      'INJ' + (prefix ? '/' + prefix : '') + ':' +
        VoxgigStruct.pad(VoxgigStruct.pathify(@path, 1)) +
        (VoxgigStruct::MODENAME[VoxgigStruct::M_VAL] || '') + (@full ? '/full' : '') + ':' +
        'key=' + @keyI.to_s + '/' + @key.to_s
    end
  end

end
