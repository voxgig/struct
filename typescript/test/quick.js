

const {
  transform, setpath, items, isnode, merge,
  validate, tn, T_noval, T_null, T_bool, T_any, 
  T_map, T_node, T_scalar, T_number, T_integer, T_decimal,
  T_string, T_function, T_instance,
  typify, getdef, flatten,
  slice, filter,
} = require('../')


// console.log(transform([{x:'a'},{x:'b'},{x:'c'}],{'`$PACK`':['',{
//  '`$KEY`': 'x', y:'`.x`'
// }]}))

/*
// console.log(transform([{x:'a'},{x:'b'},{x:'c'}],{'`$PACK`':['',{
 console.log(transform([{x:'a'}],{'`$PACK`':['',{
  '`$KEY`': 'x',
  //   '`$VAL`': {z:'`.x`'},
  //   '`$VAL`': '`.x`',
   '`$VAL`': '`$KEY.x`',
  //  '`$VAL`': '`a.x`',
  // '`$VAL`': '`.x`',
  // '`$VAL`': '`a`',
}]}))


console.log(transform({a:{x:'A'}},{a:'`$KEY.x`'}))
// console.log(transform({a:{x:'A'}},{a:'`a.x`'}))
*/

// console.log(transform({a:'A'},{a:'`.$KEY`'}))
// console.log(transform({a:'A'},{a:'`$COPY`'}))


/*
console.log(transform(['a','b','c'],{'`$PACK`':['',{
  // '`$KEY`': '`$KEY`',
  '`$VAL`': '`.$KEY`',
}]}))
*/


// console.log(transform('a','`.$KEY`'))

// console.log(transform(['a','b','c'],{'`$PACK`':['','`$COPY`']}))
// console.log(transform(['a','b','c'],{'`$PACK`':['','`.$KEY`']}))
// console.log(transform(['a','b','c'],{'`$PACK`':['',{'`$VAL`':'`$COPY`'}]}))
// console.log(transform(['a','b','c'],{'`$PACK`':['',{'`$KEY`':'`$COPY`', x:9}]}))
// console.log(transform(['a','b','c'],{'`$PACK`':['',{'`$KEY`':'`$COPY`', '`$VAL`':'`$COPY`'}]}))


/*
console.dir(
  transform(
    {v100:11,x100:[{y:0,k:'K0'},{y:1,k:'K1'}]},
    {a:{b:{'`$PACK`':['x100',{'`$KEY`':'k', y:'`.y`',p:'`...v100`'}]}}}),
  {depth:null}
)
*/


let x
// console.log(setpath(x={a:1}, 'a', 2),x)
// console.log(setpath(x={a:{b:1}}, 'a.b', 2),x)
// console.log(setpath(x={a:{b:1}}, 'a', 3),x)
// console.log(setpath(x={a:{b:1}}, '', 4),x)
// console.log(setpath(x={a:{b:1}}, 'a.b.c', 5),x)
// console.log(setpath(x={a:{b:1}}, 'a.b.0', 6),x)
// console.log(setpath(x={a:{b:1}}, ['a','b',1], 7),x)
// console.log(setpath(x={a:{b:[11,22,33]}}, ['a','b',1], 8),x)



// console.log(transform({}, {x:['`$FORMAT`','upper','a']}))
// console.log(transform({}, {x:['`$FORMAT`','upper',{y:'b'}]}))

// // console.log(transform({z:'c'}, {x:['`$FORMAT`','upper','`$WHEN`']}))
// // console.log(transform({z:'c'}, {x:{y:'`$WHEN`'}}))
// // console.log(transform({z:'c'}, {x:['`$FORMAT`','upper',{y:'`$WHEN`'}]}))

// console.log(transform({z:'c'}, {x:['`$FORMAT`','upper','`z`']}))
// console.log(transform({z:'c'}, {x:['`$FORMAT`','upper',{y:'`z`'}]}))

// console.log(transform({z:'C'}, {x:['`$FORMAT`','lower',{y:['`z`']}]}))
// console.log(transform({z:'C'}, {x:['`$FORMAT`','lower','`z`']}))


// console.log(transform(['a','b','c'],
//                       {'`$PACK`':['',{'`$KEY`':'`$COPY`',
//                                       '`$VAL`':['`$FORMAT`','upper','`$COPY`']}]}))

// console.log(transform(['a','b','c'],['`$EACH`','','`$COPY`']))
// console.log(transform(['a','b','c'],['`$EACH`','',['`$FORMAT`','upper','`$COPY`']]))


// console.log(transform(null,['`$FORMAT`','upper','a']))
// console.log(transform(null,['`$FORMAT`','string',99]))
// console.log(transform(null,['`$FORMAT`','number','1.2']))
// console.log(transform(null,['`$FORMAT`','integer','3.4']))
// console.log(transform(null,['`$FORMAT`','concat','a']))

// console.log(items(['a','b',3], (n => isnode(n[1]) ? '' : ('' + n[1]))).join(''))
// console.log(transform({x:2},['`$FORMAT`','concat',['a','`x`',3]]))
// console.log(transform({x:2},['`$FORMAT`','concat',{q:['a','`x`',3]}]))
// console.log(transform({x:'y'},['`$FORMAT`','concat','`x`']))
// console.log(transform({x:'y'},['`$FORMAT`','upper','`x`']))

// console.log(transform({x:'y'},['`$FORMAT`','concat',['a','b']]))

// console.log(transform({x:'y'},['`$FORMAT`','concat',['`x`']]))
// console.log(transform({x:'y'},['`$FORMAT`','concat',['`x`']]))
// console.log(transform({x:'y'},['`$FORMAT`','upper',['`x`']]))
// console.log(transform({x:'y'},['`$FORMAT`','upper',{q:{z:'`x`'}}]))
// console.log(transform({x:'y'},['`$FORMAT`','upper','`x`']))
// console.log(transform({x:'y'},['`$FORMAT`','upper',{z:'`x`'}]))

// console.log(transform({x:'y'},['`$FORMAT`','upper',{x:'`x`'}]))
// console.log(transform({x:'y'},{q:['`$FORMAT`','upper',{x:'`x`'}]}))

// console.log(transform({x:'y'},{q:['`$FORMAT`',(k,v)=>(''+v).toUpperCase(),'`x`']}))


// console.log(merge([{},{x:{z:11}},{y:22}],0))
// console.log(merge([{},{x:{z:11}},{y:22}],1))
// console.log(merge([{},{x:{z:11}},{y:22}],2))
// console.log(merge([{},{x:{z:11}},{y:22}],3))


// console.log(merge([{},{x:{z:11}},{x:{z:22}}],0))
// console.log(merge([{},{x:{z:11}},{x:{z:22}}],1))
// console.log(merge([{},{x:{z:11}},{x:{z:22}}],2))
// console.log(merge([{},{x:{z:11}},{x:{z:22}}],3))


// console.log(merge([{},{x:{z:11}},{x:{z:22}},{y:33}],0))
// console.log(merge([{},{x:{z:11}},{x:{z:22}},{y:33}],1))
// console.log(merge([{},{x:{z:11}},{x:{z:22}},{y:33}],2))
// console.log(merge([{},{x:{z:11}},{x:{z:22}},{y:33}],3))


// console.log(merge([{},{x:{z:11,q:10,p:8}},{x:{z:22,q:20,r:9}},{y:33}],0))
// console.log(merge([{},{x:{z:11,q:10,p:8}},{x:{z:22,q:20,r:9}},{y:33}],1))
// console.log(merge([{},{x:{z:11,q:10,p:8}},{x:{z:22,q:20,r:9}},{y:33}],2))
// console.log(merge([{},{x:{z:11,q:10,p:8}},{x:{z:22,q:20,r:9}},{y:33}],3))


// console.log(transform({x:'y'},{q:['`$APPLY`',(v)=>(''+v).toUpperCase(),'`x`']}))
// console.log(transform({x:'y'},{q:['`$APPLY`',(v)=>'a'.repeat(v),3]}))



// console.log(validate({x:1},{x:'`$ONE`'}))

// console.log(transform({x:1},{x:['`$APPLY`']}))

// console.log(T_any, tn(T_any), T_noval, tn(T_noval),T_bool, tn(T_bool))
// console.log(tn(T_number), tn(T_number|T_integer),
//             Math.clz32(T_number), Math.clz32(T_number|T_integer), )

// console.log(T_map, T_node, T_map|T_node)
// console.log(T_scalar, T_number, T_integer, T_decimal)
// console.log(T_scalar|T_number|T_integer)
// console.log(T_scalar|T_number|T_decimal)
// console.log(T_scalar|T_string)
// console.log(T_scalar|T_bool)
// console.log(T_scalar, T_function, T_scalar|T_function)
// console.log(typify(null),T_noval)
// console.log(T_any, T_integer, T_any & T_integer)



// console.log(typify(1001), T_integer, T_number, T_scalar, T_integer|T_number|T_scalar, 'QQQ',
//           T_integer & typify(1001))


// console.log(T_noval, T_null, T_null&T_scalar)

// let o = {x:1}
// let ot = typify(o)
// console.log(ot, T_node|T_map, T_instance, T_function, T_instance|T_function, (T_instance|T_function)&ot)


// console.log(getdef(1,2), getdef(undefined,3))

// console.log(flatten([1,[2,3],[[4]]]))
// console.log(flatten([1,[2,3],[[4]]],2))

// let a = [2]
// console.log(flatten([1,getdef(a,[])]))

// a = undefined
// console.log(flatten([1,getdef(a,[])]))

// let a = [1,2,3,4]
// let b = slice(a,1,3,true)
// console.log(a,b,a===b)


// a = [1,2,3,4]
// b = slice(a,0,4,true)
// console.log(a,b,a===b)

// a = [1,2,3,4]
// b = slice(a,0,0,true)
// console.log(a,b,a===b)


// a = [1,2,3,4]
// b = slice(a,0,5,true)
// console.log(a,b,a===b)


// a = [1,2,3,4]
// b = slice(a,5,6,true)
// console.log(a,b,a===b)


// a = [1,2,3,4]
// b = slice(a,2,6,true)
// console.log(a,b,a===b)


// console.log(filter([1,2,3,4], (n)=>n[1]>3))


console.log(typify(1), typify(1.1))
