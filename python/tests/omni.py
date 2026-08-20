# The shared test runner comes from voxgig/omni, consumed as a local
# checkout - omni is deliberately not published to a package registry
# (yet). The checkout is resolved the same way voxgig/sekreto's ports
# resolve it: $OMNI_HOME first, then sibling paths, taking the first
# directory that carries spec/fib.json. Set OMNI_HOME if yours lives
# elsewhere. Only the tests depend on omni; the library never does.

import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))


def omnihome():
    candidates = []

    if os.environ.get('OMNI_HOME'):
        candidates.append(os.path.abspath(os.environ['OMNI_HOME']))

    candidates.extend(
        [
            os.path.join(_HERE, '..', '..', '..', 'omni'),
            os.path.join(_HERE, '..', '..', '..', '..', 'omni'),
            '/workspace/omni',
            '/home/user/omni',
        ]
    )

    for candidate in candidates:
        if os.path.exists(os.path.join(candidate, 'spec', 'fib.json')):
            return os.path.abspath(candidate)

    raise FileNotFoundError('struct: voxgig/omni checkout not found - set OMNI_HOME')


sys.path.insert(0, os.path.join(omnihome(), 'python'))

from voxgig_omni.compat.struct import (  # noqa: E402
    EXISTSMARK,
    NULLMARK,
    UNDEFMARK,
    makeRunner,
    nullModifier,
    structprovider,
)

__all__ = [
    'EXISTSMARK',
    'NULLMARK',
    'UNDEFMARK',
    'makeRunner',
    'nullModifier',
    'structprovider',
]
