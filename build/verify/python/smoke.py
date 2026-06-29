from voxgig_struct import getpath

store = {'db': {'host': 'localhost'}}
got = getpath(store, 'db.host')

if got == 'localhost':
    print('OK python: getpath(db.host) = localhost')
    raise SystemExit(0)

print(f'FAIL python: getpath(db.host) = {got!r} (want localhost)')
raise SystemExit(1)
