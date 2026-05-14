# RUN: python -m unittest discover -s tests
# RUN-SOME: python -m unittest discover -s tests -k getpath

import unittest

try:
    from .runner import (
        NULLMARK,
        makeRunner,
        nullModifier,
    )
    from .sdk import SDK
except ImportError:
    from runner import (
        NULLMARK,
        makeRunner,
        nullModifier,
    )
    from sdk import SDK

from voxgig_struct.voxgig_struct import (
    T_function,
    T_noval,
    T_null,
    T_scalar,
)

sdk_client = SDK.test()
runner = makeRunner('../../build/test/test.json', sdk_client)
runparts = runner('struct')

spec = runparts['spec']
runset = runparts['runset']
runsetflags = runparts['runsetflags']
client = runparts['client']

# Get all the struct utilities from the client
struct_utils = client.utility().struct
clone = struct_utils.clone
delprop = struct_utils.delprop
escre = struct_utils.escre
escurl = struct_utils.escurl
filter_fn = struct_utils.filter
flatten = struct_utils.flatten
getelem = struct_utils.getelem
getpath = struct_utils.getpath
getprop = struct_utils.getprop
haskey = struct_utils.haskey
inject = struct_utils.inject
isempty = struct_utils.isempty
isfunc = struct_utils.isfunc
iskey = struct_utils.iskey
islist = struct_utils.islist
ismap = struct_utils.ismap
isnode = struct_utils.isnode
items = struct_utils.items
jm = struct_utils.jm
jt = struct_utils.jt
joinurl = struct_utils.joinurl
jsonify = struct_utils.jsonify
keysof = struct_utils.keysof
merge = struct_utils.merge
pad = struct_utils.pad
pathify = struct_utils.pathify
select = struct_utils.select
setpath = struct_utils.setpath
setprop = struct_utils.setprop
DELETE = struct_utils.DELETE
size = struct_utils.size
slice = struct_utils.slice
stringify = struct_utils.stringify
strkey = struct_utils.strkey
transform = struct_utils.transform
typename = struct_utils.typename
typify = struct_utils.typify
validate = struct_utils.validate
walk = struct_utils.walk

minorSpec = spec['minor']
walkSpec = spec['walk']
mergeSpec = spec['merge']
getpathSpec = spec['getpath']
injectSpec = spec['inject']
transformSpec = spec['transform']
validateSpec = spec['validate']
selectSpec = spec['select']


class TestStruct(unittest.TestCase):
    # minor tests
    # ===========

    def test_exists(self):
        self.assertTrue(callable(clone))
        self.assertTrue(callable(escre))
        self.assertTrue(callable(escurl))
        self.assertTrue(callable(getprop))
        self.assertTrue(callable(getpath))

        self.assertTrue(callable(haskey))
        self.assertTrue(callable(inject))
        self.assertTrue(callable(isempty))
        self.assertTrue(callable(isfunc))
        self.assertTrue(callable(iskey))

        self.assertTrue(callable(islist))
        self.assertTrue(callable(ismap))
        self.assertTrue(callable(isnode))
        self.assertTrue(callable(items))
        self.assertTrue(callable(joinurl))

        self.assertTrue(callable(keysof))
        self.assertTrue(callable(merge))
        self.assertTrue(callable(pathify))
        self.assertTrue(callable(setprop))
        self.assertTrue(callable(strkey))

        self.assertTrue(callable(stringify))
        self.assertTrue(callable(transform))
        self.assertTrue(callable(typify))
        self.assertTrue(callable(validate))
        self.assertTrue(callable(walk))

    def test_minor_isnode(self):
        runset(minorSpec['isnode'], isnode)

    def test_minor_ismap(self):
        runset(minorSpec['ismap'], ismap)

    def test_minor_islist(self):
        runset(minorSpec['islist'], islist)

    def test_minor_iskey(self):
        runsetflags(minorSpec['iskey'], {'null': False}, iskey)

    def test_minor_strkey(self):
        runsetflags(minorSpec['strkey'], {'null': False}, strkey)

    def test_minor_isempty(self):
        runsetflags(minorSpec['isempty'], {'null': False}, isempty)

    def test_minor_isfunc(self):
        runset(minorSpec['isfunc'], isfunc)

        def f0():
            return None

        self.assertTrue(isfunc(f0))
        self.assertTrue(isfunc(lambda: None))

    def test_minor_clone(self):
        runsetflags(minorSpec['clone'], {'null': False}, clone)

        def f0():
            return None

        self.assertEqual({'a': f0}, clone({'a': f0}))

    def test_minor_escre(self):
        runset(minorSpec['escre'], escre)

    def test_minor_escurl(self):
        runset(minorSpec['escurl'], escurl)

    def test_minor_stringify(self):
        runset(
            minorSpec['stringify'],
            lambda vin: stringify(
                'null' if vin.get('val') == NULLMARK else vin.get('val'), vin.get('max')
            ),
        )

    def test_minor_jsonify(self):
        runsetflags(
            minorSpec['jsonify'],
            {'null': False},
            lambda vin: jsonify(vin.get('val'), vin.get('flags')),
        )

    def test_minor_getelem(self):
        def getelem_wrapper(vin):
            if vin.get('alt') is None:
                return getelem(vin.get('val'), vin.get('key'))
            else:
                return getelem(vin.get('val'), vin.get('key'), vin.get('alt'))

        runsetflags(minorSpec['getelem'], {'null': False}, getelem_wrapper)

    def test_minor_delprop(self):
        def delprop_wrapper(vin):
            return delprop(vin.get('parent'), vin.get('key'))

        runset(minorSpec['delprop'], delprop_wrapper)

    def test_minor_edge_clone(self):
        x = {'y': 1}
        xc = clone(x)
        self.assertEqual(x, xc)
        self.assertIsNot(x, xc)

    def test_minor_edge_items(self):
        a0 = [11, 22, 33]
        self.assertEqual(items(a0), [['0', 11], ['1', 22], ['2', 33]])

    def test_minor_edge_getelem(self):
        self.assertEqual(getelem([], 1, lambda: 2), 2)

    def test_minor_edge_jsonify(self):
        self.assertEqual(jsonify(lambda: 1), 'null')

    def test_minor_edge_keysof(self):
        a0 = [11, 22, 33]
        self.assertEqual(keysof(a0), ['0', '1', '2'])

    def test_minor_edge_stringify(self):
        a = {}
        a['a'] = a
        self.assertEqual(stringify(a), '__STRINGIFY_FAILED__')

        self.assertEqual(
            stringify({'a': [9]}, -1, True),
            '\x1b[38;5;81m\x1b[38;5;118m{\x1b[38;5;118ma\x1b[38;5;118m:'
            '\x1b[38;5;213m[\x1b[38;5;213m9\x1b[38;5;213m]\x1b[38;5;118m}\x1b[0m',
        )

    def test_minor_edge_delprop(self):
        # String array tests
        strarr0 = ['a', 'b', 'c', 'd', 'e']
        strarr1 = ['a', 'b', 'c', 'd', 'e']
        self.assertEqual(delprop(strarr0, 2), ['a', 'b', 'd', 'e'])
        self.assertEqual(delprop(strarr1, '2'), ['a', 'b', 'd', 'e'])

        # Integer array tests
        intarr0 = [2, 3, 5, 7, 11]
        intarr1 = [2, 3, 5, 7, 11]
        self.assertEqual(delprop(intarr0, 2), [2, 3, 7, 11])
        self.assertEqual(delprop(intarr1, '2'), [2, 3, 7, 11])

    def test_minor_size(self):
        runsetflags(minorSpec['size'], {'null': False}, size)

    def test_minor_slice(self):
        def slice_wrapper(vin):
            return slice(vin.get('val'), vin.get('start'), vin.get('end'))

        runsetflags(minorSpec['slice'], {'null': False}, slice_wrapper)

    def test_minor_pad(self):
        def pad_wrapper(vin):
            return pad(vin.get('val'), vin.get('pad'), vin.get('char'))

        runsetflags(minorSpec['pad'], {'null': False}, pad_wrapper)

    def test_minor_pathify(self):
        def pathify_wrapper(vin=None):
            path = vin.get('path')
            path = None if path == NULLMARK else path
            pathstr = pathify(path, vin.get('from')).replace('__NULL__.', '')
            pathstr = pathstr.replace('>', ':null>') if vin.get('path') == NULLMARK else pathstr
            return pathstr

        runsetflags(minorSpec['pathify'], {'null': True}, pathify_wrapper)

    def test_minor_items(self):
        runset(minorSpec['items'], items)

    def test_minor_getprop(self):
        def getprop_wrapper(vin):
            if vin.get('alt') is None:
                return getprop(vin.get('val'), vin.get('key'))
            else:
                return getprop(vin.get('val'), vin.get('key'), vin.get('alt'))

        runsetflags(minorSpec['getprop'], {'null': False}, getprop_wrapper)

    def test_minor_edge_getprop(self):
        # String array tests
        strarr = ['a', 'b', 'c', 'd', 'e']
        self.assertEqual(getprop(strarr, 2), 'c')
        self.assertEqual(getprop(strarr, '2'), 'c')

        # Integer array tests
        intarr = [2, 3, 5, 7, 11]
        self.assertEqual(getprop(intarr, 2), 5)
        self.assertEqual(getprop(intarr, '2'), 5)

    def test_minor_setprop(self):
        runset(
            minorSpec['setprop'],
            lambda vin: setprop(vin.get('parent'), vin.get('key'), vin.get('val')),
        )

    def test_minor_edge_setprop(self):
        # String array tests
        strarr0 = ['a', 'b', 'c', 'd', 'e']
        strarr1 = ['a', 'b', 'c', 'd', 'e']
        self.assertEqual(setprop(strarr0, 2, 'C'), ['a', 'b', 'C', 'd', 'e'])
        self.assertEqual(setprop(strarr1, '2', 'CC'), ['a', 'b', 'CC', 'd', 'e'])

        # Integer array tests
        intarr0 = [2, 3, 5, 7, 11]
        intarr1 = [2, 3, 5, 7, 11]
        self.assertEqual(setprop(intarr0, 2, 55), [2, 3, 55, 7, 11])
        self.assertEqual(setprop(intarr1, '2', 555), [2, 3, 555, 7, 11])

    def test_minor_haskey(self):
        runsetflags(
            minorSpec['haskey'], {'null': False}, lambda vin: haskey(vin.get('src'), vin.get('key'))
        )

    def test_minor_keysof(self):
        runset(minorSpec['keysof'], keysof)

    def test_minor_joinurl(self):
        from voxgig_struct.voxgig_struct import join as struct_join

        runsetflags(
            minorSpec['join'],
            {'null': False},
            lambda vin: struct_join(vin.get('val'), vin.get('sep'), vin.get('url')),
        )

    def test_minor_typify(self):
        runsetflags(minorSpec['typify'], {'null': False}, typify)

    def test_minor_edge_typify(self):
        self.assertEqual(typify(), T_noval)
        self.assertEqual(typify(None), T_scalar | T_null)
        self.assertEqual(typify(float('nan')), T_noval)
        self.assertEqual(typify(lambda: None), T_scalar | T_function)

    def test_minor_setpath(self):
        runsetflags(
            minorSpec['setpath'],
            {'null': False},
            lambda vin: setpath(vin.get('store'), vin.get('path'), vin.get('val')),
        )

    def test_minor_edge_setpath(self):
        x = {'y': {'z': 1, 'q': 2}}
        self.assertEqual(setpath(x, 'y.q', DELETE), {'z': 1})
        self.assertEqual(x, {'y': {'z': 1}})

    def test_minor_filter(self):
        checkmap = {
            'gt3': lambda n: n[1] > 3,
            'lt3': lambda n: n[1] < 3,
        }
        runset(
            minorSpec['filter'], lambda vin: filter_fn(vin.get('val'), checkmap[vin.get('check')])
        )

    def test_minor_typename(self):
        runset(minorSpec['typename'], typename)

    def test_minor_flatten(self):
        runset(minorSpec['flatten'], lambda vin: flatten(vin.get('val'), vin.get('depth')))

    # walk tests
    # ==========

    def test_walk_log(self):
        test_data = clone(walkSpec['log'])

        log = []

        def walklog(key, val, parent, path):
            log.append(
                'k='
                + stringify(key)
                + ', v='
                + stringify(val)
                + ', p='
                + stringify(parent)
                + ', t='
                + pathify(path)
            )
            return val

        # Test after callback (Python walk only supports after, not before)
        # TODO: Python walk() needs to be updated to support before/after callbacks like TypeScript
        walk(test_data['in'], walklog)
        self.assertEqual(log, test_data['out']['after'])

    def test_walk_basic(self):
        def walkpath(_key, val, _parent, path):
            if isinstance(val, str):
                return val + '~' + '.'.join(str(p) for p in path)
            return val

        def walk_wrapper(vin=None):
            return walk(vin, walkpath)

        runset(walkSpec['basic'], walk_wrapper)

    def test_walk_copy(self):
        cur = [None]

        def walkcopy(key, val, _parent, path):
            if key is None:
                cur[0] = [None]
                cur[0][0] = {} if ismap(val) else [] if islist(val) else val
                return val

            v = val
            i = size(path)

            if isnode(v):
                while len(cur[0]) <= i:
                    cur[0].append(None)
                v = cur[0][i] = {} if ismap(v) else []

            setprop(cur[0][i - 1], key, v)

            return val

        def walk_copy_wrapper(vin=None):
            walk(vin, before=walkcopy)
            return cur[0][0]

        runset(walkSpec['copy'], walk_copy_wrapper)

    def test_walk_depth(self):
        def walk_depth_wrapper(vin):
            state = {'top': None, 'cur': None}

            def copy(key, val, _parent, _path):
                if key is None or isnode(val):
                    child = [] if islist(val) else {}
                    if key is None:
                        state['top'] = state['cur'] = child
                    else:
                        state['cur'][key] = child
                        state['cur'] = child
                else:
                    state['cur'][key] = val
                return val

            walk(vin.get('src'), before=copy, maxdepth=vin.get('maxdepth'))
            return state['top']

        runsetflags(walkSpec['depth'], {'null': False}, walk_depth_wrapper)

    # merge tests
    # ===========

    def test_merge_basic(self):
        test_data = clone(spec['merge']['basic'])
        self.assertEqual(merge(test_data['in']), test_data['out'])

    def test_merge_cases(self):
        runset(spec['merge']['cases'], merge)

    def test_merge_array(self):
        runset(spec['merge']['array'], merge)

    def test_merge_integrity(self):
        runset(spec['merge']['integrity'], merge)

    def test_merge_depth(self):
        runset(spec['merge']['depth'], lambda vin: merge(vin.get('val'), vin.get('depth')))

    def test_merge_special(self):
        def f0():
            return None

        self.assertEqual(merge([f0]), f0)
        self.assertEqual(merge([None, f0]), f0)
        self.assertEqual(merge([{'a': f0}]), {'a': f0})
        self.assertEqual(merge([[f0]]), [f0])
        self.assertEqual(merge([{'a': {'b': f0}}]), {'a': {'b': f0}})

    # -------------------------------------------------
    # getpath tests
    # -------------------------------------------------

    def test_getpath_basic(self):
        def getpath_wrapper(vin):
            return getpath(vin.get('store'), vin.get('path'))

        runset(spec['getpath']['basic'], getpath_wrapper)

    def test_getpath_relative(self):
        def getpath_wrapper(vin):
            dpath = vin.get('dpath')
            if dpath:
                dpath = dpath.split('.')
            injdef = {'dparent': vin.get('dparent'), 'dpath': dpath}
            return getpath(vin.get('store'), vin.get('path'), injdef)

        runset(spec['getpath']['relative'], getpath_wrapper)

    def test_getpath_special(self):
        def getpath_wrapper(vin):
            return getpath(vin.get('store'), vin.get('path'), vin.get('inj'))

        runset(spec['getpath']['special'], getpath_wrapper)

    def test_getpath_handler(self):
        def getpath_wrapper(vin):
            def handler(inj, val, ref, store):
                return val() if callable(val) else val

            return getpath(
                {'$TOP': vin.get('store'), '$FOO': lambda: 'foo'},
                vin.get('path'),
                {'handler': handler},
            )

        runset(spec['getpath']['handler'], getpath_wrapper)

    # TODO: Add test data for getpath current and state sections
    # def test_getpath_current(self):
    #     def getpath_wrapper(vin):
    #         return getpath(vin["path"], vin.get("store"), vin.get("current"))
    #     runset(spec["getpath"]["current"], getpath_wrapper)

    # def test_getpath_state(self):
    #     def handler_fn(state, val, _current=None, _ref=None, _store=None):
    #         out = f"{state.meta['step']}:{val}"
    #         state.meta["step"] = state.meta["step"]+1
    #         return out

    #     state = Injection(
    #             meta = {"step":0},
    #             handler = handler_fn,
    #             mode = "val",
    #             full = False,
    #             keyI = 0,
    #             keys = ["$TOP"],
    #             key = "$TOP",
    #             val = "",
    #             parent = {},
    #             path = ["$TOP"],
    #             nodes = [{}],
    #             base = "$TOP",
    #             errs = [],
    #         )

    #     runset(spec["getpath"]["state"],
    #            lambda vin: getpath(vin.get("path"), vin.get("store"), vin.get("current"), state))

    # -------------------------------------------------
    # inject tests
    # -------------------------------------------------

    def test_inject_basic(self):
        test_data = clone(spec['inject']['basic'])
        self.assertEqual(inject(test_data['in']['val'], test_data['in']['store']), test_data['out'])

    def test_inject_string(self):
        def inject_wrapper(vin):
            return inject(
                vin.get('val'),
                vin.get('store'),
                {'modify': nullModifier, 'extra': vin.get('current')},
            )

        runset(spec['inject']['string'], inject_wrapper)

    def test_inject_deep(self):
        runset(spec['inject']['deep'], lambda vin: inject(vin.get('val'), vin.get('store')))

    # -------------------------------------------------
    # transform tests
    # Inputs and expected outputs: build/test/transform.jsonic
    # -------------------------------------------------

    def test_transform_basic(self):
        test_data = clone(spec['transform']['basic'])
        test_data_in = test_data.get('in')
        self.assertEqual(
            transform(
                test_data_in.get('data'), test_data_in.get('spec'), test_data_in.get('store')
            ),
            test_data['out'],
        )

    def test_transform_paths(self):
        def transform_wrapper(vin):
            return transform(vin.get('data'), vin.get('spec'), vin.get('store'))

        runset(spec['transform']['paths'], transform_wrapper)

    def test_transform_cmds(self):
        def transform_wrapper(vin):
            return transform(vin.get('data'), vin.get('spec'), vin.get('store'))

        runset(spec['transform']['cmds'], transform_wrapper)

    def test_transform_each(self):
        def transform_wrapper(vin):
            return transform(vin.get('data'), vin.get('spec'), vin.get('store'))

        runset(spec['transform']['each'], transform_wrapper)

    def test_transform_pack(self):
        def transform_wrapper(vin):
            return transform(vin.get('data'), vin.get('spec'), vin.get('store'))

        runset(spec['transform']['pack'], transform_wrapper)

    def test_transform_ref(self):
        def transform_wrapper(vin):
            return transform(vin.get('data'), vin.get('spec'), vin.get('store'))

        runset(spec['transform']['ref'], transform_wrapper)

    def test_transform_modify(self):
        def modifier(val, key, parent, inj):
            if key is not None and parent is not None and isinstance(val, str):
                parent[key] = '@' + val

        runset(
            spec['transform']['modify'],
            lambda vin: transform(
                vin.get('data'), vin.get('spec'), {'modify': modifier, 'extra': vin.get('store')}
            ),
        )

    def test_transform_extra(self):
        def upper_func(state, val, current, ref, store):
            path = state.path
            this_key = path[-1] if path else None
            return str(this_key).upper()

        self.assertEqual(
            transform(
                {'a': 1},
                {'x': '`a`', 'b': '`$COPY`', 'c': '`$UPPER`'},
                {'extra': {'b': 2, '$UPPER': upper_func}},
            ),
            {'x': 1, 'b': 2, 'c': 'C'},
        )

    def test_transform_format(self):
        def transform_wrapper(vin):
            return transform(vin.get('data'), vin.get('spec'))

        runsetflags(spec['transform']['format'], {'null': False}, transform_wrapper)

    def test_transform_apply(self):
        def transform_wrapper(vin):
            return transform(vin.get('data'), vin.get('spec'))

        runset(spec['transform']['apply'], transform_wrapper)

    def test_transform_edge_apply(self):
        self.assertEqual(2, transform({}, ['`$APPLY`', lambda v: 1 + v, 1]))

    def test_transform_funcval(self):
        def f0():
            return 99

        self.assertEqual(transform({}, {'x': 1}), {'x': 1})
        self.assertEqual(transform({}, {'x': f0}), {'x': f0})
        self.assertEqual(transform({'a': 1}, {'x': '`a`'}), {'x': 1})
        self.assertEqual(transform({'f0': f0}, {'x': '`f0`'}), {'x': f0})

    # -------------------------------------------------
    # validate tests
    # -------------------------------------------------

    def test_validate_basic(self):
        def validate_wrapper(vin):
            return validate(vin.get('data'), vin.get('spec'))

        runsetflags(spec['validate']['basic'], {'null': False}, validate_wrapper)

    def test_validate_child(self):
        def validate_wrapper(vin):
            return validate(vin.get('data'), vin.get('spec'))

        runset(spec['validate']['child'], validate_wrapper)

    def test_validate_one(self):
        def validate_wrapper(vin):
            return validate(vin.get('data'), vin.get('spec'))

        runset(spec['validate']['one'], validate_wrapper)

    def test_validate_exact(self):
        def validate_wrapper(vin):
            return validate(vin.get('data'), vin.get('spec'))

        runset(spec['validate']['exact'], validate_wrapper)

    def test_validate_invalid(self):
        runsetflags(
            spec['validate']['invalid'],
            {'null': False},
            lambda vin: validate(vin.get('data'), vin.get('spec')),
        )

    def test_validate_special(self):
        def validate_wrapper(vin):
            return validate(vin.get('data'), vin.get('spec'), vin.get('inj'))

        runset(spec['validate']['special'], validate_wrapper)

    def test_validate_custom(self):
        errs = []

        def integer_check(state, _val, current, _ref, _store):
            key = state.key
            out = getprop(current, key)

            if not isinstance(out, int) and not (isinstance(out, float) and out.is_integer()):
                state.errs.append(f'Not an integer at {".".join(state.path[1:])}: {out}')
                return None

            return out

        extra = {'$INTEGER': integer_check}

        shape = {'a': '`$INTEGER`'}

        # Test with valid integer
        out = validate({'a': 1}, shape, {'extra': extra, 'errs': errs})
        self.assertEqual(out, {'a': 1})
        self.assertEqual(len(errs), 0)

        # Test with invalid value
        out = validate({'a': 'A'}, shape, {'extra': extra, 'errs': errs})
        self.assertEqual(out, {'a': 'A'})
        self.assertEqual(errs, ['Not an integer at a: A'])

    def test_validate_edge(self):
        errs = []
        validate({'x': 1}, {'x': '`$INSTANCE`'}, {'errs': errs})
        self.assertEqual(errs[0], 'Expected field x to be instance, but found integer: 1.')

        errs = []
        validate({'x': {}}, {'x': '`$INSTANCE`'}, {'errs': errs})
        self.assertEqual(errs[0], 'Expected field x to be instance, but found map: {}.')

        errs = []
        validate({'x': []}, {'x': '`$INSTANCE`'}, {'errs': errs})
        self.assertEqual(errs[0], 'Expected field x to be instance, but found list: [].')

    # -------------------------------------------------
    # select tests
    # -------------------------------------------------

    def test_select_basic(self):
        def select_wrapper(vin):
            return select(vin.get('obj'), vin.get('query'))

        runset(selectSpec['basic'], select_wrapper)

    def test_select_operators(self):
        def select_wrapper(vin):
            return select(vin.get('obj'), vin.get('query'))

        runset(selectSpec['operators'], select_wrapper)

    def test_select_edge(self):
        def select_wrapper(vin):
            return select(vin.get('obj'), vin.get('query'))

        runset(selectSpec['edge'], select_wrapper)

    def test_select_alts(self):
        def select_wrapper(vin):
            return select(vin.get('obj'), vin.get('query'))

        runset(selectSpec['alts'], select_wrapper)

    # -------------------------------------------------
    # JSON Builder tests
    # -------------------------------------------------

    def test_json_builder(self):
        self.assertEqual(jsonify(jm('a', 1)), '{\n  "a": 1\n}')

        self.assertEqual(jsonify(jt('b', 2)), '[\n  "b",\n  2\n]')

        self.assertEqual(
            jsonify(jm('c', 'C', 'd', jm('x', True), 'e', jt(None, False))),
            '{\n  "c": "C",\n  "d": {\n    "x": true\n  },\n  "e": [\n    null,\n    false\n  ]\n}',
        )

        self.assertEqual(
            jsonify(
                jt(
                    3.3,
                    jm('f', True, 'g', False, 'h', None, 'i', jt('y', 0), 'j', jm('z', -1), 'k'),
                )
            ),
            '[\n  3.3,\n  {\n    "f": true,\n    "g": false,\n    "h": null,\n    "i": [\n      "y",\n      0\n    ],\n    "j": {\n      "z": -1\n    },\n    "k": null\n  }\n]',
        )

        self.assertEqual(
            jsonify(jm(True, 1, False, 2, None, 3, ['a'], 4, {'b': 0}, 5)),
            '{\n  "true": 1,\n  "false": 2,\n  "null": 3,\n  "[a]": 4,\n  "{b:0}": 5\n}',
        )

    # -------------------------------------------------
    # Group A conformance — null and absent unified.
    # -------------------------------------------------

    def test_sentinels_getprop_unify(self):
        runsetflags(
            spec['sentinels']['getprop_unify'],
            {'null': False},
            lambda vin: getprop(vin.get('val'), vin.get('key'), vin.get('alt')),
        )

    def test_sentinels_getelem_absent(self):
        runsetflags(
            spec['sentinels']['getelem_absent'],
            {'null': False},
            lambda vin: getelem(vin.get('val'), vin.get('key'), vin.get('alt')),
        )

    def test_sentinels_haskey_unify(self):
        runsetflags(
            spec['sentinels']['haskey_unify'],
            {'null': False},
            lambda vin: haskey(vin.get('val'), vin.get('key')),
        )

    def test_sentinels_isempty_unify(self):
        runsetflags(spec['sentinels']['isempty_unify'], {'null': False}, isempty)

    def test_sentinels_isnode_unify(self):
        runsetflags(spec['sentinels']['isnode_unify'], {'null': False}, isnode)

    def test_sentinels_stringify_null(self):
        # Python conflates None=absent=null at the value level, so the
        # corpus null entry would arrive as None — same as a missing key.
        # Run with the runner's default null substitution and convert the
        # marker back to the literal string 'null' so stringify can render
        # it the same way TS/JS do for actual null.
        from tests.runner import NULLMARK

        runset(
            spec['sentinels']['stringify_null'],
            lambda vin: stringify('null' if vin == NULLMARK else vin),
        )


# If you want to run this file directly, add:
if __name__ == '__main__':
    unittest.main()
