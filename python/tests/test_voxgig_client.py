# RUN: python -m unittest discover -s tests
# RUN-SOME: python -m unittest discover -s tests -k check

import unittest

from runner import (
    makeRunner,
)
from sdk import SDK

# Create a runner for client testing
sdk_client = SDK.test()
runner = makeRunner('../../build/test/test.json', sdk_client)
runparts = runner('check')

spec = runparts['spec']
runset = runparts['runset']
subject = runparts['subject']


class TestClient(unittest.TestCase):
    def test_client_check_basic(self):
        runset(spec['basic'], subject)


# If you want to run this file directly, add:
if __name__ == '__main__':
    unittest.main()
