const s = require('@voxgig/structjs')

const store = { db: { host: 'localhost' } }
const got = s.getpath(store, 'db.host')

if (got === 'localhost') {
  console.log('OK javascript: getpath(db.host) = localhost')
  process.exit(0)
}

console.log(`FAIL javascript: getpath(db.host) = ${got} (want localhost)`)
process.exit(1)
