// Minimal in-tree insertion-ordered map.
//
// Rust's `std::collections::HashMap` doesn't preserve insertion order, and
// the canonical contract requires that JSON object key order survive every
// operation. Other ports either get this for free (Python 3.7+ dict,
// Ruby Hash, PHP array, JS object), or hand-roll an OrderedMap
// (C / C++ / Zig). This is the Rust equivalent — keeps the port
// dependency-free.
//
// Only the operations the rest of voxgig-struct uses are implemented:
// `new`, `insert`, `get`, `contains_key`, `shift_remove`, `iter`,
// `iter_mut`, `keys`, `values`, `len`, `is_empty`, indexing by `&str`,
// `Clone`, `IntoIterator` and `FromIterator`.
//
// Parallel keys + values vectors preserve insertion order; a separate
// `HashMap<String, usize>` indexes key -> position for O(1) lookup.
// `shift_remove` is O(n) on a vec-shift plus an O(n) index rebuild; the
// corpus's map sizes are modest so this is the right complexity trade.

use std::collections::HashMap;
use std::ops::Index;

#[derive(Clone, Default)]
pub struct OrderedMap<V> {
    keys: Vec<String>,
    values: Vec<V>,
    index: HashMap<String, usize>,
}

impl<V> OrderedMap<V> {
    pub fn new() -> Self {
        OrderedMap {
            keys: Vec::new(),
            values: Vec::new(),
            index: HashMap::new(),
        }
    }

    pub fn len(&self) -> usize {
        self.keys.len()
    }
    pub fn is_empty(&self) -> bool {
        self.keys.is_empty()
    }

    pub fn contains_key(&self, key: &str) -> bool {
        self.index.contains_key(key)
    }

    pub fn get(&self, key: &str) -> Option<&V> {
        self.index.get(key).map(|&i| &self.values[i])
    }

    pub fn get_mut(&mut self, key: &str) -> Option<&mut V> {
        if let Some(&i) = self.index.get(key) {
            Some(&mut self.values[i])
        } else {
            None
        }
    }

    pub fn insert(&mut self, key: String, value: V) -> Option<V> {
        if let Some(&i) = self.index.get(&key) {
            return Some(std::mem::replace(&mut self.values[i], value));
        }
        self.index.insert(key.clone(), self.keys.len());
        self.keys.push(key);
        self.values.push(value);
        None
    }

    /// Remove an entry, shifting later entries left to preserve order.
    pub fn shift_remove(&mut self, key: &str) -> Option<V> {
        let i = self.index.remove(key)?;
        self.keys.remove(i);
        let v = self.values.remove(i);
        // Re-index every entry whose position changed.
        for (k, idx) in self.index.iter_mut() {
            if *idx > i {
                *idx -= 1;
            }
            // Defensive — the removed key is gone from `index` already.
            let _ = k;
        }
        Some(v)
    }

    pub fn keys(&self) -> std::slice::Iter<'_, String> {
        self.keys.iter()
    }
    pub fn values(&self) -> std::slice::Iter<'_, V> {
        self.values.iter()
    }

    pub fn iter(&self) -> OrderedMapIter<'_, V> {
        OrderedMapIter {
            keys: &self.keys,
            values: &self.values,
            i: 0,
        }
    }

    pub fn iter_mut(&mut self) -> impl Iterator<Item = (&String, &mut V)> {
        self.keys.iter().zip(self.values.iter_mut())
    }
}

pub struct OrderedMapIter<'a, V> {
    keys: &'a [String],
    values: &'a [V],
    i: usize,
}

impl<'a, V> Iterator for OrderedMapIter<'a, V> {
    type Item = (&'a String, &'a V);
    fn next(&mut self) -> Option<Self::Item> {
        if self.i >= self.keys.len() {
            return None;
        }
        let r = (&self.keys[self.i], &self.values[self.i]);
        self.i += 1;
        Some(r)
    }
}

impl<V> Index<&str> for OrderedMap<V> {
    type Output = V;
    fn index(&self, key: &str) -> &V {
        self.get(key).expect("OrderedMap: missing key")
    }
}

impl<V> FromIterator<(String, V)> for OrderedMap<V> {
    fn from_iter<I: IntoIterator<Item = (String, V)>>(iter: I) -> Self {
        let mut m = OrderedMap::new();
        for (k, v) in iter {
            m.insert(k, v);
        }
        m
    }
}

impl<'a, V> IntoIterator for &'a OrderedMap<V> {
    type Item = (&'a String, &'a V);
    type IntoIter = OrderedMapIter<'a, V>;
    fn into_iter(self) -> Self::IntoIter {
        self.iter()
    }
}

impl<V: std::fmt::Debug> std::fmt::Debug for OrderedMap<V> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let mut m = f.debug_map();
        for (k, v) in self.iter() {
            m.entry(k, v);
        }
        m.finish()
    }
}
