/**
 * Simple test script for TypeScript getpath function.
 * This can be compiled and run to test basic functionality.
 */

// Import the functions we need to test
// Note: This will need to be compiled first

function logTest(testName: string, store: any, path: string | string[] | null, expected?: any): void {
    console.log('\n' + '='.repeat(60))
    console.log(`TEST: ${testName}`)
    console.log('='.repeat(60))
    
    console.log(`Input store: ${JSON.stringify(store)}`)
    console.log(`Input path: ${JSON.stringify(path)}`)
    
    // For now, we'll just log what we would call
    console.log(`Would call: getpath(store, path)`)
    console.log(`Expected: ${JSON.stringify(expected)}`)
}

function testBasicGetpath(): void {
    console.log('\n' + '='.repeat(80))
    console.log('BASIC GETPATH TESTS')
    console.log('='.repeat(80))
    
    // Test 1: Simple object access
    const store1 = { '$TOP': { 'a': { 'b': 'value' } } }
    logTest('Simple object access', store1, 'a.b', { 'b': 'value' })
    
    // Test 2: Array access
    const store2 = { '$TOP': { 'arr': [1, 2, 3, 4, 5] } }
    logTest('Array access', store2, 'arr.2', 3)
    
    // Test 3: Nested array access
    const store3 = { '$TOP': { 'nested': { 'arr': [{ 'id': 1 }, { 'id': 2 }, { 'id': 3 }] } } }
    logTest('Nested array access', store3, 'nested.arr.1.id', 2)
    
    // Test 4: Missing path
    const store4 = { '$TOP': { 'a': { 'b': 'value' } } }
    logTest('Missing path', store4, 'a.c', undefined)
    
    // Test 5: Empty path
    const store5 = { '$TOP': { 'a': { 'b': 'value' } } }
    logTest('Empty path', store5, '', { 'a': { 'b': 'value' } })
}

function testSpecialSyntax(): void {
    console.log('\n' + '='.repeat(80))
    console.log('SPECIAL SYNTAX TESTS')
    console.log('='.repeat(80))
    
    // Test 1: Double dollar escape
    const store1 = { '$TOP': { 'a': { 'b': 'value' } } }
    logTest('Double dollar escape', store1, 'a.$$b', 'value')
    
    // Test 2: Complex nested structure
    const store2 = {
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
    logTest('Complex nested structure', store2, 'users.1.profile.city', 'LA')
    logTest('Complex nested structure 2', store2, 'settings.notifications.email', true)
}

function testEdgeCases(): void {
    console.log('\n' + '='.repeat(80))
    console.log('EDGE CASES')
    console.log('='.repeat(80))
    
    // Test 1: Null/undefined inputs
    logTest('Null store', null, 'a.b', null)
    logTest('Null path', { '$TOP': { 'a': 'b' } }, null, { 'a': 'b' })
    
    // Test 2: Empty store
    logTest('Empty store', {}, 'a.b', null)
}

function runAllTests(): void {
    console.log('TYPESCRIPT GETPATH SIMPLE TEST SUITE')
    console.log('='.repeat(80))
    
    testBasicGetpath()
    testSpecialSyntax()
    testEdgeCases()
    
    console.log('\n' + '='.repeat(80))
    console.log('ALL TESTS COMPLETED')
    console.log('='.repeat(80))
}

// Run the tests
runAllTests() 