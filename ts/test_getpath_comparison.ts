#!/usr/bin/env node
/**
 * Comprehensive test script for TypeScript getpath function with detailed logging.
 * This script tests various getpath scenarios and logs detailed information
 * for comparison with the Python version.
 */

import { getpath, getprop, stringify, UNDEF, Injection, S_DTOP, S_DKEY, S_key } from '../src/struct.js'

function logTest(testName: string, store: any, path: string | string[] | null, injdef?: Partial<Injection>, expected?: any): any {
    /** Log detailed information about a getpath test case. */
    console.log('\n' + '='.repeat(60))
    console.log(`TEST: ${testName}`)
    console.log('='.repeat(60))
    
    console.log(`Input store: ${stringify(store)}`)
    console.log(`Input path: ${stringify(path)}`)
    
    if (injdef) {
        console.log('Injection state:')
        console.log(`  mode: ${injdef.mode}`)
        console.log(`  key: ${injdef.key}`)
        console.log(`  path: ${stringify(injdef.path)}`)
        console.log(`  meta: ${stringify(injdef.meta)}`)
        console.log(`  dparent: ${stringify(injdef.dparent)}`)
        console.log(`  dpath: ${stringify(injdef.dpath)}`)
    }
    
    // Call getpath
    const result = getpath(store, path, injdef)
    
    console.log(`Result: ${stringify(result)}`)
    if (expected !== undefined) {
        console.log(`Expected: ${stringify(expected)}`)
        console.log(`Match: ${JSON.stringify(result) === JSON.stringify(expected)}`)
    }
    
    return result
}

function testBasicGetpath(): void {
    /** Test basic getpath functionality. */
    console.log('\n' + '='.repeat(80))
    console.log('BASIC GETPATH TESTS')
    console.log('='.repeat(80))
    
    // Test 1: Simple object access
    const store1 = { '$TOP': { 'a': { 'b': 'value' } } }
    logTest('Simple object access', store1, 'a.b', undefined, { 'b': 'value' })
    
    // Test 2: Array access
    const store2 = { '$TOP': { 'arr': [1, 2, 3, 4, 5] } }
    logTest('Array access', store2, 'arr.2', undefined, 3)
    
    // Test 3: Nested array access
    const store3 = { '$TOP': { 'nested': { 'arr': [{ 'id': 1 }, { 'id': 2 }, { 'id': 3 }] } } }
    logTest('Nested array access', store3, 'nested.arr.1.id', undefined, 2)
    
    // Test 4: Missing path
    const store4 = { '$TOP': { 'a': { 'b': 'value' } } }
    logTest('Missing path', store4, 'a.c', undefined, UNDEF)
    
    // Test 5: Empty path
    const store5 = { '$TOP': { 'a': { 'b': 'value' } } }
    logTest('Empty path', store5, '', undefined, { 'a': { 'b': 'value' } })
}

function testInjectionState(): void {
    /** Test getpath with injection state. */
    console.log('\n' + '='.repeat(80))
    console.log('INJECTION STATE TESTS')
    console.log('='.repeat(80))
    
    // Test 1: With $KEY reference
    const store1 = { '$TOP': { 'a': { 'b': 'value' } } }
    const injdef1: Partial<Injection> = {
        mode: 'val',
        full: false,
        keyI: 0,
        keys: ['test'],
        key: 'test',
        val: { 'b': 'value' },
        parent: { 'test': { 'b': 'value' } },
        path: ['test'],
        nodes: [{ 'test': { 'b': 'value' } }],
        handler: undefined,
        meta: { 'key': 'b' },
        dparent: store1
    }
    logTest('With $KEY reference', store1, '$KEY', injdef1, 'b')
    
    // Test 2: With meta path
    const store2 = { '$TOP': { 'a': { 'b': 'value' } } }
    const injdef2: Partial<Injection> = {
        mode: 'val',
        full: false,
        keyI: 0,
        keys: ['test'],
        key: 'test',
        val: { 'b': 'value' },
        parent: { 'test': { 'b': 'value' } },
        path: ['test'],
        nodes: [{ 'test': { 'b': 'value' } }],
        handler: undefined,
        meta: { 'field': 'a' },
        dparent: store2
    }
    logTest('With meta path', store2, 'field$.b', injdef2, 'value')
}

function testSpecialSyntax(): void {
    /** Test getpath with special syntax features. */
    console.log('\n' + '='.repeat(80))
    console.log('SPECIAL SYNTAX TESTS')
    console.log('='.repeat(80))
    
    // Test 1: Double dollar escape
    const store1 = { '$TOP': { 'a': { 'b': 'value' } } }
    logTest('Double dollar escape', store1, 'a.$$b', undefined, 'value')
    
    // Test 2: $GET syntax
    const store2 = { '$TOP': { 'a': { 'b': 'value' }, 'path': 'a.b' } }
    const injdef2: Partial<Injection> = {
        mode: 'val',
        full: false,
        keyI: 0,
        keys: ['test'],
        key: 'test',
        val: { 'b': 'value' },
        parent: { 'test': { 'b': 'value' } },
        path: ['test'],
        nodes: [{ 'test': { 'b': 'value' } }],
        handler: undefined,
        dparent: store2
    }
    logTest('$GET syntax', store2, '$GET:path$', injdef2, 'a.b')
    
    // Test 3: $REF syntax
    const store3 = { '$TOP': { 'a': { 'b': 'value' } }, '$SPEC': { 'ref': 'a.b' } }
    const injdef3: Partial<Injection> = {
        mode: 'val',
        full: false,
        keyI: 0,
        keys: ['test'],
        key: 'test',
        val: { 'b': 'value' },
        parent: { 'test': { 'b': 'value' } },
        path: ['test'],
        nodes: [{ 'test': { 'b': 'value' } }],
        handler: undefined,
        dparent: store3
    }
    logTest('$REF syntax', store3, '$REF:ref$', injdef3, 'a.b')
    
    // Test 4: $META syntax
    const store4 = { '$TOP': { 'a': { 'b': 'value' } } }
    const injdef4: Partial<Injection> = {
        mode: 'val',
        full: false,
        keyI: 0,
        keys: ['test'],
        key: 'test',
        val: { 'b': 'value' },
        parent: { 'test': { 'b': 'value' } },
        path: ['test'],
        nodes: [{ 'test': { 'b': 'value' } }],
        handler: undefined,
        meta: { 'metapath': 'a.b' },
        dparent: store4
    }
    logTest('$META syntax', store4, '$META:metapath$', injdef4, 'a.b')
}

function testAscendSyntax(): void {
    /** Test getpath with ascend syntax (empty path parts). */
    console.log('\n' + '='.repeat(80))
    console.log('ASCEND SYNTAX TESTS')
    console.log('='.repeat(80))
    
    // Test 1: Single ascend
    const store1 = { '$TOP': { 'a': { 'b': { 'c': 'value' } } } }
    const injdef1: Partial<Injection> = {
        mode: 'val',
        full: false,
        keyI: 0,
        keys: ['test'],
        key: 'test',
        val: { 'c': 'value' },
        parent: { 'test': { 'c': 'value' } },
        path: ['test'],
        nodes: [{ 'test': { 'c': 'value' } }],
        handler: undefined,
        dpath: ['$TOP', 'a', 'b'],
        dparent: store1
    }
    logTest('Single ascend', store1, '..c', injdef1, 'value')
    
    // Test 2: Multiple ascends
    const store2 = { '$TOP': { 'a': { 'b': { 'c': 'value' } } } }
    const injdef2: Partial<Injection> = {
        mode: 'val',
        full: false,
        keyI: 0,
        keys: ['test'],
        key: 'test',
        val: { 'c': 'value' },
        parent: { 'test': { 'c': 'value' } },
        path: ['test'],
        nodes: [{ 'test': { 'c': 'value' } }],
        handler: undefined,
        dpath: ['$TOP', 'a', 'b'],
        dparent: store2
    }
    logTest('Multiple ascends', store2, '...a', injdef2, { 'b': { 'c': 'value' } })
}

function testHandler(): void {
    /** Test getpath with custom handler. */
    console.log('\n' + '='.repeat(80))
    console.log('HANDLER TESTS')
    console.log('='.repeat(80))
    
    function customHandler(injdef: any, val: any, ref: any, store: any): string {
        console.log(`  Handler called with val=${stringify(val)}, ref=${stringify(ref)}`)
        return 'handler_result'
    }
    
    const store = { '$TOP': { 'a': { 'b': 'value' } } }
    const injdef: Partial<Injection> = {
        mode: 'val',
        full: false,
        keyI: 0,
        keys: ['test'],
        key: 'test',
        val: { 'b': 'value' },
        parent: { 'test': { 'b': 'value' } },
        path: ['test'],
        nodes: [{ 'test': { 'b': 'value' } }],
        handler: customHandler,
        dparent: store
    }
    logTest('Custom handler', store, 'a.b', injdef, 'handler_result')
}

function testEdgeCases(): void {
    /** Test getpath edge cases. */
    console.log('\n' + '='.repeat(80))
    console.log('EDGE CASES')
    console.log('='.repeat(80))
    
    // Test 1: Null/undefined inputs
    logTest('Null store', null, 'a.b', undefined, null)
    logTest('Null path', { '$TOP': { 'a': 'b' } }, null, undefined, { 'a': 'b' })
    
    // Test 2: Empty store
    logTest('Empty store', {}, 'a.b', undefined, null)
    
    // Test 3: Function in store
    function testFunc(): string {
        return 'function_result'
    }
    
    const store3 = { '$TOP': { 'func': testFunc } }
    logTest('Function in store', store3, 'func', undefined, testFunc)
    
    // Test 4: Complex nested structure
    const store4 = {
        '$TOP': {
            'users': [
                { 'id': 1, 'name': 'Alice', 'profile': { 'age': 30, 'city': 'NYC' } },
                { 'id': 2, 'name': 'Bob', 'profile': { 'age': 25, 'city': 'LA' } },
                { 'id': 3, 'name': 'Charlie', 'profile': { 'age': 35, 'city': 'CHI' } }
            ],
            'settings': {
                'theme': 'dark',
                'notifications': { 'email': true, 'sms': false }
            }
        }
    }
    logTest('Complex nested structure', store4, 'users.1.profile.city', undefined, 'LA')
    logTest('Complex nested structure 2', store4, 'settings.notifications.email', undefined, true)
}

function runAllTests(): void {
    /** Run all test categories. */
    console.log('TYPESCRIPT GETPATH COMPREHENSIVE TEST SUITE')
    console.log('='.repeat(80))
    
    testBasicGetpath()
    testInjectionState()
    testSpecialSyntax()
    testAscendSyntax()
    testHandler()
    testEdgeCases()
    
    console.log('\n' + '='.repeat(80))
    console.log('ALL TESTS COMPLETED')
    console.log('='.repeat(80))
}

// Run the tests
runAllTests() 