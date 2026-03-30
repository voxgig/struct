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

  S_array    = 'array'
  S_boolean  = 'boolean'
  S_function = 'function'
  S_number   = 'number'
  S_object   = 'object'
  S_string   = 'string'
  S_null     = 'null'
  S_MT       = ''       # empty string constant (used as a prefix)
  S_BT       = '`'
  S_DS       = '$'
  S_DT       = '.'      # delimiter for key paths
  S_CN       = ':'      # colon for unknown paths
  S_KEY      = 'KEY'
  MAXDEPTH   = 32
  # Mongo-style select() error messages (match TS S_VIZ).
  SELECT_VIZ = ': '

  # Unique undefined marker.
  UNDEF = Object.new.freeze

  # When a transform (e.g. $REF) mutates the spec and should not write back the placeholder.
  SKIP = Object.new.freeze
  # When inject means "remove this key" (e.g. $COPY with missing key).
  REMOVE = Object.new.freeze
  # Sentinel value for setpath: delete the key at path instead of setting it.
  DELETE = Object.new.freeze

  # Type bitmask constants (match PHP/TS for test.json).
  T_any = (1 << 31) - 1
  T_noval = 1 << 30
  T_boolean = 1 << 29
  T_decimal = 1 << 28
  T_integer = 1 << 27
  T_number = 1 << 26
  T_string = 1 << 25
  T_function = 1 << 24
  T_symbol = 1 << 23
  T_null = 1 << 22
  T_list = 1 << 14
  T_map = 1 << 13
  T_instance = 1 << 12
  T_scalar = 1 << 7
  T_node = 1 << 6

  TYPENAME = %w[any noval boolean decimal integer number string function symbol null].concat([''] * 7).concat(%w[list map instance]).concat([''] * 4).concat(%w[scalar node]).freeze

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

  def self.items(val)
    if ismap(val)
      val.keys.sort.map { |k| [k.to_s, val[k]] }
    elsif islist(val)
      (0...val.length).map { |i| [i.to_s, val[i]] }
    else
      []
    end
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

  def self.stringify(val, maxlen = nil)
    return "null" if val.nil?
    if val.is_a?(String)
      json = val
    else
      begin
        v = val.is_a?(Hash) ? sorted(val) : val
        json = JSON.generate(v)
      rescue SystemStackError, JSON::NestingError
        return '__STRINGIFY_FAILED__'
      rescue StandardError
        json = val.to_s
      end
      json = json.gsub('"', '')
    end
    if maxlen && json.length > maxlen
      js = json[0, maxlen]
      json = js[0, maxlen - 3] + '...'
    end
    json
  end

  # JSON Builder helpers (ported from TS test-suite expectations).
  # - `jm(k1, v1, k2, v2, ...)` -> object
  # - `jt(v1, v2, ...)` -> array
  def self.jm(*kv)
    o = {}
    kvsize = kv.size
    i = 0
    while i < kvsize
      k = kv[i]
      key = k.is_a?(String) ? k : stringify(k)
      v = kv[i + 1]
      o[key] = v.nil? ? nil : v
      i += 2
    end
    o
  end

  def self.jt(*v)
    v
  end

  def self.jsonify(val, flags = {})
    return 'null' if val.nil? || isfunc(val)

    indent = (flags.is_a?(Hash) ? (flags['indent'] || flags[:indent]) : nil) || 2
    offset = ((flags.is_a?(Hash) ? (flags['offset'] || flags[:offset]) : nil) || 0).to_i

    indent_str = ' ' * indent.to_i

    str = JSON.generate(val,
      indent: indent_str,
      space: ' ',
      object_nl: "\n",
      array_nl: "\n"
    )

    return 'null' if str == 'null'

    # Collapse empty arrays/objects that Ruby spreads across lines (e.g. "[\n\n]" -> "[]").
    prev = nil
    while prev != str
      prev = str
      str = str.gsub(/\[\n\s*\]/, '[]').gsub(/\{\n\s*\}/, '{}')
    end

    if offset > 0
      lines = str.split("\n", -1)
      rest = lines[1..].map { |ln| ln.empty? ? ln : (' ' * offset) + ln }
      str = lines[0] + "\n" + rest.join("\n")
    end

    str
  rescue StandardError
    '__JSONIFY_FAILED__'
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
      path = path[start..-end_idx-1]
      path = [] if path.nil?
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
      pathstr = '<unknown-path' + (val.nil? ? S_CN + 'null' : S_CN + stringify(val, 47)) + '>'
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

  # Public typename - returns the type name string from a type bitmask.
  def self.typename(t)
    _typename(t)
  end

  # Integer size of a value: list/map/string -> length; number -> floor; boolean -> 1/0; else -> 0.
  def self.size(val)
    if islist(val)
      val.length
    elsif ismap(val)
      val.keys.length
    elsif val.is_a?(String)
      val.length
    elsif val.is_a?(Numeric)
      val.floor
    elsif val == true
      1
    elsif val == false
      0
    else
      0
    end
  end

  # Get element from a list by integer index (supports negative indices).
  # Returns alt (or alt.call if alt is callable) when not found.
  def self.getelem(val, key, alt = nil)
    return alt if val.equal?(UNDEF) || key.equal?(UNDEF)
    return (isfunc(alt) ? alt.call : alt) unless islist(val)

    key_str = key.to_s
    return (isfunc(alt) ? alt.call : alt) unless key_str.match?(/\A-?\d+\z/)

    nkey = key_str.to_i
    nkey = val.length + nkey if nkey < 0

    if nkey >= 0 && nkey < val.length
      val[nkey]
    else
      isfunc(alt) ? alt.call : alt
    end
  end

  # Delete a property from a map (by string key) or list (by integer index, shifting elements).
  def self.delprop(parent, key)
    return parent unless iskey(key)

    if ismap(parent)
      key_str = strkey(key)
      parent.delete(key_str)
    elsif islist(parent)
      key_str = key.to_s
      return parent unless key_str.match?(/\A-?\d+\z/)
      key_i = key_str.to_i.floor
      psize = size(parent)
      parent.delete_at(key_i) if key_i >= 0 && key_i < psize
    end

    parent
  end

  # Filter items of val using a check function. Returns array of matching values.
  def self.filter(val, check)
    all = items(val)
    out = []
    all.each { |item| out.push(item[1]) if check.call(item) }
    out
  end

  # Flatten an array by depth (default 1). Non-arrays returned unchanged.
  def self.flatten(list, depth = nil)
    return list unless islist(list)
    list.flatten(depth.nil? ? 1 : depth)
  end

  # Extract a range from an array or string, or clamp a number between [start, end-1].
  # When mutate is true, arrays are modified in place.
  def self.slice(val, start = nil, end_idx = nil, mutate = nil)
    if val.is_a?(Numeric)
      s = (start.nil? || !start.is_a?(Numeric)) ? -Float::INFINITY : start.to_f
      e = (end_idx.nil? || !end_idx.is_a?(Numeric)) ? Float::INFINITY : end_idx.to_f - 1
      return [[val, s].max, e].min
    end

    vlen = size(val)

    start = 0 if !end_idx.nil? && start.nil?

    return val if start.nil?

    if start < 0
      end_idx = vlen + start
      end_idx = 0 if end_idx < 0
      start = 0
    elsif !end_idx.nil?
      if end_idx < 0
        end_idx = vlen + end_idx
        end_idx = 0 if end_idx < 0
      elsif vlen < end_idx
        end_idx = vlen
      end
    else
      end_idx = vlen
    end

    start = vlen if vlen < start

    if start >= 0 && start <= end_idx && end_idx <= vlen
      if islist(val)
        if mutate
          (end_idx - start).times { |i| val[i] = val[start + i] }
          val.slice!((end_idx - start)..-1)
        else
          val = val[start...end_idx]
        end
      elsif val.is_a?(String)
        val = val[start...end_idx]
      end
    else
      if islist(val)
        mutate ? val.replace([]) : (val = [])
      elsif val.is_a?(String)
        val = ''
      end
    end

    val
  end

  # Pad a string to a given width. Positive padding pads right (ljust); negative pads left (rjust).
  def self.pad(str, padding = nil, padchar = nil)
    str = str.is_a?(String) ? str : stringify(str)
    padding = padding.nil? ? 44 : padding
    padchar = padchar.nil? ? ' ' : (padchar.to_s + ' ')[0]
    padding >= 0 ? str.ljust(padding, padchar) : str.rjust(-padding, padchar)
  end

  # Set a value at a dot-delimited path in a store. Missing intermediate nodes are created.
  # When val is DELETE, deletes the key at the path instead.
  # Returns the parent node of the final key.
  def self.setpath(store, path, val, injdef = nil)
    path_type = typify(path)
    parts = if (T_list & path_type) != 0
              path
            elsif (T_string & path_type) != 0
              path.to_s.split(S_DT)
            elsif (T_number & path_type) != 0
              [strkey(path)]
            else
              UNDEF
            end

    return UNDEF if parts.equal?(UNDEF)

    base = injdef && (injdef['base'] || injdef[:base])
    num_parts = size(parts)
    parent = base ? getprop(store, base, store) : store

    (0...num_parts - 1).each do |pI|
      part_key = getelem(parts, pI)
      next_parent = getprop(parent, part_key)
      unless isnode(next_parent)
        next_key = getelem(parts, pI + 1)
        # Create an array only when the next key is a numeric type (integer/decimal), not a string.
        next_parent = (T_number & typify(next_key)) != 0 ? [] : {}
        setprop(parent, part_key, next_parent)
      end
      parent = next_parent
    end

    last_key = getelem(parts, -1)
    if val.equal?(DELETE)
      delprop(parent, last_key)
    else
      setprop(parent, last_key, val)
    end

    parent
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
  def self.haskey(*args)
    if args.size == 1 && args.first.is_a?(Array) && args.first.size >= 2
      val, key = args.first[0], args.first[1]
    elsif args.size == 2
      val, key = args
    else
      return false
    end
    # Key existence (TS: NONE !== getprop). Present JSON null must be true, unlike !getprop.nil?
    !_getprop(val, key, UNDEF).equal?(UNDEF)
  end

  # Join array of strings with sep, optionally normalizing url slashes. Matches TS join().
  def self.join(arr, sep = nil, url = nil)
    return S_MT unless islist(arr)
    sepdef = sep.nil? || sep == S_MT ? ',' : sep.to_s
    sepre = (sepdef.length == 1) ? escre(sepdef) : nil
    filtered = items(arr).select { |_idx, v| (T_string & typify(v)) != 0 && v != S_MT }.map { |_i, v| v.to_s }
    return S_MT if filtered.empty?
    sarr = filtered.length
    out = filtered.each_with_index.map do |s, i|
      s = s.dup
      if sepre && sepre != S_MT
        if url && i == 0
          s = s.sub(Regexp.new(Regexp.escape(sepre) + '+$'), S_MT)
        else
          s = s.sub(Regexp.new('^' + Regexp.escape(sepre) + '+'), S_MT) if i > 0
          s = s.sub(Regexp.new(Regexp.escape(sepre) + '+$'), S_MT) if i < sarr - 1 || !url
          s = s.gsub(Regexp.new('([^' + Regexp.escape(sepre) + '])' + Regexp.escape(sepre) + '+([^' + Regexp.escape(sepre) + '])'), "\\1#{sepdef}\\2")
        end
      end
      s
    end.reject { |s| s == S_MT }.join(sepdef)
    out
  end

  def self.joinurl(parts)
    join(parts, '/', true)
  end

  # Return type bitmask (same as TS/PHP for test.json).
  def self.typify(value)
    return T_noval if value.equal?(UNDEF)
    return T_scalar | T_null if value.nil?
    return T_scalar | T_boolean if [true, false].include?(value)
    return T_scalar | T_number | T_integer if value.is_a?(Integer)
    return T_scalar | T_number | T_decimal if value.is_a?(Float)
    return T_scalar | T_string if value.is_a?(String)
    return T_scalar | T_function if isfunc(value)
    return T_scalar | T_symbol if value.is_a?(Symbol)
    return T_node | T_list if islist(value)
    return T_node | T_map if ismap(value)
    # Ruby object (e.g. custom class) -> instance type.
    return T_node | T_instance if value.is_a?(Object)
    T_noval
  end

  # Walk depth-first, matching TS walk semantics:
  # - before-only: pre-order (call before, then recurse into children)
  # - after-only: post-order (recurse into children, then call after)
  # - both before and after: call before, recurse, call after
  def self.walk(val, before = nil, after = nil, maxdepth = nil, key = nil, parent = nil, path = nil)
    path = path || []
    md = (maxdepth.nil? || maxdepth < 0) ? MAXDEPTH : maxdepth

    # Call before callback (pre-order) if provided.
    out = before ? before.call(key, val, parent, path) : val

    # Recurse into children if depth limit not reached and output is a node.
    if md > 0 && path.length < md && isnode(out)
      items(out).each do |ckey, child|
        new_path = path + [ckey.to_s]
        setprop(out, ckey, walk(getprop(out, ckey), before, after, md, ckey, out, new_path))
      end
    end

    # Call after callback (post-order) if provided.
    out = after.call(key, out, parent, path) if after

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
  #
  # Accepts an array of nodes and deep merges them (later nodes override earlier ones).
  # Optional maxdepth limits merge depth (0 = return empty container of last element's type).
  def self.merge(val, maxdepth = nil)
    return nil if val.equal?(UNDEF)
    return val unless islist(val)
    list = val
    lenlist = list.size
    return nil if lenlist == 0

    # Clamp maxdepth: negative -> 0, nil -> MAXDEPTH (matching TS slice(maxdepth ?? MAXDEPTH, 0)).
    md = maxdepth.nil? ? MAXDEPTH : (maxdepth < 0 ? 0 : maxdepth)

    # depth=0: return empty container of same type as last element (no merging).
    if md == 0
      last = list[-1]
      return islist(last) ? [] : ismap(last) ? {} : last
    end

    result = list[0]
    (1...lenlist).each do |i|
      obj = list[i]
      if !isnode(obj)
        result = obj
      else
        result = _merge_node(result, obj, md, 0)
      end
    end
    result
  end

  # Recursively merge b into a, limited to maxdepth levels.
  def self._merge_node(a, b, maxdepth, depth)
    return b unless isnode(b)
    # At maxdepth: b overrides completely.
    return b if depth >= maxdepth
    # a is not a node or different kind: b wins.
    return b unless isnode(a) && typify(a) == typify(b)

    if ismap(a) && ismap(b)
      merged = a.dup
      b.each do |k, v|
        if merged.key?(k) && isnode(merged[k]) && isnode(v) && typify(merged[k]) == typify(v)
          merged[k] = _merge_node(merged[k], v, maxdepth, depth + 1)
        else
          merged[k] = v
        end
      end
      merged
    elsif islist(a) && islist(b)
      merged = a.dup
      b.each_with_index do |v, i|
        if i < a.length && isnode(merged[i]) && isnode(v) && typify(merged[i]) == typify(v)
          merged[i] = _merge_node(merged[i], v, maxdepth, depth + 1)
        else
          merged[i] = v
        end
      end
      merged
    else
      b
    end
  end

  # --- getpath function ---
  #
  # Looks up a value deep inside a node using a dot-delimited path.
  # A path that begins with an empty string (i.e. a leading dot) is treated as relative
  # and resolved against the `current` parameter.
  # The optional state hash can provide a :base key and a :handler.
  # When preserve_undef: true, returns UNDEF when value is missing (so inject can remove keys).
  def self.getpath(path, store, current = nil, state = nil, preserve_undef: false)
    log("getpath: called with path=#{path.inspect}, store=#{store.inspect}, current=#{current.inspect}, state=#{state.inspect}")
    if path.is_a?(String) && path.start_with?('...')
      top = store.is_a?(Hash) ? getprop(store, '$TOP') : nil
      if top
        apath = path.gsub(/\A\.+/, '')
        aval = getpath(apath, top, current, nil, preserve_undef: preserve_undef)
        return aval
      end
    elsif path.is_a?(String) && path.start_with?('..')
      # One-level ancestor-style relative path: treat as standard relative from current.
      path = '.' + path[2..]
    end
    parts =
      if islist(path)
        path
      elsif path.is_a?(String)
        arr = path.split(S_DT, -1)  # -1 keeps trailing empty strings (e.g. "." -> ["",""])
        log("getpath: split path into parts=#{arr.inspect}")
        arr = [S_MT] if arr.empty?  # treat empty string as [S_MT]
        arr
      else
        UNDEF
      end
    if parts.equal?(UNDEF)
      log("getpath: parts is UNDEF, returning nil")
      return nil
    end

    root = store
    val = store
    base = state && state[:base]
    log("getpath: initial root=#{root.inspect}, base=#{base.inspect}")

    # If there is no path (or if path consists of a single empty string)
    if path.nil? || store.nil? || (parts.length == 1 && (parts[0] == S_MT || parts[0].to_s.empty?))
      # When no state/base is provided, return store directly.
      if base.nil?
        val = store
        log("getpath: no base provided; returning entire store: #{val.inspect}")
      else
        val = _getprop(store, base, UNDEF)
        log("getpath: empty or nil path; looking up base key #{base.inspect} gives #{val.inspect}")
      end
    elsif parts.length > 0
      pI = 0
      if parts[0] == S_MT
        pI = 1
        root = current
        log("getpath: relative path detected. Switching root to current: #{current.inspect}")
      end

      # If all remaining parts are empty (e.g. path was "."), return root (current) directly.
      if pI >= parts.length || parts[pI..].all? { |p| p == S_MT }
        val = root
        log("getpath: all-empty remaining path; returning root: #{val.inspect}")
      else
        # Apply $$ -> $ unescaping on all parts (TS R_DOUBLE_DOLLAR replacement).
        parts = parts.map { |p| p.is_a?(String) ? p.gsub('$$', '$') : p }

        part = (pI < parts.length ? parts[pI] : UNDEF)
        first = _getprop(root, part, UNDEF)
        log("getpath: first lookup for part=#{part.inspect} in root=#{root.inspect} yielded #{first.inspect}")
        # If not found at top level and no value present, try fallback if base is given.
        if (first.nil? || first.equal?(UNDEF)) && pI == 0 && !base.nil?
          fallback = _getprop(root, base, UNDEF)
          log("getpath: fallback lookup: _getprop(root, base) returned #{fallback.inspect}")
          val = _getprop(fallback, part, UNDEF)
          log("getpath: fallback lookup for part=#{part.inspect} yielded #{val.inspect}")
        else
          val = first
        end
        pI += 1
        while !val.equal?(UNDEF) && pI < parts.length
          log("getpath: descending into part #{parts[pI].inspect} with current val=#{val.inspect}")
          val = _getprop(val, parts[pI], UNDEF)
          pI += 1
        end
      end
    end

    if state && state[:handler] && state[:handler].respond_to?(:call)
      ref = pathify(path)
      log("getpath: applying state handler with ref=#{ref.inspect} and val=#{val.inspect}")
      val = state[:handler].call(state, val, current, ref, store)
      log("getpath: state handler returned #{val.inspect}")
    end

    final = (preserve_undef && val.equal?(UNDEF)) ? UNDEF : (val.equal?(UNDEF) ? nil : val)
    log("getpath: final returning #{final.inspect}")
    final
  end


  # In your VoxgigStruct module, add the following methods (e.g., at the bottom):

  def self._injectstr(val, store, current = nil, state = nil)
    log("(_injectstr) called with val=#{val.inspect}, store=#{store.inspect}, current=#{current.inspect}, state=#{state.inspect}")
    return S_MT unless val.is_a?(String) && val != S_MT
  
    out = val
    m = val.match(/^`(\$[A-Z]+|[^`]*)[0-9]*`$/)
    log("(_injectstr) regex match result: #{m.inspect}")
  
    if m
      state[:full] = true if state
      pathref = m[1]
      pathref = pathref.gsub('$BT', S_BT).gsub('$DS', S_DS) if pathref.to_s.length > 3

      # TS-style meta-path syntax in validation mode:
      # - `q0$=x1`  -> wrap resolved value as [`$EXACT`, value]
      # - `q0$~x1`  -> resolve as value (no exact-equality enforcement)
      if state && state[:modify].respond_to?(:name) && state[:modify].name == :_validation && state[:meta].is_a?(Hash)
        rmeta = pathref.to_s.match(/\A([^$]+)\$([=~])(.+)\z/)
        if rmeta
          meta_root = getprop(state[:meta], rmeta[1])
          resolved = getpath(rmeta[3], meta_root, nil, nil, preserve_undef: true)
          return (rmeta[2] == '=' ? ['`$EXACT`', resolved] : resolved)
        end
      end

      out = getpath(pathref, store, current, state, preserve_undef: true)
      if state && state[:handler].respond_to?(:call) && isfunc(out) && pathref.to_s.start_with?(S_DS)
        out = state[:handler].call(state, out, current, val, store)
      end
      return out if out == SKIP
      out = out.is_a?(String) ? out : JSON.generate(out) unless state&.dig(:full)
    else
      out = val.gsub(/`([^`]+)`/) do |match|
        ref = match[1..-2]  # remove the backticks
        pathref = ref.to_s.length > 3 ? ref.gsub('$BT', S_BT).gsub('$DS', S_DS) : ref
        state[:full] = false if state
        found = getpath(pathref, store, current, state)
        # When store returns a callable (e.g. $BT, $DS), call it for the substitution value.
        found = found.call if found.respond_to?(:call) && pathref.to_s.start_with?(S_DS)
        if found.nil?
          # If the key exists (even with nil), substitute "null";
          # otherwise, use an empty string.
          (store.is_a?(Hash) && store.key?(ref)) ? "null" : S_MT
        else
          # If the found value is a Hash or Array, use JSON.generate.
          if found.is_a?(Hash) || found.is_a?(Array)
            JSON.generate(found)
          else
            found.to_s
          end
        end
      end
      
        
  
      if state && state[:handler] && state[:handler].respond_to?(:call)
        state[:full] = true
        out = state[:handler].call(state, out, current, val, store)
      end
    end

    return SKIP if out == SKIP
    log("(_injectstr) returning #{out.inspect}")
    out
  end  

  # --- inject: Recursively inject store values into a node ---
  def self.inject(val, store, modify = nil, current = nil, state = nil, flag = nil)
    log("inject: called with val=#{val.inspect}, store=#{store.inspect}, modify=#{modify.inspect}, current=#{current.inspect}, state=#{state.inspect}, flag=#{flag.inspect}") 
    # If state is not provided, create a virtual root.
    if state.nil?
      parent = { S_DTOP => val }  # virtual parent container
      state = {
        mode: S_MVAL,           # current phase: value injection
        full: false,
        key: S_DTOP,            # the key this state represents
        parent: parent,         # the parent container (virtual root)
        path: [S_DTOP],
        dparent: store,        # data parent (for $COPY etc.: value at path is getprop(dparent, key))
        handler: method(:_injecthandler), # default injection handler
        base: S_DTOP,
        modify: modify,
        errs: getprop(store, S_DERRS, []),
        meta: (store.is_a?(Hash) && store.key?('$INJ_META')) ? clone(store['$INJ_META']) : {},
        nodes: [parent],
        keys: [S_DTOP]
      }
    end

    # If no current container is provided at root, use data from store when present so
    # validators see the actual data; otherwise assume a wrapper. When recursing (state set),
    # keep nil as nil so validators see "no value" at missing keys.
    current = if state && state[:key] != S_DTOP
                # Recurse: keep current as-is (may be nil for missing data)
                current
              elsif current.nil? && store.is_a?(Hash) && store.key?('$TOP')
                getprop(store, '$TOP')
              else
                current || { '$TOP' => store }
              end

    # Process based on the type of node.
    if ismap(val)
      # In validation mode, special commands may return SKIP to indicate they
      # already mutated the structure. We still need the _validation modifier
      # to run for the current node, so don't short-circuit on SKIP.
      is_validation = state && state[:modify].respond_to?(:name) && state[:modify].name == :_validation
      skip_seen = false
      # Use a mutable key list so handlers (e.g. $CHILD) can append keys during traversal.
      # Keep existing order rules: $REF keys last; $MERGE suffix order.
      # Match TS inject ordering: process keys whose *name* has `$` in second position
      # (e.g. `$OPEN`, `$AND`) *after* literal field keys, so metadata keys are not
      # validated as data fields (see select() + `$OPEN`).
      keys = val.keys.sort_by do |kk|
        vv = val[kk]
        sk = kk.to_s
        ds_key = sk.length > 1 && sk[1] == '$'
        merge_num = (sk.include?('$MERGE') && sk =~ /MERGE(\d+)/) ? Regexp.last_match(1).to_i : -1
        ref_last = merge_num >= 0 ? merge_num : 0
        ref_in_value = vv.is_a?(Array) && vv.length >= 2 && vv[0].to_s == '`$REF`'
        [ds_key ? 1 : 0, ref_in_value ? 1 : 0, ref_last, sk]
      end.map(&:to_s)
      i = 0
      while i < keys.length
        k = keys[i]
        i += 1
        next unless haskey(val, k)
        v = val[k]
        cur_data = state[:dparent] ? getprop(state[:dparent], state[:key]) : nil
        # Keep dparent as container so _validation can do getprop(dparent, key) for cval
        child_dparent = (state[:key] == S_DTOP) ? getprop(store, '$TOP') : cur_data
        child_state = state.merge({
          key: k.to_s,
          parent: val,
          path: state[:path] + [k.to_s],
          dparent: child_dparent,
          mode: S_MVAL,
          nodes: (state[:nodes] || [state[:parent]]) + [val],
          keys: keys
        })
        # key:pre phase - enables validators like $CHILD to prepare map/list traversal.
        # Match TS inject: if _injectstr returns NONE/UNDEF here, skip val inject and key:post
        # (e.g. key "`$OPEN`" — not in store — must not run _validation against data).
        pre_state = child_state.merge({ mode: S_MKEYPRE })
        prekey = _injectstr(k.to_s, store, current, pre_state)
        next unless haskey(val, k)
        # TS: NONE === undefined; _injectstr returns undefined for handler keys like `$AND`
        # after select_* run in key:pre — then the child val must not be injected/validated.
        if prekey.nil? || prekey.equal?(UNDEF)
          next
        end
        # Use cur_data as current so relative paths (e.g. `.b`) resolve in the right node
        result = inject(v, store, modify, cur_data || current, child_state, flag)
        if result == SKIP
          skip_seen = true unless is_validation
        elsif result.equal?(REMOVE)
          val.delete(k)  # key removed by transform (e.g. $COPY missing)
        else
          val[k] = result
        end
        # key:post phase - run key injection again so $MERGE etc. can mutate parent
        post_state = child_state.merge({ mode: S_MKEYPOST })
        _injectstr(k.to_s, store, current, post_state)
      end
      return SKIP if skip_seen && !is_validation
    elsif islist(val)
      skip_seen = false
      each_src_map = state[:meta].is_a?(Hash) ? state[:meta][:each_src_map] : nil
      list_path = pathify(state[:path])
      i = 0
      while i < val.length
        item = val[i]
        cur_data = state[:dparent] ? getprop(state[:dparent], state[:key]) : nil
        if each_src_map.is_a?(Hash) && each_src_map.key?(list_path)
          cur_data = each_src_map[list_path]
        end
        child_state = state.merge({
          key: i.to_s,
          parent: val,
          path: state[:path] + [i.to_s],
          dparent: cur_data,
          keyI: i,
          keys: (0...val.length).to_a.map(&:to_s),
          nodes: (state[:nodes] || [state[:parent]]) + [val]
        })
        # Validation needs strict "missing stays missing"; transforms (e.g. $EACH) need parent fallback.
        is_validation = state[:modify].respond_to?(:name) && state[:modify].name == :_validation
        child_current = is_validation ? cur_data : (cur_data || current)
        result = inject(item, store, modify, child_current, child_state, flag)
        if result == SKIP
          skip_seen = true unless is_validation
        elsif result.equal?(REMOVE)
          val.delete_at(i)
        else
          # Handler may have resized/shrunk list (e.g. validate $CHILD); only write when slot exists.
          val[i] = result if i < val.length
        end
        # Allow validators (e.g. $ONE/$EXACT/$CHILD) to move the list cursor.
        next_i = child_state[:keyI]
        default_i = result.equal?(REMOVE) ? i : (i + 1)
        i = (next_i.is_a?(Integer) && next_i > i) ? next_i : default_i
      end
      return SKIP if skip_seen && !is_validation
    elsif val.is_a?(String)
      val = _injectstr(val, store, current, state)
      return SKIP if val == SKIP
      if state[:parent]
        if val.equal?(UNDEF)
          _setparentprop(state, UNDEF)  # remove key when inject returns UNDEF (e.g. $COPY missing)
          val = REMOVE  # signal to map/list iteration to delete key
        else
          parent_obj = state[:parent]
          if parent_obj.is_a?(Array)
            idx = Integer(state[:key]) rescue nil
            setprop(parent_obj, state[:key], val) if idx && idx >= 0 && idx < parent_obj.length
          else
            setprop(parent_obj, state[:key], val) if haskey(parent_obj, state[:key])
          end
        end
      end
      log("+++ after setprop: parent now = #{state[:parent].inspect}")
    end
    

    # Call the modifier if provided.
    if modify
      mkey   = state[:key]
      mparent = state[:parent]
      mval   = getprop(mparent, mkey)
      modify.call(mval, mkey, mparent, state, current, store)
    end

    log("inject: returning #{val.inspect} for key #{state[:key].inspect}")

    # Return transformed value (REMOVE means key was removed, caller should delete)
    # At root, REMOVE means "missing" -> return nil for API callers (e.g. inject string test).
    if val.equal?(REMOVE)
      return nil if state[:key] == S_DTOP
      return REMOVE
    end
    if state[:key] == S_DTOP
      v = getprop(state[:parent], S_DTOP)
      return v.equal?(UNDEF) ? nil : v
    else
      if state[:parent].is_a?(Hash)
        return REMOVE unless haskey(state[:parent], state[:key])
      elsif state[:parent].is_a?(Array)
        idx = Integer(state[:key]) rescue nil
        return REMOVE unless idx && idx >= 0 && idx < state[:parent].length
      end
      getprop(state[:parent], state[:key])
    end

  end

  # --- _injecthandler: The default injection handler ---
  def self._injecthandler(state, val, current, ref, store)
    out = val
    # Call validator/transform when ref is $NAME or `$NAME` (full injection)
    ref_ok = ref.nil? || ref.to_s.start_with?(S_DS) || ref.to_s.include?('`$')
    if isfunc(val) && ref_ok
      out = val.call(state, val, current, ref, store)
    elsif state[:mode] == S_MVAL && state[:full]
      log("(_injecthandler) setting parent key #{state[:key]} to #{val.inspect} (full=#{state[:full]})")
      _setparentprop(state, val)
    end
    out
  end

  # Helper to update the parent's property.
  def self._setparentprop(state, val)
    log("(_setparentprop) writing #{val.inspect} to #{state[:key]} in #{state[:parent].inspect}")
    # UNDEF means "remove key" (match TS setval(NONE) -> delprop)
    if val.equal?(UNDEF)
      parent = state[:parent]
      key = state[:key]
      if parent.is_a?(Hash)
        key_str = key.to_s
        parent.delete(key_str)
        parent.delete(key.to_sym) if key.is_a?(String)
      elsif parent.is_a?(Array)
        i = Integer(key) rescue nil
        parent.delete_at(i) if i && i >= 0 && i < parent.length
      end
    else
      setprop(state[:parent], state[:key], val)
    end
  end

  # The transform_* functions are special command inject handlers (see Injector).

  # Delete a key from a map or list.
  def self.transform_delete(state, _val = nil, _current = nil, _ref = nil, _store = nil)
    _setparentprop(state, UNDEF)
    nil
  end

  # Resolve a ref path from the spec and set the result on the spec at the current key; return SKIP.
  def self.transform_ref(state, _val = nil, _current = nil, _ref = nil, store = nil)
    parent = state[:parent]
    path = state[:path] || []
    return SKIP if path.length < 2
    spec_source = store && store['$SPEC']
    spec = spec_source.respond_to?(:call) ? spec_source.call : nil
    return SKIP if spec.nil?
    refpath = getprop(parent, 1)
    ref = getpath(refpath, spec, nil, nil)
    key = path[1]
    # Self-ref or unresolved: omit key (match TS/JSON output).
    if ref.nil? || ref.equal?(UNDEF) || ref.equal?(parent)
      spec.delete(key) if spec.is_a?(Hash)
    else
      setprop(spec, key, ref)
    end
    SKIP
  end

  # Copy value from source data.
  def self.transform_copy(state, _val = nil, current = nil, _ref = nil, _store = nil)
    mode = state[:mode]
    key = state[:key]
    dparent = state[:dparent]

    out = key
    unless mode.start_with?('key')
      # Resolve from data parent (same path as spec) so root `$COPY` gets store[$TOP] = data.
      src = dparent || current
      out = if src.nil?
              UNDEF
            elsif !isnode(src)
              src
            else
              getprop(src, key, UNDEF)
            end
      # When key is missing in data, remove it from output; otherwise set (even if nil).
      _setparentprop(state, out.equal?(UNDEF) ? UNDEF : out)
    end

    out
  end

  # As a value, inject the key of the parent node.
  # As a key, defined the name of the key property in the source object.
  def self.transform_key(state, _val = nil, current = nil, _ref = nil, _store = nil)
    mode = state[:mode]
    path = state[:path]
    parent = state[:parent]

    # Do nothing in val mode.
    return nil unless mode == 'val'

    if state[:meta].is_a?(Hash) && state[:meta][:pack_src_key_map].is_a?(Hash) && path.is_a?(Array) && path.length >= 3
      ppath = pathify(path[0..-3])
      pkey = path[-2].to_s
      m = state[:meta][:pack_src_key_map][ppath]
      return m[pkey] if m.is_a?(Hash) && m.key?(pkey)
    end

    # Key is defined by $KEY meta property.
    keyspec = getprop(parent, '`$KEY`')
    if keyspec != nil
      parent.delete('`$KEY`') if parent.is_a?(Hash)
      parent.delete(:'`$KEY`') if parent.is_a?(Hash)
      return getprop(current, keyspec)
    end

    # Key is defined within general purpose $META object.
    if state[:meta].is_a?(Hash) && state[:meta][:each_key_map].is_a?(Hash) && path.is_a?(Array) && path.length >= 2
      list_path = pathify(path[0..-3])
      idx = path[-2].to_s
      if state[:meta][:each_key_map].key?(list_path) && idx =~ /\A\d+\z/
        keys = state[:meta][:each_key_map][list_path]
        key_val = keys[idx.to_i] if keys.is_a?(Array)
        return key_val unless key_val.nil?
      end
    end

    # Key is defined within general purpose $META object.
    getprop(getprop(parent, '`$META`'), 'KEY', getprop(path, path.length - 2))
  end

  # Store meta data about a node. Does nothing itself, just used by
  # other injectors, and is removed when called.
  def self.transform_meta(state, _val = nil, _current = nil, _ref = nil, _store = nil)
    parent = state[:parent]
    if parent.is_a?(Hash)
      parent.delete('`$META`')
      parent.delete(:'`$META`')
    end
    nil
  end

  # Merge a list of objects into the current object.
  # Must be a key in an object. The value is merged over the current object.
  # If the value is an array, the elements are first merged using `merge`.
  # If the value is the empty string, merge the top level store.
  # Format: { '`$MERGE`': '`source-path`' | ['`source-paths`', ...] }
  def self.transform_merge(state, _val = nil, current = nil, _ref = nil, store = nil)
    mode = state[:mode]
    key = state[:key]
    parent = state[:parent]

    return key if mode == S_MKEYPRE

    # Operate after child values have been transformed.
    if mode == S_MKEYPOST
      args = getprop(parent, key)
      args = (args == '' || args == S_MT) ? (store && getprop(store, S_DTOP) ? [getprop(store, S_DTOP)] : []) : (args.is_a?(Array) ? args : [args])
      args = args.map do |a|
        if a == '.' || a == '`.`'
          current
        elsif a.is_a?(String) && a.start_with?('`') && a.end_with?('`')
          _injectstr(a, store, current, state)
        else
          a
        end
      end

      # Remove the $MERGE command from a parent map.
      _setparentprop(state, UNDEF)

      # Literals in the parent have precedence, but command keys should not.
      # Preserve only non-command keys in the final overlay.
      preserved = {}
      if parent.is_a?(Hash)
        parent.each do |pk, pv|
          sk = pk.to_s
          preserved[pk] = clone(pv) unless sk.start_with?('`$')
        end
      end
      mergelist = [parent, *args, preserved]
      merged = merge(mergelist)
      parent.replace(merged) if parent.is_a?(Hash) && merged.is_a?(Hash)

      return key
    end

    # Ensures $MERGE is removed from parent list.
    return REMOVE if mode == S_MVAL && parent.is_a?(Array)
    nil
  end

  # Convert a node to a list.
  def self.transform_each(state, val, current, ref, store)
    mode = state[:mode]
    parent = state[:parent]
    key_i = state[:keyI]
    return nil unless mode == S_MVAL
    return nil unless parent.is_a?(Array) && key_i == 0

    args = parent[1..-1] || []
    srcpath = args[0]
    child = args[1]
    return nil unless srcpath.is_a?(String)

    srcstore = getprop(store, state[:base], store)
    src = getpath(srcpath, srcstore, current, nil)

    tval = []
    src_values = nil
    if islist(src)
      src_values = src
      tval = src.map { |_n| clone(child) }
    elsif ismap(src)
      src_values = src.values
      tval = src.map do |k, _v|
        merge([clone(child), { '`$META`' => { 'KEY' => k } }])
      end
    end

    if state[:meta].is_a?(Hash)
      state[:meta][:each_src_map] ||= {}
      state[:meta][:each_src_map][pathify(state[:path][0..-2])] = src_values if src_values
      if ismap(src)
        state[:meta][:each_key_map] ||= {}
        state[:meta][:each_key_map][pathify(state[:path][0..-2])] = src.keys.map(&:to_s)
      end
    end

    # Simple passthrough: each child is just `$COPY`.
    if child.is_a?(String) && child == '`$COPY`' && src_values.is_a?(Array)
      parent.replace(src_values.map { |v| clone(v) })
      state[:keyI] = parent.length
      return getprop(parent, 0)
    end

    # Simple per-item formatting, e.g. ['$FORMAT','upper','`$COPY`'].
    if child.is_a?(Array) && child[0].to_s == '`$FORMAT`' && src_values.is_a?(Array)
      fmt = child[1].to_s.downcase
      srcspec = child[2]
      out = src_values.map do |sv|
        base = if srcspec.is_a?(String) && srcspec == '`$COPY`'
                 sv
               elsif srcspec.is_a?(String)
                 inject(srcspec, merge([{}, store, { '$TOP' => sv }]))
               else
                 srcspec
               end
        s = base.nil? ? '' : base.to_s
        fmt == 'upper' ? s.upcase : (fmt == 'lower' ? s.downcase : s)
      end
      parent.replace(out)
      state[:keyI] = parent.length
      return getprop(parent, 0)
    end

    # Special-case: child template merges current item via `$MERGE`: ".".
    if child.is_a?(Hash) && src_values.is_a?(Array)
      mkey = child.keys.find { |kk| kk.to_s.start_with?('`$MERGE') }
      mref = mkey.nil? ? nil : child[mkey]
      if mref == '.' || mref == '`.`'
        plain_child = clone(child)
        plain_child.delete(mkey)
        tval = src_values.map do |sv|
          merged_node = merge([clone(sv), clone(plain_child)])
          local_store = merge([{}, store, { '$TOP' => sv }])
          inject(merged_node, local_store, state[:modify], sv)
        end
        parent.replace(tval)
        state[:keyI] = parent.length
        return getprop(parent, 0)
      end
    end

    parent.replace(tval)
    if tval.any? && src_values.is_a?(Array)
      tval.each_with_index do |tmpl, idx|
        if tmpl.is_a?(Hash)
          mkey = tmpl.keys.find { |kk| kk.to_s.start_with?('`$MERGE') }
          mref = mkey.nil? ? nil : tmpl[mkey]
          if mref == '.' || mref == '`.`'
            merged_tmpl = merge([clone(src_values[idx]), clone(tmpl)])
            if merged_tmpl.is_a?(Hash)
              merged_tmpl.keys.each { |mk| merged_tmpl.delete(mk) if mk.to_s.start_with?('`$MERGE') }
            end
            tmpl = merged_tmpl
            tval[idx] = tmpl
          end
        end
        child_state = state.merge({
          key: idx.to_s,
          parent: tval,
          path: state[:path][0..-2] + [idx.to_s],
          dparent: src_values,
          keyI: idx,
          keys: (0...tval.length).to_a.map(&:to_s),
          nodes: (state[:nodes] || [state[:parent]]) + [tval]
        })
        res = inject(tmpl, store, state[:modify], src_values[idx], child_state)
        if res.equal?(REMOVE)
          tval.delete_at(idx)
        elsif res != SKIP
          tval[idx] = res
        end
        if idx < tval.length && tval[idx].is_a?(Hash)
          mmk = tval[idx].keys.find { |kk| kk.to_s.start_with?('`$MERGE') }
          mmv = mmk.nil? ? nil : tval[idx][mmk]
          if mmv == '.' || mmv == '`.`'
            forced = clone(tval[idx])
            forced.delete(mmk)
            forced = merge([clone(src_values[idx]), forced])
            tval[idx] = inject(forced, store, state[:modify], src_values[idx], child_state)
          end
        end
      end
    end

    # Skip outer list-loop processing of this generated list.
    state[:keyI] = parent.length
    getprop(parent, 0)
  end

  # Format a scalar/string value.
  # Format: ['`$FORMAT`', 'upper'|'lower', value]
  def self.transform_format(state, _val = nil, current = nil, _ref = nil, store = nil)
    mode = state[:mode]
    parent = state[:parent]
    key_i = state[:keyI]
    nodes = state[:nodes] || []
    path = state[:path] || []
    return nil unless mode == S_MVAL
    return nil unless parent.is_a?(Array) && key_i == 0

    fmt = getprop(parent, 1)
    src = getprop(parent, 2)

    resolved = if src.is_a?(String)
                 _injectstr(src, store, current, state)
               else
                 src
               end

    f = fmt.to_s.downcase
    formatter = nil
    case f
    when 'upper'
      formatter = lambda do |_k, v, _p, _path|
        isnode(v) ? v : (v.nil? ? 'null' : v.to_s).upcase
      end
    when 'lower'
      formatter = lambda do |_k, v, _p, _path|
        isnode(v) ? v : (v.nil? ? 'null' : v.to_s).downcase
      end
    when 'identity'
      formatter = lambda do |_k, v, _p, _path|
        v
      end
    when 'string'
      formatter = lambda do |_k, v, _p, _path|
        isnode(v) ? v : (v.nil? ? 'null' : v.to_s)
      end
    when 'number'
      formatter = lambda do |_k, v, _p, _path|
        next v if isnode(v)
        if v.nil?
          0
        elsif v.is_a?(Integer)
          v
        elsif v.is_a?(Float)
          v
        elsif [true, false].include?(v)
          v ? 1 : 0
        else
          s = v.to_s
          n = begin
            Float(s)
          rescue
            Float::NAN
          end
          if n.nan?
            0
          else
            (n % 1 == 0) ? n.to_i : n
          end
        end
      end
    when 'integer'
      formatter = lambda do |_k, v, _p, _path|
        next v if isnode(v)
        if v.nil?
          0
        elsif v.is_a?(Integer)
          v
        elsif v.is_a?(Float)
          v.to_i
        elsif [true, false].include?(v)
          v ? 1 : 0
        else
          s = v.to_s
          n = begin
            Float(s)
          rescue
            Float::NAN
          end
          n = 0 if n.nan?
          n.to_i
        end
      end
    when 'concat'
      formatter = lambda do |k, v, _p, _path|
        if k.nil? && islist(v)
          v.map do |elem|
            isnode(elem) ? '' : (elem.nil? ? 'null' : elem.to_s)
          end.join('')
        else
          v
        end
      end
    else
      raise '$FORMAT: unknown format: ' + fmt.to_s + '.'
    end

    out = walk(resolved, formatter)

    # Replace the command list node with final scalar output.
    if path.length >= 2
      grandparent = nodes[nodes.length - 2]
      grandkey = path[path.length - 2]
      setprop(grandparent, grandkey, out) if grandparent
    end
    state[:keyI] = parent.length
    out
  end

  # Apply a function to a resolved child value.
  # Format: ['`$APPLY`', fn, child]
  def self.transform_apply(state, _val = nil, current = nil, _ref = nil, store = nil)
    ijname = 'APPLY'
    mode = state[:mode]
    parent = state[:parent]
    key_i = state[:keyI]
    nodes = state[:nodes] || []
    path = state[:path] || []

    # Must be used as a value (not as key) and require parent list placement.
    if mode != S_MVAL
      raise '$' + ijname + ': invalid placement as key, expected: value.'
    end
    raise '$' + ijname + ': invalid placement in parent ' + _typename(typify(parent)) + ', expected: list.' unless islist(parent)

    # Only execute once at the beginning of the command list.
    return nil unless key_i == 0

    apply_fn = getprop(parent, 1)
    child = getprop(parent, 2)

    unless isfunc(apply_fn)
      arg_type = _typename(typify(apply_fn))
      raise '$' + ijname + ': invalid argument: ' +
        stringify(apply_fn) + ' (' + arg_type + ' at position 1) is not of type: function.'
    end

    resolved_child = child.is_a?(String) ? _injectstr(child, store, current, state) : child

    out =
      if apply_fn.arity == 0
        apply_fn.call
      elsif apply_fn.arity == 1
        apply_fn.call(resolved_child)
      else
        # TS passes (resolved, store, cinj). Ruby lambdas in tests usually only need arity=1.
        apply_fn.call(resolved_child, store, nil)
      end

    if path.length >= 2
      grandparent = nodes[nodes.length - 2]
      grandkey = path[path.length - 2]
      setprop(grandparent, grandkey, out) if grandparent
    end

    state[:keyI] = parent.length
    out
  end

  # Convert a node to a map.
  def self.transform_pack(state, val, current, ref, store)
    mode = state[:mode]
    key = state[:key]
    parent = state[:parent]
    return nil unless mode == S_MKEYPRE && parent.is_a?(Hash)

    args = getprop(parent, key)
    srcpath = args.is_a?(Array) ? args[0] : nil
    childspec = args.is_a?(Array) ? args[1] : nil
    return nil unless srcpath.is_a?(String)

    srcstore = getprop(store, state[:base], store)
    src = getpath(srcpath, srcstore, current, nil)

    src_entries =
      if islist(src)
        src.each_with_index.map { |n, i| [i.to_s, n] }
      elsif ismap(src)
        src.map { |k0, n| [k0.to_s, n] }
      else
        []
      end

    keypath = ismap(childspec) ? getprop(childspec, '`$KEY`') : nil
    base_child = ismap(childspec) ? getprop(childspec, '`$VAL`', childspec) : childspec
    child = clone(base_child)
    if child.is_a?(Hash)
      child.delete('`$KEY`')
      child.delete(:'`$KEY`')
      child.delete('`$VAL`')
      child.delete(:'`$VAL`')
    end

    tval = {}
    if state[:meta].is_a?(Hash)
      state[:meta][:pack_src_key_map] ||= {}
      ppath = pathify(state[:path][0..-2])
      state[:meta][:pack_src_key_map][ppath] ||= {}
    end
    src_entries.each do |srckey, srcnode|
      k = srckey
      if keypath.is_a?(String) && keypath.start_with?('`')
        k = inject(keypath, merge([{}, store, { '$TOP' => srcnode }]))
      elsif keypath.is_a?(String)
        k = getpath(keypath, srcnode, srcnode, nil)
      end
      if ismap(src) && state[:meta].is_a?(Hash)
        ppath = pathify(state[:path][0..-2])
        state[:meta][:pack_src_key_map][ppath][k.to_s] = srckey
      end

      tchild = clone(child)
      if ismap(src) && tchild.is_a?(Hash)
        tchild['`$META`'] ||= {}
        tchild['`$META`']['KEY'] = srckey
      end
      if tchild.is_a?(Array) && tchild[0].to_s == '`$FORMAT`'
        fmt = tchild[1].to_s.downcase
        srcspec = tchild[2]
        base = if srcspec.is_a?(String) && srcspec == '`$COPY`'
                 srcnode
               elsif srcspec.is_a?(String)
                 inject(srcspec, merge([{}, store, { '$TOP' => srcnode }]))
               else
                 srcspec
               end
        s = base.nil? ? '' : base.to_s
        tchild = (fmt == 'upper' ? s.upcase : (fmt == 'lower' ? s.downcase : s))
      else
        setprop(tval, k.to_s, tchild)
        child_state = state.merge({
          mode: S_MVAL,
          key: k.to_s,
          parent: tval,
          path: state[:path][0..-2] + [k.to_s],
          dparent: srcnode
        })
        tchild = inject(tchild, store, state[:modify], srcnode, child_state)
      end
      tval[k.to_s] = tchild
    end

    # Remove command key and write packed result into this map.
    parent.delete(key) if parent.is_a?(Hash)
    tval.each { |pk, pv| parent[pk] = pv }
    nil
  end

  # Transform data using spec.
  def self.transform(data, spec, extra = nil, modify = nil)
    # Clone the spec so that the clone can be modified in place as the transform result.
    spec = clone(spec)

    extra_transforms = {}
    extra_data = if extra.nil?
      nil
    else
      items(extra).reduce({}) do |a, n|
        if n[0].start_with?(S_DS)
          extra_transforms[n[0]] = n[1]
        else
          a[n[0]] = n[1]
        end
        a
      end
    end

    data_clone = merge([
      isempty(extra_data) ? nil : clone(extra_data),
      clone(data)
    ])

    # Define a top level store that provides transform operations.
    store = {
      # The inject function recognises this special location for the root of the source data.
      # NOTE: to escape data that contains "`$FOO`" keys at the top level,
      # place that data inside a holding map: { myholder: mydata }.
      '$TOP' => data_clone,

      # Escape backtick (this also works inside backticks).
      '$BT' => ->(_state = nil, _val = nil, _current = nil, _ref = nil, _store = nil) { S_BT },

      # Escape dollar sign (this also works inside backticks).
      '$DS' => ->(_state = nil, _val = nil, _current = nil, _ref = nil, _store = nil) { S_DS },

      # Insert current date and time as an ISO string.
      '$WHEN' => ->(_state = nil, _val = nil, _current = nil, _ref = nil, _store = nil) { Time.now.iso8601 },

      '$DELETE' => method(:transform_delete),
      '$COPY' => method(:transform_copy),
      '$KEY' => method(:transform_key),
      '$META' => method(:transform_meta),
      '$MERGE' => method(:transform_merge),
      '$EACH' => method(:transform_each),
      '$FORMAT' => method(:transform_format),
      '$APPLY' => method(:transform_apply),
      '$PACK' => method(:transform_pack),
      '$SPEC' => ->(_s = nil, _v = nil, _c = nil, _r = nil, _st = nil) { spec },
      '$REF' => method(:transform_ref),

      # Custom extra transforms, if any.
      **extra_transforms
    }

    out = inject(spec, store, modify, data_clone)
    out = spec if out == SKIP
    out = nil if out.equal?(UNDEF) || out.equal?(REMOVE)
    out
  end

  # Update all references to target in state.nodes.
  def self._update_ancestors(_state, target, tkey, tval)
    # SetProp is sufficient in Ruby as target reference remains consistent even for lists.
    setprop(target, tkey, tval)
  end

  def self._typename(type)
    return 'any' if type.nil? || type <= 0
    idx = (31 - Math.log2(type).floor).to_i
    names = %w[any noval boolean decimal integer number string function symbol null] + ([''] * 7) + %w[list map instance] + ([''] * 4) + %w[scalar node]
    names[idx] || 'any'
  end

  # Build a type validation error message.
  def self._invalid_type_msg(path, needtype, vt, v, _whence = nil)
    needtype_str = needtype.is_a?(Integer) ? (_typename(needtype) rescue needtype.to_s) : needtype.to_s
    vt_str = vt.is_a?(Integer) ? (_typename(vt) rescue vt.to_s) : vt.to_s
    vs = if v.nil?
           'no value'
         elsif v.respond_to?(:call) || (v.is_a?(Hash) && v.values.any? { |x| x.respond_to?(:call) })
           vt_str
         else
           s = stringify(v)
           (s.to_s.length > 80 || s.to_s.include?('#<')) ? vt_str : s
         end

    'Expected ' +
      (path.length > 1 ? ('field ' + pathify(path, 1) + ' to be ') : '') +
      needtype_str + ', but found ' +
      (v.nil? ? '' : vt_str + ': ') + vs +
      # Uncomment to help debug validation errors.
      # ' [' + _whence + ']' +
      '.'
  end

  # Value at current path: at root (key == $TOP) use current itself, else getprop(current, key).
  def self._cval(state, current)
    return current if state[:key] == S_DTOP
    # For validators inside ONE/EXACT lists, `current` can be a scalar while key is list index.
    # In that case validate against the scalar itself.
    return current unless isnode(current)
    getprop(current, state[:key])
  end

  # A required string value. NOTE: Rejects empty strings.
  def self.validate_string(state, _val = nil, current = nil, _ref = nil, _store = nil)
    out = _cval(state, current)

    t = typify(out)
    if (T_string & t) == 0
      msg = _invalid_type_msg(state[:path], S_string, t, out, 'V1010')
      state[:errs].push(msg)
      return nil
    end

    if out == S_MT
      msg = 'Empty string at ' + pathify(state[:path], 1)
      state[:errs].push(msg)
      return nil
    end

    out
  end

  # A required number value (int or float).
  def self.validate_number(state, _val = nil, current = nil, _ref = nil, _store = nil)
    out = _cval(state, current)

    t = typify(out)
    if (T_number & t) == 0
      state[:errs].push(_invalid_type_msg(state[:path], S_number, t, out, 'V1020'))
      return nil
    end

    out
  end

  # A required boolean value.
  def self.validate_boolean(state, _val = nil, current = nil, _ref = nil, _store = nil)
    out = _cval(state, current)

    t = typify(out)
    if (T_boolean & t) == 0
      state[:errs].push(_invalid_type_msg(state[:path], S_boolean, t, out, 'V1030'))
      return nil
    end

    out
  end

  # A required object (map) value (contents not validated).
  def self.validate_object(state, _val = nil, current = nil, _ref = nil, _store = nil)
    out = _cval(state, current)

    t = typify(out)
    if (T_map & t) == 0
      state[:errs].push(_invalid_type_msg(state[:path], 'object', t, out, 'V1040'))
      return nil
    end

    out
  end

  # A required array (list) value (contents not validated).
  def self.validate_array(state, _val = nil, current = nil, _ref = nil, _store = nil)
    out = _cval(state, current)

    t = typify(out)
    if (T_list & t) == 0
      state[:errs].push(_invalid_type_msg(state[:path], 'array', t, out, 'V1050'))
      return nil
    end

    out
  end

  # A required function value.
  def self.validate_function(state, _val = nil, current = nil, _ref = nil, _store = nil)
    out = _cval(state, current)

    t = typify(out)
    if (T_function & t) == 0
      state[:errs].push(_invalid_type_msg(state[:path], S_function, t, out, 'V1060'))
      return nil
    end

    out
  end

  # Generic type validator: ref is e.g. "`$INTEGER`", validates by type name.
  def self.validate_type(state, _val = nil, current = nil, ref = nil, _store = nil)
    return nil if ref.nil? || !ref.to_s.include?(S_DS)
    tname = ref.to_s.gsub(/^`?\$?/, '').gsub(/`$/, '').downcase
    needname = tname
    tname = 'null' if tname == 'nil'
    idx = TYPENAME.index(tname)
    typev = (idx && idx >= 0) ? (1 << (31 - idx)) : 0
    out = _cval(state, current)
    t = typify(out)
    if typev <= 0 || (t & typev) == 0
      state[:errs].push(_invalid_type_msg(state[:path], needname, t, out, 'V1001'))
      return nil
    end
    # Omit key from output when type is null/nil and value is nil (match TS $NIL/$NULL)
    return UNDEF if (tname == 'null' || tname == 'nil') && out.nil?
    out
  end

  # Allow any value.
  def self.validate_any(state, _val = nil, current = nil, _ref = nil, _store = nil)
    _cval(state, current)
  end

  # Specify child values for map or list.
  # Map syntax: {'`$CHILD`': child-template }
  # List syntax: ['`$CHILD`', child-template ]
  def self.validate_child(state, _val = nil, current = nil, _ref = nil, _store = nil)
    mode = state[:mode]
    key = state[:key]
    parent = state[:parent]
    keys = state[:keys]
    path = state[:path]

    # Map syntax.
    if mode == S_MKEYPRE
      childtm = getprop(parent, key)

      # Get corresponding current object.
      pkey = getprop(path, path.length - 2)
      tval = getprop(current, pkey)

      if tval.nil?
        tval = {}
      elsif !ismap(tval)
        state[:errs].push(_invalid_type_msg(
          state[:path][0..-2], S_object, typify(tval), tval, 'V0220'))
        return nil
      end

      ckeys = keysof(tval)
      ckeys.each do |ckey|
        setprop(parent, ckey, clone(childtm))

        # NOTE: modifying state! This extends the child value loop in inject.
        keys.push(ckey)
      end

      # Remove $CHILD to cleanup output.
      _setparentprop(state, UNDEF)
      return nil
    end

    # List syntax.
    if mode == S_MVAL
      if !islist(parent)
        # $CHILD was not inside a list.
        state[:errs].push('Invalid $CHILD as value')
        return nil
      end

      childtm = getprop(parent, 1)

      if current.nil?
        # Empty list as default.
        parent.clear
        return nil
      end

      if !islist(current)
        msg = _invalid_type_msg(
          state[:path][0..-2], S_array, typify(current), current, 'V0230')
        state[:errs].push(msg)
        state[:keyI] = parent.length
        return current
      end

      # Clone children and reset state key index.
      # The inject child loop will now iterate over the cloned children,
      # validating them against the current list values.
      current.each_with_index { |_n, i| parent[i] = clone(childtm) }
      parent.replace(current.map { |_n| clone(childtm) })
      state[:keyI] = 0
      out = getprop(current, 0)
      return out
    end

    nil
  end

  # Match at least one of the specified shapes.
  # Syntax: ['`$ONE`', alt0, alt1, ...]
  def self.validate_one(state, _val = nil, current = nil, _ref = nil, store = nil)
    mode = state[:mode]
    parent = state[:parent]
    path = state[:path]
    keyI = state[:keyI]
    nodes = state[:nodes]

    # Only operate in val mode, since parent is a list.
    if mode == S_MVAL
      if !islist(parent) || keyI != 0
        state[:errs].push('The $ONE validator at field ' +
          pathify(state[:path], 1) +
          ' must be the first element of an array.')
        return
      end

      state[:keyI] = state[:keys].length

      grandparent = nodes[nodes.length - 2]
      grandkey = path[path.length - 2]

      # Clean up structure, replacing [$ONE, ...] with current
      setprop(grandparent, grandkey, current)
      state[:path] = state[:path][0..-2]
      state[:key] = state[:path][state[:path].length - 1]

      tvals = parent[1..-1]
      if tvals.empty?
        state[:errs].push('The $ONE validator at field ' +
          pathify(state[:path], 1) +
          ' must have at least one argument.')
        return
      end

      # See if we can find a match.
      tvals.each do |tval|
        # If match, then terrs stays empty.
        terrs = []

        # Validate current value against each alternative shape.
        # Pass only collected errors; don't pass a transform store as `extra`.
        vcurrent = validate(current, tval, nil, terrs)
        setprop(grandparent, grandkey, vcurrent)

        # Accept current value if there was a match
        return if terrs.empty?
      end

      # There was no match.
      valdesc = tvals
        .map { |v| stringify(v) }
        .join(', ')
        .gsub(/`\$([A-Z]+)`/) { Regexp.last_match(1).downcase }

      state[:errs].push(_invalid_type_msg(
        state[:path],
        (tvals.length > 1 ? 'one of ' : '') + valdesc,
        typify(current), current, 'V0210'))
    end
  end

  def self.validate_exact(state, _val = nil, current = nil, _ref = nil, _store = nil)
    mode = state[:mode]
    parent = state[:parent]
    key = state[:key]
    keyI = state[:keyI]
    path = state[:path]
    nodes = state[:nodes]

    # Only operate in val mode, since parent is a list.
    if mode == S_MVAL
      if !islist(parent) || keyI != 0
        state[:errs].push('The $EXACT validator at field ' +
          pathify(state[:path], 1) +
          ' must be the first element of an array.')
        return
      end

      state[:keyI] = state[:keys].length

      grandparent = nodes[nodes.length - 2]
      grandkey = path[path.length - 2]

      # Clean up structure, replacing [$EXACT, ...] with current
      setprop(grandparent, grandkey, current)
      state[:path] = state[:path][0..-2]
      state[:key] = state[:path][state[:path].length - 1]

      tvals = parent[1..-1]
      if tvals.empty?
        state[:errs].push('The $EXACT validator at field ' +
          pathify(state[:path], 1) +
          ' must have at least one argument.')
        return
      end

      # See if we can find an exact value match.
      currentstr = nil
      tvals.each do |tval|
        exactmatch = tval == current

        if !exactmatch && isnode(tval)
          currentstr ||= stringify(current)
          tvalstr = stringify(tval)
          exactmatch = tvalstr == currentstr
        end

        return if exactmatch
      end

      valdesc = tvals
        .map { |v| stringify(v) }
        .join(', ')
        .gsub(/`\$([A-Z]+)`/, &:downcase)

      state[:errs].push(_invalid_type_msg(
        state[:path],
        (state[:path].length > 1 ? '' : 'value ') +
        'exactly equal to ' + (tvals.length == 1 ? '' : 'one of ') + valdesc,
        typify(current), current, 'V0110'))
    else
      setprop(parent, key, nil)
    end
  end

  # This is the "modify" argument to inject. Use this to perform
  # generic validation. Runs *after* any special commands.
  def self._validation(pval, key = nil, parent = nil, state = nil, current = nil, _store = nil)
    return if state.nil?

    exact = state[:meta].is_a?(Hash) && state[:meta]['`$EXACT`'] == true

    # Missing key (UNDEF) vs present JSON null (nil). TS skips missing fields unless exact (select).
    cval = if key == S_DTOP
             current
           elsif !key.nil? && isnode(state[:dparent])
             raw = _getprop(state[:dparent], key, UNDEF)
             if raw.equal?(UNDEF)
               return unless exact
               # Keep UNDEF (TS NONE) so exact `null` spec does not match a missing key.
               raw
             else
               raw
             end
           elsif !key.nil? && key != S_DTOP
             # No data container (TS: cval is NONE); skip unless select-style exact.
             return unless exact
             UNDEF
           else
             getprop(state[:dparent], key)
           end

    return if state.nil?

    # TS-style exact-equality wrapper: [`$EXACT`, expected]
    # This is used by validation meta-paths like `q0$=x1`.
    if islist(pval) && pval.length >= 2 && pval[0].to_s == '`$EXACT`'
      tvals = pval[1..-1]
      currentstr = nil
      exactmatch = false

      tvals.each do |tval|
        if tval == cval
          exactmatch = true
          break
        end
        if !exactmatch && isnode(tval)
          currentstr ||= stringify(cval)
          exactmatch = stringify(tval) == currentstr
        end
      end

      unless exactmatch
        valdesc = tvals
          .map { |v| stringify(v) }
          .join(', ')
          .gsub(/`\$([A-Z]+)`/, &:downcase)

        needtype = (tvals.length == 1 ? '' : 'one of ') + valdesc
        needtype = (state[:path].length > 1 ? '' : 'value ') + 'exactly equal to ' + needtype

        state[:errs].push(_invalid_type_msg(state[:path], needtype, typify(cval), cval, 'V0110'))
      else
        setprop(parent, key, cval) if parent && key
      end
      return
    end

    ptype = typify(pval)

    # Delete any special commands remaining.
    return if ptype == S_string && pval.is_a?(String) && pval.include?(S_DS)

    ctype = typify(cval)

    # When types match at a scalar leaf, output the data value (so validate returns data, not spec).
    if ptype == ctype && !pval.nil? && parent && key && !isnode(pval) && !isnode(cval) && !exact
      setprop(parent, key, cval)
    end

    # Type mismatch. When spec value is nil (e.g. after $EXACT replaced with data), don't error on node data.
    if ptype != ctype && !pval.nil?
      state[:errs].push(_invalid_type_msg(state[:path], ptype, ctype, cval, 'V0010'))
      return
    end
    if pval.nil? && cval && (T_node & typify(cval)) != 0
      # Spec was replaced with nil (e.g. $EXACT placeholder); data is present, accept it.
      setprop(parent, key, cval) if parent && key
      return
    end

    if ismap(cval)
      if !ismap(pval)
        state[:errs].push(_invalid_type_msg(state[:path], ptype, ctype, cval, 'V0020'))
        return
      end

      ckeys = keysof(cval)
      pkeys = keysof(pval)

      # Empty spec object {} means object can be open (any keys).
      if !pkeys.empty? && getprop(pval, '`$OPEN`') != true
        badkeys = []
        ckeys.each do |ckey|
          badkeys.push(ckey) unless haskey(pval, ckey)
        end

        # Closed object, so reject extra keys not in shape.
        if !badkeys.empty?
          msg = 'Unexpected keys at field ' + pathify(state[:path], 1) + ': ' + badkeys.join(', ')
          state[:errs].push(msg)
        end
      else
        # Object is open, so merge in extra keys and set result back on parent.
        merged = merge([pval, cval])
        setprop(parent, key, merged) if parent && key
        if isnode(merged)
          merged.delete('`$OPEN`')
          merged.delete(:'`$OPEN`')
        end
      end
    elsif islist(cval)
      if !islist(pval)
        state[:errs].push(_invalid_type_msg(state[:path], ptype, ctype, cval, 'V0030'))
      end
    else
      if exact
        if cval != pval
          pathmsg = state[:path].length > 1 ? ('at field ' + pathify(state[:path], 1) + ': ') : S_MT
          cshow = cval.equal?(UNDEF) ? 'no value' : stringify(cval)
          state[:errs].push('Value ' + pathmsg + cshow +
            ' should equal ' + pval.to_s + S_DT)
        end
      else
        # Spec value was a default, copy over data
        setprop(parent, key, cval)
      end
    end
  end

  # --- select (Mongo-style queries via validate + logical operators) ---

  def self.select_extras
    {
      '$AND' => method(:select_and),
      '$OR' => method(:select_or),
      '$NOT' => method(:select_not),
      '$GT' => method(:select_cmp),
      '$LT' => method(:select_cmp),
      '$GTE' => method(:select_cmp),
      '$LTE' => method(:select_cmp),
      '$LIKE' => method(:select_cmp)
    }
  end

  def self._select_open_query(q)
    return if q.nil?
    walk(q, lambda do |_k, v, _parent, _path|
      if ismap(v)
        ov = v['`$OPEN`']
        ov = v[:'`$OPEN`'] if ov.nil? && v.is_a?(Hash)
        v['`$OPEN`'] = ov.nil? ? true : ov
      end
      v
    end)
  end

  def self.select(obj, query)
    return [] unless isnode(obj)

    children =
      if ismap(obj)
        items(obj).map do |k, v|
          c = clone(v)
          setprop(c, '$KEY', k)
          c
        end
      else
        obj.each_with_index.map do |v, i|
          c = clone(v)
          setprop(c, '$KEY', i)
          c
        end
      end

    q = clone(query)
    _select_open_query(q)

    meta = { '`$EXACT`' => true }
    extras = select_extras

    results = []
    children.each do |child|
      terrs = []
      vchild = clone(child)
      if vchild.is_a?(Hash)
        vchild.delete('$KEY')
        vchild.delete(:'$KEY')
      end
      validate(vchild, clone(q), { 'meta' => meta }.merge(extras), terrs)
      results.push(child) if terrs.empty?
    end
    results
  end

  def self.select_and(state, _fn, current, ref, store)
    return nil unless state[:mode] == S_MKEYPRE

    terms = getprop(state[:parent], state[:key])
    terms = [] unless islist(terms)

    path = state[:path] || []
    ppath = path.length >= 2 ? path[0...-1] : [S_DTOP]
    point = getpath(ppath, store)

    terms.each do |term|
      terrs = []
      validate(point, clone(term), { 'meta' => state[:meta] }.merge(select_extras), terrs)
      unless terrs.empty?
        state[:errs].push(
          'AND:' + pathify(ppath) + SELECT_VIZ + stringify(point) + ' fail:' + stringify(terms)
        )
      end
    end

    gkey = path[-2]
    gp = state[:nodes][-2]
    setprop(gp, gkey, point) if gp && !gkey.nil?
    nil
  end

  def self.select_or(state, _fn, current, ref, store)
    return nil unless state[:mode] == S_MKEYPRE

    terms = getprop(state[:parent], state[:key])
    terms = [] unless islist(terms)

    path = state[:path] || []
    ppath = path.length >= 2 ? path[0...-1] : [S_DTOP]
    point = getpath(ppath, store)

    gkey = path[-2]
    gp = state[:nodes][-2]

    terms.each do |term|
      terrs = []
      validate(point, clone(term), { 'meta' => state[:meta] }.merge(select_extras), terrs)
      if terrs.empty?
        setprop(gp, gkey, point) if gp && !gkey.nil?
        return nil
      end
    end

    state[:errs].push(
      'OR:' + pathify(ppath) + SELECT_VIZ + stringify(point) + ' fail:' + stringify(terms)
    )
    nil
  end

  def self.select_not(state, _fn, current, ref, store)
    return nil unless state[:mode] == S_MKEYPRE

    term = getprop(state[:parent], state[:key])

    path = state[:path] || []
    ppath = path.length >= 2 ? path[0...-1] : [S_DTOP]
    point = getpath(ppath, store)

    terrs = []
    validate(point, clone(term), { 'meta' => state[:meta] }.merge(select_extras), terrs)

    if terrs.empty?
      state[:errs].push(
        'NOT:' + pathify(ppath) + SELECT_VIZ + stringify(point) + ' fail:' + stringify(term)
      )
    end

    gkey = path[-2]
    gp = state[:nodes][-2]
    setprop(gp, gkey, point) if gp && !gkey.nil?
    nil
  end

  def self.select_cmp(state, _fn, current, ref, store)
    return nil unless state[:mode] == S_MKEYPRE

    term = getprop(state[:parent], state[:key])

    path = state[:path] || []
    ppath = path.length >= 2 ? path[0...-1] : [S_DTOP]
    point = getpath(ppath, store)

    op = ref.to_s[/\$([A-Z]+)/, 1]
    pass = case op
           when 'GT' then point > term
           when 'LT' then point < term
           when 'GTE' then point >= term
           when 'LTE' then point <= term
           when 'LIKE'
             begin
               ::Regexp.new(term.to_s).match?(stringify(point))
             rescue RegexpError
               false
             end
           else
             false
           end

    gkey = path[-2]
    gp = state[:nodes][-2]

    if pass
      setprop(gp, gkey, point) if gp && !gkey.nil?
    else
      ref_disp = op ? "$#{op}" : ref.to_s
      state[:errs].push(
        'CMP: ' + pathify(ppath) + SELECT_VIZ + stringify(point) +
          ' fail:' + ref_disp + ' ' + stringify(term)
      )
    end
    nil
  end

  # Validate a data structure against a shape specification.
  def self.validate(data, spec, extra = nil, collecterrs = nil)
    errs = collecterrs.nil? ? [] : collecterrs

    # TS validate() passes an "inj" object as the 3rd argument.
    # That "inj" can include `meta`, which must not be merged into the
    # validated source data. Instead we inject it into the injection state.
    inj_meta = nil
    extra_hash = extra.is_a?(Hash) ? clone(extra) : nil
    if extra_hash && (extra_hash.key?('meta') || extra_hash.key?(:meta))
      inj_meta = extra_hash['meta'] || extra_hash[:meta]
      extra_hash.delete('meta')
      extra_hash.delete(:meta)
    end

    store = {
      # Remove the transform commands.
      '$DELETE' => nil,
      '$COPY' => nil,
      '$KEY' => nil,
      '$META' => nil,
      '$MERGE' => nil,
      '$EACH' => nil,
      '$PACK' => nil,

      '$STRING' => method(:validate_string),
      '$NUMBER' => method(:validate_number),
      '$INTEGER' => method(:validate_type),
      '$DECIMAL' => method(:validate_type),
      '$INSTANCE' => method(:validate_type),
      '$BOOLEAN' => method(:validate_boolean),
      '$OBJECT' => method(:validate_object),
      '$ARRAY' => method(:validate_array),
      '$MAP' => method(:validate_type),
      '$LIST' => method(:validate_type),
      '$NULL' => method(:validate_type),
      '$NIL' => method(:validate_type),
      '$FUNCTION' => method(:validate_function),
      '$ANY' => method(:validate_any),
      '$CHILD' => method(:validate_child),
      '$ONE' => method(:validate_one),
      '$EXACT' => method(:validate_exact),

      # Keep any custom validators (keys starting with `$`) and friends.
      **(extra_hash || {}),

      # Injection meta used by special validation test cases.
      '$INJ_META' => inj_meta,

      # A special top level value to collect errors.
      # NOTE: collecterrs parameter always wins.
      '$ERRS' => errs
    }

    out = transform(data, spec, store, method(:_validation))

    generr = !errs.empty? && collecterrs.nil?
    raise "Invalid data: #{errs.join(' | ')}" if generr

    out
  end

  # Transform commands.
  def self.transform_cmds(state, val, current, ref, store)
    out = val
    if ismap(val)
      out = {}
      val.each do |k, v|
        if k.start_with?(S_DS)
          out[k] = v
        else
          out[k] = transform_cmds(state, v, current, ref, store)
        end
      end
    elsif islist(val)
      out = val.map { |v| transform_cmds(state, v, current, ref, store) }
    end
    out
  end

end
