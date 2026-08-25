# frozen_string_literal: true

# The shared test runner comes from voxgig/omni, consumed as a local
# checkout - omni has no gem (the two Node ports are on npm; this one is
# not). The
# checkout is resolved the same way voxgig/sekreto's ports resolve it:
# $OMNI_HOME first, then sibling paths, taking the first directory that
# carries spec/fib.json. Set OMNI_HOME if yours lives elsewhere.
# Only the tests depend on omni; the library never does.
#
# This file is the Ruby counterpart of javascript/test/omni.js and
# python/tests/omni.py. It presents omni's struct compat shim under
# struct's own `VoxgigRunner` namespace, so the test files change by one
# require line and nothing else.

def omnihome
  here = File.dirname(File.expand_path(__FILE__))
  cands = [
    ENV.fetch('OMNI_HOME', nil),
    File.join(here, '..', '..', 'omni'),
    File.join(here, '..', '..', '..', 'omni'),
    '/workspace/omni',
    '/home/user/omni'
  ]

  cands.each do |cand|
    return File.expand_path(cand) if cand && File.exist?(File.join(cand, 'spec', 'fib.json'))
  end

  raise 'struct: voxgig/omni checkout not found - set OMNI_HOME'
end

$LOAD_PATH.unshift(File.join(omnihome, 'ruby', 'lib'))

require 'voxgig_omni/compat/struct'

# struct's runner namespace, backed by omni. `include` brings the
# sentinels (NULLMARK, UNDEFMARK, EXISTSMARK) in as constants; `extend`
# makes make_runner and null_modifier module methods, which is how
# struct's test files call them.
module VoxgigRunner
  include VoxgigOmni::Compat::Struct
  extend VoxgigOmni::Compat::Struct
end
