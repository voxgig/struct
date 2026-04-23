declare const M_KEYPRE = 1;
declare const M_KEYPOST = 2;
declare const M_VAL = 4;
declare const T_any: number;
declare const T_noval: number;
declare const T_boolean: number;
declare const T_decimal: number;
declare const T_integer: number;
declare const T_number: number;
declare const T_string: number;
declare const T_function: number;
declare const T_symbol: number;
declare const T_null: number;
declare const T_list: number;
declare const T_map: number;
declare const T_instance: number;
declare const T_scalar: number;
declare const T_node: number;
declare const SKIP: {
    '`$SKIP`': boolean;
};
declare const DELETE: {
    '`$DELETE`': boolean;
};
type PropKey = string | number;
type Indexable = {
    [key: string]: any;
} & {
    [key: number]: any;
};
type InjectMode = number;
type Injector = (inj: Injection, // Injection state.
val: any, // Injection value specification.
ref: string, // Original injection reference string.
store: any) => any;
type Modify = (val: any, // Value.
key?: PropKey, // Value key, if any,
parent?: any, // Parent node, if any.
inj?: Injection, // Injection state, if any.
store?: any) => void;
type WalkApply = (key: string | number | undefined, val: any, parent: any, path: string[]) => any;
declare function typename(t: number): any;
declare function getdef(val: any, alt: any): any;
declare function isnode(val: any): val is Indexable;
declare function ismap(val: any): val is {
    [key: string]: any;
};
declare function islist(val: any): val is any[];
declare function iskey(key: any): key is PropKey;
declare function isempty(val: any): boolean;
declare function isfunc(val: any): val is Function;
declare function size(val: any): number;
declare function slice<V extends any>(val: V, start?: number, end?: number, mutate?: boolean): V;
declare function pad(str: any, padding?: number, padchar?: string): string;
declare function typify(value: any): number;
declare function getelem(val: any, key: any, alt?: any): any;
declare function getprop(val: any, key: any, alt?: any): any;
declare function strkey(key?: any): string;
declare function keysof(val: any): string[];
declare function haskey(val: any, key: any): boolean;
declare function items(val: any): [string, any][];
declare function items<T>(val: any, apply: (item: [string, any]) => T): T[];
declare function flatten(list: any[], depth?: number): any[];
declare function filter(val: any, check: (item: [string, any]) => boolean): any[];
declare function escre(s: string): string;
declare function escurl(s: string): string;
declare function join(arr: any[], sep?: string, url?: boolean): string;
declare function jsonify(val: any, flags?: {
    indent?: number;
    offset?: number;
}): string;
declare function stringify(val: any, maxlen?: number, pretty?: any): string;
declare function pathify(val: any, startin?: number, endin?: number): string;
declare function clone(val: any): any;
declare function jm(...kv: any[]): Record<string, any>;
declare function jt(...v: any[]): any[];
declare function delprop<PARENT>(parent: PARENT, key: any): PARENT;
declare function setprop<PARENT>(parent: PARENT, key: any, val: any): PARENT;
declare function walk(val: any, before?: WalkApply, after?: WalkApply, maxdepth?: number, key?: string | number, parent?: any, path?: string[], pool?: string[][]): any;
declare function merge(val: any, maxdepth?: number): any;
declare function setpath(store: any, path: number | string | string[], val: any, injdef?: Partial<Injection>): any;
declare function getpath(store: any, path: number | string | string[], injdef?: Partial<Injection>): any;
declare function inject(val: any, store: any, injdef?: Partial<Injection>): any;
declare function transform(data: any, // Source data to transform into new data (original not mutated)
spec: any, // Transform specification; output follows this shape
injdef?: Partial<Injection>): any;
declare function validate(data: any, // Source data to transform into new data (original not mutated)
spec: any, // Transform specification; output follows this shape
injdef?: Partial<Injection>): any;
declare function select(children: any, query: any): any[];
declare class Injection {
    mode: InjectMode;
    full: boolean;
    keyI: number;
    keys: string[];
    key: string;
    val: any;
    parent: any;
    path: string[];
    nodes: any[];
    handler: Injector;
    errs: any[];
    meta: Record<string, any>;
    dparent: any;
    dpath: string[];
    base?: string;
    modify?: Modify;
    prior?: Injection;
    extra?: any;
    constructor(val: any, parent: any);
    toString(prefix?: string): string;
    descend(): any;
    child(keyI: number, keys: string[]): Injection;
    setval(val: any, ancestor?: number): undefined;
}
declare const MODENAME: any;
declare function checkPlacement(modes: InjectMode, ijname: string, parentTypes: number, inj: Injection): boolean;
declare function injectorArgs(argTypes: number[], args: any[]): any;
declare function injectChild(child: any, store: any, inj: Injection): Injection;
declare class StructUtility {
    clone: typeof clone;
    delprop: typeof delprop;
    escre: typeof escre;
    escurl: typeof escurl;
    filter: typeof filter;
    flatten: typeof flatten;
    getdef: typeof getdef;
    getelem: typeof getelem;
    getpath: typeof getpath;
    getprop: typeof getprop;
    haskey: typeof haskey;
    inject: typeof inject;
    isempty: typeof isempty;
    isfunc: typeof isfunc;
    iskey: typeof iskey;
    islist: typeof islist;
    ismap: typeof ismap;
    isnode: typeof isnode;
    items: typeof items;
    join: typeof join;
    jsonify: typeof jsonify;
    keysof: typeof keysof;
    merge: typeof merge;
    pad: typeof pad;
    pathify: typeof pathify;
    select: typeof select;
    setpath: typeof setpath;
    setprop: typeof setprop;
    size: typeof size;
    slice: typeof slice;
    strkey: typeof strkey;
    stringify: typeof stringify;
    transform: typeof transform;
    typify: typeof typify;
    typename: typeof typename;
    validate: typeof validate;
    walk: typeof walk;
    SKIP: {
        '`$SKIP`': boolean;
    };
    DELETE: {
        '`$DELETE`': boolean;
    };
    jm: typeof jm;
    jt: typeof jt;
    tn: typeof typename;
    T_any: number;
    T_noval: number;
    T_boolean: number;
    T_decimal: number;
    T_integer: number;
    T_number: number;
    T_string: number;
    T_function: number;
    T_symbol: number;
    T_null: number;
    T_list: number;
    T_map: number;
    T_instance: number;
    T_scalar: number;
    T_node: number;
    checkPlacement: typeof checkPlacement;
    injectorArgs: typeof injectorArgs;
    injectChild: typeof injectChild;
}
export { StructUtility, clone, delprop, escre, escurl, filter, flatten, getdef, getelem, getpath, getprop, haskey, inject, isempty, isfunc, iskey, islist, ismap, isnode, items, join, jsonify, keysof, merge, pad, pathify, select, setpath, setprop, size, slice, strkey, stringify, transform, typify, typename, validate, walk, SKIP, DELETE, jm, jt, T_any, T_noval, T_boolean, T_decimal, T_integer, T_number, T_string, T_function, T_symbol, T_null, T_list, T_map, T_instance, T_scalar, T_node, M_KEYPRE, M_KEYPOST, M_VAL, MODENAME, checkPlacement, injectorArgs, injectChild, };
export type { Injection, Injector, WalkApply };
