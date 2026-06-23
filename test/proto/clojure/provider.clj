;; Test Provider (prototype) — Clojure port of the canonical ts/provider.ts.
;;
;; Reads the shared corpus (build/test/test.json) and hands test code clean,
;; normalized cases. It is NOT a test runner: it never calls the subject and
;; never asserts. See ../PROVIDER.md for the model and ../AGENTS.md for usage.
;;
;; Zero runtime dependencies (Clojure / Java stdlib only). This includes a
;; hand-written, minimal JSON reader — no clojure.data.json, no cheshire.
;;
;; ─── Data model produced by the JSON reader ────────────────────────────────
;;
;;   JSON object  -> a Clojure persistent map. Key INSERTION ORDER is preserved
;;                   by attaching it as metadata under :order (a vector of the
;;                   string keys). The map value itself is an ordinary Clojure
;;                   map so get / contains? / deep-equality work idiomatically;
;;                   `okeys` reads :order to recover JSON order (needed so that
;;                   functions()/groups() report keys in corpus order).
;;   JSON array   -> a Clojure vector.
;;   JSON string  -> java.lang.String.
;;   JSON number  -> Long (integral) or Double (has . / e / E).
;;   JSON true/false -> Boolean.
;;   JSON null    -> the keyword ::null  (a DISTINCT sentinel, kept separate
;;                   from Clojure nil which we reserve for "key absent").
;;
;; The ::null choice mirrors the TS provider keeping VALUE(null) distinct from
;; ABSENT: a present "out": null becomes {:kind :value :value ::null}, whereas
;; a missing "out" key becomes {:kind :absent}.

(ns voxgig.proto.provider
  (:refer-clojure :exclude [load])
  (:require [clojure.string :as str])
  (:import [java.util.regex Pattern]))

(def NULLMARK "__NULL__")
(def UNDEFMARK "__UNDEF__")
(def EXISTSMARK "__EXISTS__")

;; Distinct sentinel for JSON null (separate from Clojure nil = "absent").
(def JNULL ::null)

;; Sentinel distinguishing "key absent" from a present value during getpath.
(def MISSING ::missing)

;; ───────────────────────────────────────────────────────────────────────────
;; Ordered-map helpers
;; ───────────────────────────────────────────────────────────────────────────

(defn ordered-map
  "Build a Clojure map from a seq of [k v] pairs, recording insertion order
   in :order metadata so JSON key order can be recovered later."
  [pairs]
  (let [m (reduce (fn [acc [k v]] (assoc acc k v)) {} pairs)]
    (with-meta m {:order (mapv first pairs)})))

(defn okeys
  "Keys of an object map in JSON insertion order (falls back to (keys m))."
  [m]
  (or (:order (meta m)) (vec (keys m))))

(defn omap?
  "Is v a JSON object (a Clojure map)?"
  [v]
  (map? v))

;; ───────────────────────────────────────────────────────────────────────────
;; Minimal JSON reader -> ordered maps / vectors / Long / Double / String /
;; Boolean / JNULL
;; ───────────────────────────────────────────────────────────────────────────

(defn json-read [^String s]
  (let [n (count s)
        pos (int-array 1)]
    (letfn [(peek-c [] (when (< (aget pos 0) n) (.charAt s (aget pos 0))))
            (next-c [] (let [c (.charAt s (aget pos 0))]
                         (aset pos 0 (inc (aget pos 0))) c))
            (skip-ws []
              (while (and (< (aget pos 0) n)
                          (Character/isWhitespace (.charAt s (aget pos 0))))
                (aset pos 0 (inc (aget pos 0)))))
            (parse-val []
              (skip-ws)
              (let [c (peek-c)]
                (cond
                  (= c \{) (parse-obj)
                  (= c \[) (parse-arr)
                  (= c \") (parse-str)
                  (or (= c \t) (= c \f)) (parse-bool)
                  (= c \n) (parse-null)
                  :else (parse-num))))
            (parse-obj []
              (next-c) ;; consume {
              (skip-ws)
              (if (= (peek-c) \})
                (do (next-c) (ordered-map []))
                (loop [acc (transient [])]
                  (skip-ws)
                  (let [k (parse-str)]
                    (skip-ws)
                    (next-c) ;; consume :
                    (let [v (parse-val)
                          acc (conj! acc [k v])]
                      (skip-ws)
                      (let [c (next-c)]
                        (if (= c \,)
                          (recur acc)
                          (ordered-map (persistent! acc)))))))))
            (parse-arr []
              (next-c) ;; consume [
              (skip-ws)
              (if (= (peek-c) \])
                (do (next-c) [])
                (loop [acc (transient [])]
                  (let [v (parse-val)
                        acc (conj! acc v)]
                    (skip-ws)
                    (let [c (next-c)]
                      (if (= c \,)
                        (recur acc)
                        (persistent! acc)))))))
            (parse-str []
              (next-c) ;; consume opening "
              (let [sb (StringBuilder.)]
                (loop []
                  (let [c (next-c)]
                    (cond
                      (= c \") (.toString sb)
                      (= c \\)
                      (let [e (next-c)]
                        (case e
                          \" (.append sb \")
                          \\ (.append sb \\)
                          \/ (.append sb \/)
                          \n (.append sb \newline)
                          \t (.append sb \tab)
                          \r (.append sb \return)
                          \b (.append sb \backspace)
                          \f (.append sb \formfeed)
                          \u (let [hex (subs s (aget pos 0) (+ (aget pos 0) 4))]
                               (aset pos 0 (+ (aget pos 0) 4))
                               (.append sb (char (Integer/parseInt hex 16))))
                          (.append sb e))
                        (recur))
                      :else (do (.append sb c) (recur)))))))
            (parse-bool []
              (if (= (peek-c) \t)
                (do (aset pos 0 (+ (aget pos 0) 4)) true)   ;; true
                (do (aset pos 0 (+ (aget pos 0) 5)) false))) ;; false
            (parse-null []
              (aset pos 0 (+ (aget pos 0) 4)) JNULL)        ;; null
            (parse-num []
              (let [start (aget pos 0)]
                (while (and (< (aget pos 0) n)
                            (let [c (.charAt s (aget pos 0))]
                              (or (Character/isDigit c)
                                  (= c \-) (= c \+) (= c \.) (= c \e) (= c \E))))
                  (aset pos 0 (inc (aget pos 0))))
                (let [tok (subs s start (aget pos 0))]
                  (if (or (.contains tok ".") (.contains tok "e") (.contains tok "E"))
                    (Double/parseDouble tok)
                    (Long/parseLong tok)))))]
      (parse-val))))

;; ───────────────────────────────────────────────────────────────────────────
;; Default corpus path + load
;; ───────────────────────────────────────────────────────────────────────────

(defn default-test-file
  "build/test/test.json relative to the repo root.
   This file lives at test/proto/clojure/provider.clj, so the repo root is
   three directories up."
  []
  (let [here (-> (java.io.File. *file*) .getAbsoluteFile .getParentFile)] ;; test/proto/clojure
    (-> here .getParentFile .getParentFile .getParentFile               ;; repo root
        (java.io.File. "build/test/test.json")
        .getPath)))

;; ───────────────────────────────────────────────────────────────────────────
;; Group / function classification (mirrors ts isGroupBag / hasGroups)
;; ───────────────────────────────────────────────────────────────────────────

(defn group-bag?
  "A group bag is a map with a `set` vector."
  [v]
  (and (omap? v) (vector? (get v "set"))))

(defn has-groups?
  "A function node has at least one child group bag."
  [v]
  (and (omap? v)
       (boolean (some (fn [k] (and (not= k "name") (group-bag? (get v k))))
                      (okeys v)))))

;; ───────────────────────────────────────────────────────────────────────────
;; Provider — a plain map {:spec <parsed json>}
;; ───────────────────────────────────────────────────────────────────────────

(defn load
  "Parse test.json and return a provider map. Optional explicit path."
  ([] (load (default-test-file)))
  ([path] {:spec (json-read (slurp path))}))

(defn raw
  "The parsed test.json (escape hatch)."
  [provider]
  (:spec provider))

(defn- root-node
  "The struct sub-map if present, else the spec itself."
  [provider]
  (let [spec (:spec provider)]
    (or (and (omap? spec) (get spec "struct")) spec)))

(defn- fn-node
  [provider fnname]
  (let [spec (:spec provider)
        node (or (get (root-node provider) fnname)
                 (and (omap? spec) (get spec fnname)))]
    (when (nil? node)
      (throw (ex-info (str "Unknown function: " fnname) {:fn fnname})))
    node))

(defn functions
  "Top-level function names in corpus order."
  [provider]
  (let [root (root-node provider)]
    (vec (filter (fn [k] (or (group-bag? (get root k)) (has-groups? (get root k))))
                 (okeys root)))))

(defn groups
  "Group names for a function, in corpus order."
  [provider fnname]
  (let [node (fn-node provider fnname)]
    (vec (filter (fn [k] (and (not= k "name") (group-bag? (get node k))))
                 (okeys node)))))

;; ───────────────────────────────────────────────────────────────────────────
;; Normalization
;; ───────────────────────────────────────────────────────────────────────────

(defn- present?
  "JSON key presence — true if the map contains the key (value may be JNULL)."
  [raw key]
  (and (omap? raw) (contains? raw key)))

(defn- as-string
  "str of a value that is present and not JNULL, else nil. Mirrors ts
   `null != raw.id ? String(raw.id) : null` (JSON null counts as absent)."
  [raw key]
  (let [v (get raw key)]
    (when (and (some? v) (not= v JNULL)) (str v))))

(defn resolve-input
  "Tagged input. Precedence ctx > args > in. For :in, an absent \"in\" key
   yields JNULL (native null)."
  [raw]
  (cond
    (present? raw "ctx") {:kind :ctx :ctx (get raw "ctx")}
    (present? raw "args") {:kind :args :args (get raw "args")}
    :else {:kind :in :in (if (present? raw "in") (get raw "in") JNULL)}))

(defn parse-err
  "ErrorCheck from an `err` spec.
   true -> {:any true}; \"/re/\" -> regex; other string -> literal text;
   anything else -> any error."
  [err]
  (cond
    (true? err) {:any true :text nil :regex false}
    (string? err)
    (if-let [m (re-matches #"^/(.+)/$" err)]
      {:any false :text (second m) :regex true}
      {:any false :text err :regex false})
    :else {:any true :text nil :regex false}))

(defn resolve-expect
  "Tagged expectation. Precedence err > out > match > absent. Uses KEY
   PRESENCE (contains?), so out:null still yields :value. A co-existing match
   block is attached as :match on :error / :value."
  [raw]
  (let [match-part (when (present? raw "match") (get raw "match"))]
    (cond
      (present? raw "err")
      {:kind :error :error (parse-err (get raw "err")) :match match-part}
      (present? raw "out")
      {:kind :value :value (get raw "out") :match match-part}
      (present? raw "match")
      {:kind :match :match (get raw "match")}
      :else {:kind :absent})))

(defn normalize
  [fnname group index raw]
  {:function fnname
   :group group
   :index index
   :id (as-string raw "id")
   :doc (true? (get raw "doc"))
   :client (as-string raw "client")
   :input (resolve-input raw)
   :expect (resolve-expect raw)
   :raw raw})

(defn entries
  "All normalized entries for a function (optionally one group)."
  ([provider fnname] (entries provider fnname nil))
  ([provider fnname group]
   (let [node (fn-node provider fnname)
         gs (if (some? group) [group] (groups provider fnname))]
     (vec
      (mapcat
       (fn [g]
         (let [bag (get node g)]
           (when (group-bag? bag)
             (map-indexed (fn [i e] (normalize fnname g i e)) (get bag "set")))))
       gs)))))

;; ───────────────────────────────────────────────────────────────────────────
;; Pure comparison helpers (mirror PROVIDER.md §5)
;; ───────────────────────────────────────────────────────────────────────────

(declare compact-json)

(defn stringify
  "The string itself if already a string, else compact JSON."
  [x]
  (if (string? x) x (compact-json x)))

(defn- json-escape [^String s]
  (let [sb (StringBuilder.)]
    (doseq [c s]
      (case c
        \" (.append sb "\\\"")
        \\ (.append sb "\\\\")
        \newline (.append sb "\\n")
        \tab (.append sb "\\t")
        \return (.append sb "\\r")
        \backspace (.append sb "\\b")
        \formfeed (.append sb "\\f")
        (if (< (int c) 0x20)
          (.append sb (format "\\u%04x" (int c)))
          (.append sb c))))
    (.toString sb)))

(defn- num->json [x]
  ;; Render Doubles with integral value as 1, not 1.0, to match JSON.stringify.
  (if (and (instance? Double x) (== x (Math/rint x)) (Double/isFinite x))
    (str (long x))
    (str x)))

(defn compact-json
  "Compact JSON serialization mirroring JSON.stringify for our data model."
  [x]
  (cond
    (or (nil? x) (= x JNULL)) "null"
    (string? x) (str "\"" (json-escape x) "\"")
    (boolean? x) (str x)
    (number? x) (num->json x)
    (vector? x) (str "[" (str/join "," (map compact-json x)) "]")
    (sequential? x) (str "[" (str/join "," (map compact-json x)) "]")
    (map? x) (str "{"
                  (str/join ","
                            (map (fn [k] (str "\"" (json-escape (str k)) "\":"
                                              (compact-json (get x k))))
                                 (okeys x)))
                  "}")
    :else (str "\"" (json-escape (str x)) "\"")))

(defn- norm-null
  "Normalize __NULL__, JNULL and nil all to nil (lenient null collapse)."
  [x]
  (cond
    (or (= x NULLMARK) (= x JNULL) (nil? x)) nil
    (vector? x) (mapv norm-null x)
    (sequential? x) (mapv norm-null x)
    (map? x) (reduce (fn [acc k] (assoc acc k (norm-null (get x k)))) {} (keys x))
    :else x))

(defn- norm-mark
  "Strict normalize — only __NULL__ collapses to nil; JNULL stays distinct."
  [x]
  (cond
    (= x NULLMARK) nil
    (vector? x) (mapv norm-mark x)
    (sequential? x) (mapv norm-mark x)
    (map? x) (reduce (fn [acc k] (assoc acc k (norm-mark (get x k)))) {} (keys x))
    :else x))

(defn- deep-eq
  "Deep equality with JS-=== semantics: booleans never equal numbers, arrays
   only equal arrays, maps only equal maps (by key set + values)."
  [a b]
  (cond
    ;; bool/number distinction (Clojure already keeps true ≠ 1, but be explicit)
    (not= (boolean? a) (boolean? b)) false
    (and (sequential? a) (sequential? b))
    (and (= (count a) (count b))
         (every? true? (map deep-eq a b)))
    (or (sequential? a) (sequential? b)) false
    (and (map? a) (map? b))
    (let [ak (keys a) bk (keys b)]
      (and (= (count ak) (count bk))
           (every? (fn [k] (and (contains? b k) (deep-eq (get a k) (get b k)))) ak)))
    (or (map? a) (map? b)) false
    :else (= a b)))

(defn matchval
  "Scalar primitive match. check === base; else if check is a string:
   \"/re/\" => regex test of stringify(base); else case-insensitive substring
   of stringify(base). A function check => true."
  [check base]
  (cond
    (deep-eq check base) true
    (string? check)
    (let [basestr (stringify base)]
      (if-let [m (re-matches #"^/(.+)/$" check)]
        (boolean (re-find (Pattern/compile (second m)) basestr))
        (str/includes? (str/lower-case basestr) (str/lower-case check))))
    (fn? check) true
    :else false))

(defn equal
  "Deep equality with lenient null collapse (runner default null:true)."
  [expected actual]
  (deep-eq (norm-null expected) (norm-null actual)))

(defn equal-strict
  "Deep equality where absent/JNULL is distinct from __NULL__ (null:false)."
  [expected actual]
  (deep-eq (norm-mark expected) (norm-mark actual)))

(defn error-matches
  "ErrorCheck vs a thrown message."
  [check message]
  (cond
    (:any check) true
    (nil? (:text check)) false
    (:regex check) (boolean (re-find (Pattern/compile (:text check)) message))
    :else (str/includes? (str/lower-case message) (str/lower-case (:text check)))))

;; getpath for struct-match — returns MISSING for absent, distinct from JNULL.
(defn- mt-getpath [store path]
  (loop [cur store
         ks path]
    (if (empty? ks)
      cur
      (let [k (first ks)]
        (cond
          (or (nil? cur) (= cur MISSING) (= cur JNULL)) MISSING
          (vector? cur)
          (let [idx (try (Integer/parseInt (str k)) (catch Exception _ -1))]
            (recur (if (and (<= 0 idx) (< idx (count cur))) (nth cur idx) MISSING)
                   (rest ks)))
          (map? cur)
          (recur (if (contains? cur (str k)) (get cur (str k)) MISSING) (rest ks))
          :else MISSING)))))

(defn- walk-leaves [node path f]
  (cond
    (vector? node)
    (doseq [[i v] (map-indexed vector node)]
      (walk-leaves v (conj path (str i)) f))
    (and (sequential? node) (not (string? node)))
    (doseq [[i v] (map-indexed vector node)]
      (walk-leaves v (conj path (str i)) f))
    (map? node)
    (doseq [k (okeys node)]
      (walk-leaves (get node k) (conj path k) f))
    :else (f node path)))

(defn struct-match
  "Partial structural match: every leaf of `check` must match `base` at its
   path. Returns {:ok true} or {:ok false :path .. :expected .. :actual ..}."
  [check base]
  (let [result (atom {:ok true})]
    (walk-leaves
     check []
     (fn [val path]
       (when (:ok @result)
         (let [baseval (mt-getpath base path)
               present (not= baseval MISSING)
               cmp (if present baseval nil)]
           (cond
             (and present (deep-eq baseval val)) nil
             (and (= val UNDEFMARK) (not present)) nil
             (and (= val EXISTSMARK) present (not= baseval JNULL) (some? baseval)) nil
             (not (matchval val cmp))
             (reset! result {:ok false :path path :expected val :actual cmp}))))))
    @result))
