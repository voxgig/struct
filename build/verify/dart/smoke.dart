// Universal struct smoke: getpath({ db: { host: "localhost" } }, "db.host").
import 'package:voxgig_struct/voxgig_struct.dart';

void main() {
  final got = getpath({
    'db': {'host': 'localhost'}
  }, 'db.host');
  if (got == 'localhost') {
    print('OK dart: getpath(db.host) = localhost');
    return;
  }
  throw StateError('FAIL dart: getpath(db.host) = $got (want localhost)');
}
