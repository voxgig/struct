type PropKey = string | number;
type Indexable = {
    [key: string]: any;
} & {
    [key: number]: any;
};
type InjectMode = 'key:pre' | 'key:post' | 'val';
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
declare function isnode(val: any): val is Indexable;
declare function ismap(val: any): val is {
    [key: string]: any;
};
declare function islist(val: any): val is any[];
declare function iskey(key: any): key is PropKey;
declare function isempty(val: any): boolean;
declare function isfunc(val: any): val is Function;
declare function size(val: any): number;
declare function slice<V extends any>(val: V, start?: number, end?: number): V;
declare function pad(str: any, padding?: number, padchar?: string): string;
declare function typify(value: any): string;
declare function getelem(val: any, key: any, alt?: any): any;
declare function getprop(val: any, key: any, alt?: any): any;
declare function strkey(key?: any): string;
declare function keysof(val: any): string[];
declare function haskey(val: any, key: any): boolean;
declare function items(val: any): [number | string, any][];
declare function escre(s: string): string;
declare function escurl(s: string): string;
declare function joinurl(sarr: any[]): string;
declare function stringify(val: any, maxlen?: number, pretty?: any): string;
declare function pathify(val: any, startin?: number, endin?: number): string;
declare function clone(val: any): any;
declare function delprop<PARENT>(parent: PARENT, key: any): PARENT;
declare function setprop<PARENT>(parent: PARENT, key: any, val: any): PARENT;
declare function walk(val: any, apply: WalkApply, key?: string | number, parent?: any, path?: string[]): any;
declare function merge(val: any): any;
declare function getpath(store: any, path: string | string[], injdef?: Partial<Injection>): any;
declare function inject(val: any, store: any, injdef?: Partial<Injection>): any;
declare function transform(data: any, // Source data to transform into new data (original not mutated)
spec: any, // Transform specification; output follows this shape
injdef?: Partial<Injection>): any;
declare function validate(data: any, // Source data to transform into new data (original not mutated)
spec: any, // Transform specification; output follows this shape
injdef?: Partial<Injection>): any;
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
    setval(val: any, ancestor?: number): any;
}
declare class StructUtility {
    clone: typeof clone;
    delprop: typeof delprop;
    escre: typeof escre;
    escurl: typeof escurl;
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
    joinurl: typeof joinurl;
    keysof: typeof keysof;
    merge: typeof merge;
    pad: typeof pad;
    pathify: typeof pathify;
    setprop: typeof setprop;
    size: typeof size;
    slice: typeof slice;
    strkey: typeof strkey;
    stringify: typeof stringify;
    transform: typeof transform;
    typify: typeof typify;
    validate: typeof validate;
    walk: typeof walk;
}
export { StructUtility, clone, delprop, escre, escurl, getelem, getpath, getprop, haskey, inject, isempty, isfunc, iskey, islist, ismap, isnode, items, joinurl, keysof, merge, pad, pathify, setprop, size, slice, strkey, stringify, transform, typify, validate, walk, };
export type { Injection, Injector, WalkApply };
