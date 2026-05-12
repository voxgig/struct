# Test runner that uses the test model in build/test.

import json
import os
import re
from collections.abc import Callable
from typing import Any, TypedDict

NULLMARK = '__NULL__'  # Value is JSON null
UNDEFMARK = '__UNDEF__'  # Value is not present (thus, undefined)
EXISTSMARK = '__EXISTS__'  # Value exists (not undefined).


class RunPack(TypedDict):
    spec: dict[str, Any]
    runset: Callable
    runsetflags: Callable
    subject: Callable
    client: Any | None


def makeRunner(testfile: str, client: Any):

    def runner(
        name: str,
        store: Any = None,
    ) -> RunPack:
        store = store or {}

        utility = client.utility()
        structUtils = utility.struct

        spec = resolve_spec(name, testfile)
        clients = resolve_clients(client, spec, store, structUtils)
        subject = resolve_subject(name, utility)

        def runsetflags(testspec, flags, testsubject):
            nonlocal subject, clients

            subject = testsubject or subject
            flags = resolve_flags(flags)
            testspecmap = fixJSON(testspec, flags)
            testset = testspecmap['set']

            for entry in testset:
                try:
                    entry = resolve_entry(entry, flags)

                    testpack = resolve_testpack(name, entry, subject, client, clients)
                    args = resolve_args(entry, testpack, utility, structUtils)

                    # Execute the test function
                    res = testpack['subject'](*args)
                    res = fixJSON(res, flags)
                    entry['res'] = res
                    check_result(entry, args, res, structUtils)

                except Exception as err:
                    handle_error(entry, err, structUtils)

        def runset(testspec, testsubject):
            return runsetflags(testspec, {}, testsubject)

        runpack = {
            'spec': spec,
            'runset': runset,
            'runsetflags': runsetflags,
            'subject': subject,
            'client': client,
        }

        return runpack

    return runner


def resolve_spec(name: str, testfile: str) -> dict[str, Any]:
    with open(os.path.join(os.path.dirname(__file__), testfile), encoding='utf-8') as f:
        alltests = json.load(f)

    if 'primary' in alltests and name in alltests['primary']:
        spec = alltests['primary'][name]
    elif name in alltests:
        spec = alltests[name]
    else:
        spec = alltests

    return spec


def resolve_clients(
    client: Any, spec: dict[str, Any], store: Any, structUtils: Any
) -> dict[str, Any]:
    clients = {}
    if 'DEF' in spec and 'client' in spec['DEF']:
        for client_name, client_val in structUtils.items(spec['DEF']['client']):
            # Get client options
            client_opts = client_val.get('test', {}).get('options', {})

            # Apply store injections if needed
            if isinstance(store, dict) and structUtils.inject:
                structUtils.inject(client_opts, store)

            # Create and store the client using the passed client object
            clients[client_name] = client.tester(client_opts)

    return clients


def resolve_subject(name: str, container: Any):
    return getattr(container, name, getattr(container.struct, name, None))


def check_result(entry, args, res, structUtils):
    matched = False

    if 'match' in entry:
        result = {
            'in': entry.get('in'),
            'args': args,
            'out': entry.get('res'),
            'ctx': entry.get('ctx'),
        }
        match(entry['match'], result, structUtils)
        matched = True

    out = entry.get('out')

    if out == res:
        return

    # NOTE: allow match with no out
    if matched and (out == NULLMARK or out is None):
        return

    try:
        cleaned_res = json.loads(json.dumps(res, default=str))
    except:
        # If can't be serialized just use the original
        cleaned_res = res

    # Compare result with expected output using deep equality
    if cleaned_res != out:
        raise AssertionError(
            f'Expected: {out}, got: {cleaned_res}\nTest: {entry.get("name", "unknown")}'
        )


def handle_error(entry, err, structUtils):
    # Record the error in the entry
    entry['thrown'] = err
    entry_err = entry.get('err')

    # If the test expects an error
    if entry_err is not None:
        # If it's any error or matches expected pattern
        if entry_err is True or matchval(entry_err, str(err), structUtils):
            # If we also need to match error details
            if 'match' in entry:
                # err_json = None
                # if None != err:
                # err_json = {"message":str(err)}

                match(
                    entry['match'],
                    {
                        'in': entry.get('in'),
                        'out': entry.get('res'),
                        'ctx': entry.get('ctx'),
                        #'err': err_json
                        'err': fixJSON(err),
                    },
                    structUtils,
                )
            # Error was expected, continue
            return True

        # Expected error didn't match the actual error
        raise AssertionError(f'ERROR MATCH: [{structUtils.stringify(entry_err)}] <=> [{err!s}]')
    # If the test doesn't expect an error
    elif isinstance(err, AssertionError):
        # Propagate assertion errors with added context
        raise AssertionError(f'{err!s}\nTest: {entry.get("name", "unknown")}')
    else:
        # For other errors, include the full error stack
        import traceback

        raise AssertionError(f'{traceback.format_exc()}\nTest: {entry.get("name", "unknown")}')


def resolve_testpack(
    name,
    entry,
    subject,
    client,
    clients,
):
    testpack = {
        'client': client,
        'subject': subject,
        'utility': client.utility(),
    }

    if 'client' in entry:
        testpack['client'] = clients[entry['client']]
        testpack['utility'] = testpack['client'].utility()
        testpack['subject'] = resolve_subject(name, testpack['utility'])

    return testpack


def resolve_args(entry, testpack, utility, structUtils):
    args = []

    if 'ctx' in entry:
        args = [entry['ctx']]
    elif 'args' in entry:
        args = entry['args']
    elif 'in' in entry:
        args = [structUtils.clone(entry['in'])]

    # If we have context or arguments, we might need to patch them
    if ('ctx' in entry or 'args' in entry) and len(args) > 0:
        first = args[0]
        if structUtils.ismap(first):
            # Clone the argument
            first = structUtils.clone(first)
            first = utility.contextify(first)
            args[0] = first
            entry['ctx'] = first
            first.client = testpack['client']
            first.utility = testpack['utility']

    return args


def resolve_flags(flags: dict[str, Any] = None) -> dict[str, bool]:
    if flags is None:
        flags = {}

    flags['null'] = flags.get('null', True)

    return flags


def resolve_entry(entry: dict[str, Any], flags: dict[str, bool]) -> dict[str, Any]:
    # Set default output value for missing 'out' field
    if 'out' not in entry and flags.get('null', True):
        entry['out'] = NULLMARK

    return entry


def fixJSON(obj, flags={}):
    # Handle nulls
    if obj is None:
        return NULLMARK if flags.get('null', True) else None

    # Handle errors
    if isinstance(obj, Exception):
        return {**vars(obj), 'name': type(obj).__name__, 'message': str(obj)}

    # Handle collections recursively
    elif isinstance(obj, list):
        return [fixJSON(item, flags) for item in obj]
    elif isinstance(obj, dict):
        return {k: fixJSON(v, flags) for k, v in obj.items()}

    # Return everything else unchanged
    return obj


def jsonfallback(obj):
    return f'<non-serializable: {type(obj).__name__}>'


def match(check, base, structUtils):
    base = structUtils.clone(base)

    # Use walk function to iterate through the check structure
    def walk_apply(_key, val, _parent, path):
        if not structUtils.isnode(val):
            baseval = structUtils.getpath(base, path)

            if baseval == val:
                return val

            # Explicit undefined expected
            if val == UNDEFMARK and baseval is None:
                return val

            # Explicit defined expected
            if val == EXISTSMARK and baseval is not None:
                return val

            if not matchval(val, baseval, structUtils):
                raise AssertionError(
                    f'MATCH: {".".join(map(str, path))}: '
                    f'[{structUtils.stringify(val)}] <=> [{structUtils.stringify(baseval)}]'
                )
        return val

    # Use walk to apply the check function to each node
    structUtils.walk(check, walk_apply)


def matchval(check, base, structUtils):
    # Handle undefined special case
    if check == '__UNDEF__' or check == NULLMARK:
        check = None

    if check == base:
        return True

    # String-based pattern matching
    if isinstance(check, str):
        # Convert base to string for comparison
        base_str = structUtils.stringify(base)

        # Check for regex pattern with /pattern/ syntax
        regex_match = re.match(r'^/(.+)/$', check)

        if regex_match:
            pattern = regex_match.group(1)
            return re.search(pattern, base_str) is not None
        else:
            # Case-insensitive substring check
            return structUtils.stringify(check).lower() in base_str.lower()

    # Functions automatically pass
    elif callable(check):
        return True

    # No match
    return False


def nullModifier(val, key, parent, _state=None, _current=None, _store=None):
    if val == NULLMARK:
        parent[key] = None
    elif isinstance(val, str):
        parent[key] = val.replace(NULLMARK, 'null')


# Export the necessary components similar to TypeScript
__all__ = [
    'NULLMARK',
    'UNDEFMARK',
    'makeRunner',
    'nullModifier',
]
