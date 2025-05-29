#!/usr/bin/env python3

import sys
sys.path.insert(0, '.')
from voxgig_struct.voxgig_struct import transform
import json

# Test $COPY transform
data = {'a': 1}
spec = {'a': '`$COPY`'}  # This should copy the value from data.a

print('Input data:', data)
print('Input spec:', spec)

result = transform(data, spec)
print('Result:', json.dumps(result, indent=2)) 