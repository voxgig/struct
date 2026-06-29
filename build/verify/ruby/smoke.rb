require 'voxgig_struct'

store = { 'db' => { 'host' => 'localhost' } }
got = VoxgigStruct.getpath(store, 'db.host')

if got == 'localhost'
  puts 'OK ruby: getpath(db.host) = localhost'
  exit 0
end

puts "FAIL ruby: getpath(db.host) = #{got.inspect} (want localhost)"
exit 1
