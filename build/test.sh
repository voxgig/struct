#!/bin/bash

SCRIPT_PATH="$0"
while [ -L "$SCRIPT_PATH" ]; do
  SCRIPT_PATH=$(readlink "$SCRIPT_PATH")
done

SCRIPT_DIR=$(cd "$(dirname "$SCRIPT_PATH")" && pwd)

echo
echo "=== TS ==="
cd "$SCRIPT_DIR/../ts" || exit 1
npm test

echo
echo "=== PY ==="
cd "$SCRIPT_DIR/../py" || exit 1
python -m unittest discover -s tests

echo
