const s = require('@voxgig/struct')

const store = { db: { host: 'localhost' } }
const got = s.getpath(store, 'db.host')

if (got === 'localhost') {
  console.log('OK typescript: getpath(db.host) = localhost')
  process.exit(0)
}

console.log(`FAIL typescript: getpath(db.host) = ${got} (want localhost)`)
process.exit(1)
