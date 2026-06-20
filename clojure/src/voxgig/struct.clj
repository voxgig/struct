;; Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
;;
;; Voxgig Struct
;; =============
;;
;; Utility functions to manipulate in-memory JSON-like data structures.
;; This Clojure version is a faithful port of the canonical TypeScript
;; implementation (typescript/src/StructUtility.ts), following the same
;; "by-example" design and logic. To preserve the reference-stable, in-place
;; mutation semantics the algorithm depends on, nodes are represented by
;; mutable Java collections: java.util.LinkedHashMap for maps (insertion
;; ordered, like a JS object) and java.util.ArrayList for lists. The Clojure
;; `nil` plays the role of both the canonical `undefined` and JSON `null`
;; (Group A/B rules, per design/UNDEF_SPEC.md, recover the distinction where
;; it matters). The library has zero third-party runtime dependencies.

(ns voxgig.struct
  (:refer-clojure :exclude [merge filter flatten replace]))

(import '(java.util LinkedHashMap ArrayList List Map)
        '(java.util.regex Pattern Matcher))

;; ---------------------------------------------------------------------------
;; String / mode / type constants
;; ---------------------------------------------------------------------------

(def ^:const S-MKEYPRE "key:pre")
(def ^:const S-MKEYPOST "key:post")
(def ^:const S-MVAL "val")
(def ^:const S-MKEY "key")

(def ^:const M_KEYPRE 1)
(def ^:const M_KEYPOST 2)
(def ^:const M_VAL 4)

(def MODENAME {M_VAL "val" M_KEYPRE "key:pre" M_KEYPOST "key:post"})
(def ^:private MODE-TO-NUM {S-MKEYPRE M_KEYPRE S-MKEYPOST M_KEYPOST S-MVAL M_VAL})
(def ^:private PLACEMENT {M_VAL "value" M_KEYPRE S-MKEY M_KEYPOST S-MKEY})

(def ^:const S-DKEY "$KEY")
(def ^:const S-BANNO "`$ANNO`")
(def ^:const S-DTOP "$TOP")
(def ^:const S-DERRS "$ERRS")
(def ^:const S-DSPEC "$SPEC")
(def ^:const S-BEXACT "`$EXACT`")
(def ^:const S-BVAL "`$VAL`")
(def ^:const S-BKEY "`$KEY`")

(def ^:const S-MT "")
(def ^:const S-BT "`")
(def ^:const S-DS "$")
(def ^:const S-DT ".")
(def ^:const S-CM ",")
(def ^:const S-CN ":")
(def ^:const S-FS "/")
(def ^:const S-KEY "KEY")
(def ^:const S-VIZ ": ")

(def ^:const S-string "string")
(def ^:const S-number "number")
(def ^:const S-integer "integer")
(def ^:const S-decimal "decimal")
(def ^:const S-boolean "boolean")
(def ^:const S-null "null")
(def ^:const S-nil "nil")
(def ^:const S-map "map")
(def ^:const S-list "list")
(def ^:const S-object "object")
(def ^:const S-function "function")
(def ^:const S-instance "instance")
(def ^:const S-any "any")
(def ^:const S-scalar "scalar")
(def ^:const S-node "node")
(def ^:const S-base "base")

;; Type bit flags (mirroring the canonical TypeScript layout exactly).
(def ^:const T_any (- (bit-shift-left 1 31) 1))
(def ^:const T_noval (bit-shift-left 1 30))
(def ^:const T_boolean (bit-shift-left 1 29))
(def ^:const T_decimal (bit-shift-left 1 28))
(def ^:const T_integer (bit-shift-left 1 27))
(def ^:const T_number (bit-shift-left 1 26))
(def ^:const T_string (bit-shift-left 1 25))
(def ^:const T_function (bit-shift-left 1 24))
(def ^:const T_symbol (bit-shift-left 1 23))
(def ^:const T_null (bit-shift-left 1 22))
(def ^:const T_list (bit-shift-left 1 14))
(def ^:const T_map (bit-shift-left 1 13))
(def ^:const T_instance (bit-shift-left 1 12))
(def ^:const T_scalar (bit-shift-left 1 7))
(def ^:const T_node (bit-shift-left 1 6))

(def ^:private TYPENAME
  [S-any S-nil S-boolean S-decimal S-integer S-number S-string S-function
   "symbol" S-null "" "" "" "" "" "" "" S-list S-map S-instance
   "" "" "" "" S-scalar S-node])

;; Private markers (compared by identity).
(def SKIP (doto (LinkedHashMap.) (.put "`$SKIP`" true)))
(def DELETE (doto (LinkedHashMap.) (.put "`$DELETE`" true)))

(def ^:const MAXDEPTH 32)

;; Path processing regexes.
(def ^:private R-META-PATH (Pattern/compile "^([^$]+)\\$([=~])(.+)$"))
(def ^:private R-DOUBLE-DOLLAR (Pattern/compile "\\$\\$"))
(def ^:private R-INJECT-FULL (Pattern/compile "^`(\\$[A-Z]+|[^`]*)[0-9]*`$"))
(def ^:private R-INJECT-PART (Pattern/compile "`([^`]*)`"))
(def ^:private R-TRANSFORM-NAME (Pattern/compile "`\\$([A-Z]+)`"))

;; ---------------------------------------------------------------------------
;; Mutable-collection helpers
;; ---------------------------------------------------------------------------

(defn- lhm ^LinkedHashMap [] (LinkedHashMap.))
(defn- alist ^ArrayList [] (ArrayList.))

(defn- alist-of ^ArrayList [coll]
  (let [a (ArrayList.)]
    (doseq [x coll] (.add a x))
    a))

;; The injection state object. Distinct type so it is never mistaken for a
;; data map. Backed by a mutable HashMap of keyword -> value.
(deftype Inj [^java.util.HashMap m])

(defn- inj? [x] (instance? Inj x))
(defn- ig [^Inj inj k] (.get ^java.util.HashMap (.-m inj) k))
(defn- is! [^Inj inj k v] (.put ^java.util.HashMap (.-m inj) k v) v)

;; Forward declarations.
(declare getprop getelem setprop delprop isnode ismap islist iskey isfunc
         isempty keysof items size slice clone typify typename stringify
         pathify join merge walk getpath setpath inject _injectstr _lookup
         strkey flatten filter getdef haskey escre
         re_compile re_find re_find_all re_replace re_test
         _injecthandler _validatehandler _invalidTypeMsg
         inj-descend inj-child inj-setval
         checkPlacement injectorArgs injectChild
         validate transform select jsonify FORMATTER)

;; ---------------------------------------------------------------------------
;; Low-level numeric / key helpers
;; ---------------------------------------------------------------------------

(defn- jbool? [v] (instance? Boolean v))
(defn- jdouble? [v] (or (instance? Double v) (instance? Float v)))
(defn- jint? [v] (and (number? v) (not (jbool? v)) (not (jdouble? v))))

(defn- parse-long-strict
  "Mirror Python int(key): coerce numbers (floor), parse integer strings."
  [k]
  (cond
    (jbool? k) nil
    (jint? k) (long k)
    (jdouble? k) (long (Math/floor (double k)))
    (string? k) (try (Long/parseLong (.trim ^String k)) (catch Exception _ nil))
    :else nil))

;; ---------------------------------------------------------------------------
;; Minor utilities
;; ---------------------------------------------------------------------------

(defn isnode [val] (or (instance? Map val) (instance? List val)))
(defn ismap [val] (instance? Map val))
(defn islist [val] (instance? List val))

(defn iskey [key]
  (cond
    (string? key) (pos? (count key))
    (jbool? key) false
    (number? key) true
    :else false))

(defn isfunc [val] (fn? val))

(defn getdef [val alt] (if (nil? val) alt val))

(defn- map-keys
  "Insertion-ordered keys of a Java Map (as the stored key objects)."
  [^Map m] (seq (.keySet m)))

(defn keysof [val]
  (cond
    (not (isnode val)) []
    (ismap val) (vec (sort (map str (map-keys val))))
    :else (mapv str (range (.size ^List val)))))

(defn size [val]
  (cond
    (nil? val) 0
    (islist val) (.size ^List val)
    (ismap val) (.size ^Map val)
    (string? val) (count val)
    (jbool? val) (if val 1 0)
    (number? val) (long (Math/floor (double val)))
    :else 0))

(defn strkey
  ([] S-MT)
  ([key]
   (cond
     (nil? key) S-MT
     (string? key) key
     (jbool? key) S-MT
     (jint? key) (str (long key))
     (jdouble? key) (str (long (double key)))
     (number? key) (str key)
     :else S-MT)))

(defn isempty [val]
  (cond
    (nil? val) true
    (= val S-MT) true
    (and (islist val) (zero? (.size ^List val))) true
    (and (ismap val) (zero? (.size ^Map val))) true
    :else false))

(defn- clz32 [n]
  (if (<= (long n) 0) 32 (Integer/numberOfLeadingZeros (unchecked-int (long n)))))

(defn typename [t] (getelem TYPENAME (clz32 t) (nth TYPENAME 0)))

(def ^:private TYPIFY-NOARG (Object.))
(def NOARG TYPIFY-NOARG)

(defn typify
  ([] T_noval)
  ([value]
   (cond
     (identical? value TYPIFY-NOARG) T_noval
     (nil? value) (bit-or T_scalar T_null)
     (jbool? value) (bit-or T_scalar T_boolean)
     (jint? value) (bit-or T_scalar T_number T_integer)
     (jdouble? value) (if (Double/isNaN (double value))
                        T_noval
                        (bit-or T_scalar T_number T_decimal))
     (number? value) (bit-or T_scalar T_number T_integer)
     (string? value) (bit-or T_scalar T_string)
     (isfunc value) (bit-or T_scalar T_function)
     (islist value) (bit-or T_node T_list)
     (ismap value) (bit-or T_node T_map)
     :else (bit-or T_node T_instance))))

(defn getelem
  ([val key] (getelem val key nil))
  ([val key alt]
   (let [out (atom nil)]
     (if (or (nil? val) (nil? key))
       alt
       (do
         (when (islist val)
           (let [ks (str key)]
             (when (re-matches #"-?[0-9]+" ks)
               (let [len (.size ^List val)
                     nk0 (Long/parseLong ks)
                     nk (if (neg? nk0) (+ len nk0) nk0)]
                 (when (and (<= 0 nk) (< nk len))
                   (reset! out (.get ^List val (int nk))))))))
         (if (nil? @out)
           (if (isfunc alt) (alt) alt)
           @out))))))

(defn getprop
  ([val key] (getprop val key nil))
  ([val key alt]
   (if (or (nil? val) (nil? key))
     alt
     (let [out (cond
                 (ismap val) (let [skey (str key)]
                               (if (.containsKey ^Map val skey)
                                 (.get ^Map val skey) alt))
                 (islist val) (let [ki (parse-long-strict key)]
                                (if (and ki (<= 0 ki) (< ki (.size ^List val)))
                                  (.get ^List val (int ki)) alt))
                 :else alt)]
       (if (nil? out) alt out)))))

(defn- _lookup [val key]
  (cond
    (or (nil? val) (nil? key)) nil
    (ismap val) (let [skey (str key)]
                  (if (.containsKey ^Map val skey) (.get ^Map val skey) nil))
    (islist val) (let [ki (parse-long-strict key)]
                   (if (and ki (<= 0 ki) (< ki (.size ^List val)))
                     (.get ^List val (int ki)) nil))
    :else nil))

(defn haskey
  ([val] (haskey val nil))
  ([val key] (some? (getprop val key))))

(defn items
  ([val] (items val nil))
  ([val apply]
   (if-not (isnode val)
     []
     (let [ks (keysof val)
           out (mapv (fn [k]
                       [k (if (ismap val)
                            (.get ^Map val k)
                            (.get ^List val (int (Long/parseLong k))))])
                     ks)]
       (if apply (mapv apply out) out)))))

(defn flatten
  ([lst] (flatten lst 1))
  ([lst depth]
   (let [depth (if (nil? depth) 1 depth)]
     (if-not (islist lst)
       lst
       (let [out (alist)]
         (doseq [item lst]
           (if (and (islist item) (> depth 0))
             (doseq [x (flatten item (dec depth))] (.add out x))
             (.add out item)))
         out)))))

(defn filter [val check]
  (let [all (items val)
        out (alist)]
    (doseq [it all] (when (check it) (.add out (nth it 1))))
    out))

(defn setprop [parent key val]
  (when (iskey key)
    (cond
      (ismap parent) (.put ^Map parent (str key) val)
      (islist parent)
      (let [ki (parse-long-strict key)]
        (when ki
          (let [^List p parent len (.size p)]
            (if (>= ki 0)
              (let [ki (min ki len)]
                (if (>= ki len) (.add p val) (.set p (int ki) val)))
              (.add p 0 val)))))))
  parent)

(defn delprop [parent key]
  (when (iskey key)
    (cond
      (ismap parent) (.remove ^Map parent (str key))
      (islist parent)
      (let [ki (parse-long-strict key)]
        (when ki
          (let [^List p parent]
            (when (and (<= 0 ki) (< ki (.size p)))
              (.remove p (int ki))))))))
  parent)

(defn slice
  ([val] (slice val nil nil false))
  ([val start] (slice val start nil false))
  ([val start end] (slice val start end false))
  ([val start end mutate]
   (cond
     (and (number? val) (not (jbool? val)))
     (let [lo start
           hi (when (some? end) (dec (long end)))]
       (cond
         (and (some? hi) (> (double val) (double hi))) hi
         (and (some? lo) (< (double val) (double lo))) lo
         :else val))

     (or (islist val) (string? val))
     (let [vlen (size val)
           start (if (and (nil? start) (some? end)) 0 start)]
       (if (nil? start)
         val
         (let [[start end]
               (cond
                 (< start 0) [0 (let [e (+ vlen start)] (if (< e 0) 0 e))]
                 (some? end) [start (cond (< end 0) (let [e (+ vlen end)] (if (< e 0) 0 e))
                                          (< vlen end) vlen
                                          :else end)]
                 :else [start vlen])
               start (if (< vlen start) vlen start)]
           (if (and (> start -1) (<= start end) (<= end vlen))
             (cond
               (and (islist val) mutate)
               (let [^List p val]
                 (loop [i 0 j start]
                   (when (< j end) (.set p i (.get p j)) (recur (inc i) (inc j))))
                 (while (> (.size p) (- end start)) (.remove p (int (dec (.size p)))))
                 p)
               (islist val) (alist-of (subvec (vec val) start end))
               (string? val) (subs val start end)
               :else val)
             (cond
               (and (islist val) mutate) (let [^List p val] (.clear p) p)
               (islist val) (alist)
               (string? val) S-MT
               :else val)))))
     :else val)))

;; ---------------------------------------------------------------------------
;; Regex utility (uniform re_* API)
;; ---------------------------------------------------------------------------

(defn- ->pattern ^Pattern [p]
  (if (instance? Pattern p) p (Pattern/compile (str p))))

(defn re_compile
  ([p] (->pattern p))
  ([p _flags] (->pattern p)))

(defn- match-groups [^Matcher m]
  (vec (for [i (range (inc (.groupCount m)))]
         (let [g (.group m (int i))] (if (nil? g) "" g)))))

(defn re_find [p input]
  (let [m (.matcher (->pattern p) input)]
    (when (.find m) (match-groups m))))

(defn re_find_all [p input]
  (let [m (.matcher (->pattern p) input) out (alist)]
    (while (.find m)
      (.add out (match-groups m))
      (when (= "" (.group m)) ))
    out))

(defn re_test [p input] (.find (.matcher (->pattern p) input)))

(defn re_replace [p input replacement]
  (let [m (.matcher (->pattern p) input) sb (StringBuffer.)]
    (if (isfunc replacement)
      (do (while (.find m)
            (.appendReplacement m sb (Matcher/quoteReplacement (str (replacement (match-groups m))))))
          (.appendTail m sb)
          (.toString sb))
      ;; String replacement: translate $& -> $0 (Java group ref); leave $1.. as-is.
      (let [jrepl (clojure.string/replace (str replacement) "$&" "$0")]
        (.replaceAll (.matcher (->pattern p) input) jrepl)))))

(defn escre [s]
  (let [s (if (nil? s) S-MT s)]
    (re_replace (Pattern/compile "[.*+?^${}()|\\[\\]\\\\]") s
                (fn [g] (str "\\" (nth g 0))))))

(defn re_escape [s] (escre s))

(def ^:private URL-UNRESERVED
  (set (concat (map char (range (int \A) (inc (int \Z))))
               (map char (range (int \a) (inc (int \z))))
               (map char (range (int \0) (inc (int \9))))
               [\- \_ \. \! \~ \* \' \( \)])))

(defn escurl
  "Escape a URL component, matching JS encodeURIComponent."
  [s]
  (let [s (if (nil? s) S-MT (str s))
        sb (StringBuilder.)]
    (doseq [b (.getBytes ^String s "UTF-8")]
      (let [c (char (bit-and b 0xff))]
        (if (contains? URL-UNRESERVED c)
          (.append sb c)
          (.append sb (format "%%%02X" (bit-and b 0xff))))))
    (.toString sb)))

;; ---------------------------------------------------------------------------
;; JSON-ish serialization (stringify / jsonify) and clone
;; ---------------------------------------------------------------------------

(defn- num->json [v]
  (cond
    (jdouble? v) (let [d (double v)]
                   (cond
                     (or (Double/isNaN d) (Double/isInfinite d)) "null"
                     (== d (Math/floor d)) (str (long d))
                     :else (str d)))
    :else (str v)))

(defn- esc-json-str [^String s]
  (let [sb (StringBuilder.)]
    (.append sb \")
    (doseq [c s]
      (cond
        (= c \") (.append sb "\\\"")
        (= c \\) (.append sb "\\\\")
        (= c \newline) (.append sb "\\n")
        (= c \return) (.append sb "\\r")
        (= c \tab) (.append sb "\\t")
        (< (int c) 32) (.append sb (format "\\u%04x" (int c)))
        :else (.append sb c)))
    (.append sb \")
    (.toString sb)))

(defn- json-encode
  "Encode val as JSON. opts: :sort? sort map keys; :indent (nil=compact)."
  [val opts]
  (let [{:keys [sort? indent]} opts]
    (letfn [(enc [v level]
              (cond
                (nil? v) "null"
                (jbool? v) (if v "true" "false")
                (number? v) (num->json v)
                (string? v) (esc-json-str v)
                (isfunc v) "null"
                (islist v)
                (let [items (vec v)]
                  (if (empty? items)
                    "[]"
                    (if indent
                      (let [pad (apply str (repeat (* indent (inc level)) " "))
                            cpad (apply str (repeat (* indent level) " "))]
                        (str "[\n" (clojure.string/join ",\n"
                                     (map #(str pad (enc % (inc level))) items))
                             "\n" cpad "]"))
                      (str "[" (clojure.string/join "," (map #(enc % (inc level)) items)) "]"))))
                (ismap v)
                (let [ks (let [k (vec (map str (map-keys v)))] (if sort? (vec (sort k)) k))]
                  (if (empty? ks)
                    "{}"
                    (if indent
                      (let [pad (apply str (repeat (* indent (inc level)) " "))
                            cpad (apply str (repeat (* indent level) " "))]
                        (str "{\n" (clojure.string/join ",\n"
                                     (map #(str pad (esc-json-str %) ": " (enc (.get ^Map v %) (inc level))) ks))
                             "\n" cpad "}"))
                      (str "{" (clojure.string/join ","
                                 (map #(str (esc-json-str %) ":" (enc (.get ^Map v %) (inc level))) ks))
                           "}"))))
                :else (esc-json-str (str v))))]
      (enc val 0))))

(defn pad
  ([s] (pad s nil nil))
  ([s padding] (pad s padding nil))
  ([s padding padchar]
   (let [s (if (nil? s) "null" (if (string? s) s (stringify s)))
         padding (if (nil? padding) 44 padding)
         padchar (if (nil? padchar) " " (subs (str padchar " ") 0 1))]
     (if (> padding -1)
       (let [n (- padding (count s))]
         (if (> n 0) (str s (apply str (repeat n padchar))) s))
       (let [n (- (- padding) (count s))]
         (if (> n 0) (str (apply str (repeat n padchar)) s) s))))))

(defn stringify
  ([] S-MT)
  ([val] (stringify val nil nil))
  ([val maxlen] (stringify val maxlen nil))
  ([val maxlen pretty]
   (let [pretty (boolean pretty)
         valstr (if (string? val)
                  val
                  (try
                    (json-encode val {:sort? true})
                    (catch Throwable _ "__STRINGIFY_FAILED__")))
         ;; detect cyclic / failed encode already returns marker via exception only
         valstr (if (string? val) val (clojure.string/replace valstr "\"" ""))
         valstr (if (and (some? maxlen) (> maxlen -1))
                  (let [js (subs valstr 0 (min maxlen (count valstr)))]
                    (if (< maxlen (count valstr)) (str (subs js 0 (- maxlen 3)) "...") valstr))
                  valstr)]
     (if pretty
       (let [colors [81 118 213 39 208 201 45 190 129 51 160 121 226 33 207 69]
             c (mapv #(str "[38;5;" % "m") colors)
             r "[0m"]
         (loop [chs (seq valstr) d 0 o (nth c 0) t (nth c 0)]
           (if (empty? chs)
             (str t r)
             (let [ch (first chs)]
               (cond
                 (or (= ch \{) (= ch \[))
                 (let [d (inc d) o (nth c (mod d (count c)))]
                   (recur (rest chs) d o (str t o ch)))
                 (or (= ch \}) (= ch \]))
                 (let [t (str t o ch) d (dec d) o (nth c (mod d (count c)))]
                   (recur (rest chs) d o t))
                 :else (recur (rest chs) d o (str t o ch)))))))
       valstr))))

;; Re-do stringify cyclic detection: json-encode can recurse infinitely on a
;; self-referential map. Guard by catching StackOverflowError above (Throwable).

(defn clone [val]
  (cond
    (nil? val) nil
    (ismap val) (let [o (lhm)] (doseq [k (map-keys val)] (.put o k (clone (.get ^Map val k)))) o)
    (islist val) (let [a (alist)] (doseq [x val] (.add a (clone x))) a)
    :else val))

(defn jsonify
  ([val] (jsonify val nil))
  ([val flags]
   (if (nil? val)
     S-null
     (let [indent (getprop flags "indent" 2)
           json-str (try
                      (if (and indent (> indent 0))
                        (json-encode val {:indent indent})
                        (json-encode val {}))
                      (catch Throwable _ S-null))
           offset (getprop flags "offset" 0)]
       (if (and json-str (> offset 0))
         (let [lines (clojure.string/split-lines json-str)
               padded (map (fn [n] (pad (nth n 1) (- (- offset) (size (nth n 1))))) (items (alist-of (rest lines))))]
           (str "{\n" (clojure.string/join "\n" padded)))
         (or json-str S-null))))))

;; ---------------------------------------------------------------------------
;; join / pathify
;; ---------------------------------------------------------------------------

(defn join
  ([arr] (join arr nil nil))
  ([arr sep] (join arr sep nil))
  ([arr sep url]
   (if-not (islist arr)
     S-MT
     (let [sepdef (if (or (nil? sep)) S-CM sep)
           sepre (if (= 1 (size sepdef)) (escre sepdef) nil)
           sarr (size arr)
           filtered (keep-indexed (fn [i s] (when (and (string? s) (not= s S-MT)) [i s])) arr)
           result (alist)]
       (doseq [[idx s0] filtered]
         (let [s (if (and sepre (not= sepre S-MT))
                   (cond
                     (and url (= idx 0))
                     (re_replace (Pattern/compile (str sepre "+$")) s0 (fn [_] S-MT))
                     :else
                     (let [s (if (> idx 0)
                               (re_replace (Pattern/compile (str "^" sepre "+")) s0 (fn [_] S-MT))
                               s0)
                           s (if (or (< idx (dec sarr)) (not url))
                               (re_replace (Pattern/compile (str sepre "+$")) s (fn [_] S-MT))
                               s)]
                       (re_replace (Pattern/compile (str "([^" sepre "])" sepre "+([^" sepre "])"))
                                   s (fn [g] (str (nth g 1) sepdef (nth g 2))))))
                   s0)]
           (when (not= s S-MT) (.add result s))))
       (clojure.string/join sepdef (vec result))))))

(defn joinurl [sarr] (join sarr "/" true))

(defn replace [s from to]
  (let [ts (typify s)
        rs (cond
             (zero? (bit-and T_string ts)) (stringify s)
             (pos? (bit-and (bit-or T_noval T_null) ts)) S-MT
             :else (stringify s))]
    (if (string? from)
      (clojure.string/replace rs from (str to))
      (re_replace from rs (str to)))))

(defn pathify
  ([] (pathify TYPIFY-NOARG nil nil))
  ([val] (pathify val nil nil))
  ([val startin] (pathify val startin nil))
  ([val startin endin]
   (let [absent? (identical? val TYPIFY-NOARG)
         val (if absent? nil val)
         path (cond (islist val) (vec val)
                    (iskey val) [val]
                    :else nil)
         start (cond (nil? startin) 0 (> startin -1) startin :else 0)
         end (cond (nil? endin) 0 (> endin -1) endin :else 0)
         pathstr
         (when (and (some? path) (>= start 0))
           (let [path (subvec path (min start (count path)) (max 0 (- (count path) end)))]
             (if (zero? (count path))
               "<root>"
               (let [fp (clojure.core/filter iskey path)
                     mapped (map (fn [p]
                                   (if (and (number? p) (not (jbool? p)))
                                     (str (long p))
                                     (clojure.string/replace (str p) "." S-MT)))
                                 fp)]
                 (clojure.string/join S-DT mapped)))))]
     (if (nil? pathstr)
       (str "<unknown-path" (if absent? S-MT (str S-CN (stringify val 47))) ">")
       pathstr))))

;; ---------------------------------------------------------------------------
;; walk / merge
;; ---------------------------------------------------------------------------

(defn walk
  ([val] (walk val {}))
  ([val arg]
   (let [{:keys [before after maxdepth key parent path pool]} (if (map? arg) arg {:after arg})
         pool (if (nil? pool) (doto (alist) (.add (alist))) pool)
         path (if (nil? path) (.get ^List pool 0) path)
         depth (.size ^List path)
         out (if (nil? before) val (before key val parent path))
         md (if (and (some? maxdepth) (>= maxdepth 0)) maxdepth MAXDEPTH)]
     (if (or (= md 0) (and (> md 0) (<= md depth)))
       out
       (do
         (when (isnode out)
           (let [child-depth (inc depth)]
             (while (<= (.size ^List pool) child-depth)
               (.add ^List pool (alist-of (repeat (.size ^List pool) nil))))
             (let [^List child-path (.get ^List pool child-depth)]
               (dotimes [i depth] (.set child-path (int i) (.get ^List path (int i))))
               (doseq [[ckey child] (items out)]
                 (.set child-path (int depth) (str ckey))
                 (let [result (walk child {:before before :after after :maxdepth md
                                           :key ckey :parent out :path child-path :pool pool})]
                   (cond
                     (ismap out) (.put ^Map out (str ckey) result)
                     (islist out) (.set ^List out (int (Long/parseLong (str ckey))) result)))))))
         (if (nil? after) out (after key out parent path)))))))

(defn merge
  ([objs] (merge objs nil))
  ([objs maxdepth]
   (let [md (if (nil? maxdepth) MAXDEPTH (max maxdepth 0))]
     (if-not (islist objs)
       objs
       (let [lenlist (.size ^List objs)]
         (cond
           (= lenlist 0) nil
           (= lenlist 1) (.get ^List objs 0)
           :else
           (let [out (atom (getprop objs 0 (lhm)))]
             (doseq [oI (range 1 lenlist)]
               (let [obj (.get ^List objs (int oI))]
                 (if-not (isnode obj)
                   (reset! out obj)
                   (let [cur (alist-of [@out])
                         dst (alist-of [@out])
                         grow! (fn [^ArrayList a n]
                                 (while (<= (.size a) n) (.add a nil)))
                         before (fn [key val _parent path]
                                  (let [pI (size path)]
                                    (cond
                                      (<= md pI)
                                      (do (grow! cur pI) (.set cur (int pI) val)
                                          (when (> pI 0) (setprop (.get cur (int (dec pI))) key val))
                                          nil)
                                      (not (isnode val))
                                      (do (grow! cur pI) (.set cur (int pI) val) val)
                                      :else
                                      (do (grow! dst pI) (grow! cur pI)
                                          (.set dst (int pI) (if (> pI 0) (getprop (.get dst (int (dec pI))) key) (.get dst (int pI))))
                                          (let [tval (.get dst (int pI))]
                                            (cond
                                              (nil? tval) (do (.set cur (int pI) (if (islist val) (alist) (lhm))) val)
                                              (or (and (islist val) (islist tval)) (and (ismap val) (ismap tval)))
                                              (do (.set cur (int pI) tval) val)
                                              :else (do (.set cur (int pI) val) nil)))))))
                         after (fn [key _val _parent path]
                                 (let [cI (size path)]
                                   (if (< cI 1)
                                     (if (> (.size cur) 0) (.get cur 0) _val)
                                     (let [target (when (< (dec cI) (.size cur)) (.get cur (int (dec cI))))
                                           value (when (< cI (.size cur)) (.get cur (int cI)))]
                                       (setprop target key value)
                                       value))))]
                     (reset! out (walk obj {:before before :after after}))))))
             (when (= md 0)
               (let [o (getprop objs (dec lenlist) nil)]
                 (reset! out (cond (islist o) (alist) (ismap o) (lhm) :else o))))
             @out)))))))

;; ---------------------------------------------------------------------------
;; getpath / setpath
;; ---------------------------------------------------------------------------

(defn getpath
  ([store path] (getpath store path nil))
  ([store path injdef]
   (let [parts (cond
                 (islist path) (alist-of path)
                 (string? path) (alist-of (.split ^String path "\\." -1))
                 (and (number? path) (not (jbool? path))) (alist-of [(strkey path)])
                 :else nil)]
     (if (nil? parts)
       nil
       (let [is-inj (inj? injdef)
             base (if is-inj (ig injdef :base) (when injdef (getprop injdef S-base)))
             dparent (if is-inj (ig injdef :dparent) (when injdef (getprop injdef "dparent")))
             inj-meta (if is-inj (ig injdef :meta) (when injdef (getprop injdef "meta")))
             inj-key (if is-inj (ig injdef :key) (when injdef (getprop injdef "key")))
             dpath (if is-inj (ig injdef :dpath) (when injdef (getprop injdef "dpath")))
             src (if base (getprop store base store) store)
             numparts (size parts)
             val (atom store)]
         (cond
           (or (nil? path) (nil? store) (and (= numparts 1) (= (.get parts 0) S-MT)) (= numparts 0))
           (reset! val src)

           (> numparts 0)
           (do
             (when (= numparts 1)
               (reset! val (getprop store (.get parts 0))))
             (when-not (isfunc @val)
               (reset! val src)
               (let [m (when (string? (.get parts 0)) (re_find R-META-PATH (.get parts 0)))]
                 (when (and m inj-meta)
                   (reset! val (getprop inj-meta (nth m 1)))
                   (.set parts 0 (nth m 3))))
               (loop [pI 0]
                 (when (and (some? @val) (< pI numparts))
                   (let [raw (.get parts (int pI))
                         part (cond
                                (and injdef (= raw S-DKEY)) (if (some? inj-key) inj-key raw)
                                (and (string? raw) (.startsWith ^String raw "$GET:"))
                                (stringify (getpath src (slice raw 5 -1)))
                                (and (string? raw) (.startsWith ^String raw "$REF:"))
                                (stringify (getpath (getprop store S-DSPEC) (slice raw 5 -1)))
                                (and injdef (string? raw) (.startsWith ^String raw "$META:"))
                                (stringify (getpath inj-meta (slice raw 6 -1)))
                                :else raw)
                         part (if (string? part)
                                (re_replace R-DOUBLE-DOLLAR part (fn [_] "$"))
                                (strkey part))]
                     (if (= part S-MT)
                       (let [[ascends pI2]
                             (loop [a 0 p pI]
                               (if (and (< (inc p) (.size parts)) (= (.get parts (int (inc p))) S-MT))
                                 (recur (inc a) (inc p))
                                 [a p]))]
                         (if (and injdef (> ascends 0))
                           (let [last? (= pI2 (dec (.size parts)))
                                 ascends (if last? (dec ascends) ascends)]
                             (if (= ascends 0)
                               (do (reset! val dparent) (recur (inc pI2)))
                               (let [fullpath (flatten (alist-of [(slice dpath (- ascends)) (alist-of (subvec (vec parts) (inc pI2)))]))]
                                 (reset! val (if (<= ascends (size dpath)) (getpath store fullpath) nil)))))
                           (do (reset! val dparent) (recur (inc pI2)))))
                       (do (reset! val (getprop @val part)) (recur (inc pI))))))))))
         (let [handler (if is-inj (ig injdef :handler) (when injdef (getprop injdef "handler")))]
           (when (and handler (isfunc handler))
             (let [ref (pathify path)]
               (reset! val (handler injdef @val ref store)))))
         @val)))))

(defn setpath
  ([store path val] (setpath store path val nil))
  ([store path val injdef]
   (let [ptype (typify path)
         parts (cond
                 (pos? (bit-and T_list ptype)) (alist-of path)
                 (pos? (bit-and T_string ptype)) (alist-of (.split ^String path "\\." -1))
                 (pos? (bit-and T_number ptype)) (alist-of [path])
                 :else nil)]
     (if (nil? parts)
       nil
       (let [base (when injdef (getprop injdef S-base))
             numparts (size parts)
             parent (atom (if base (getprop store base store) store))]
         (doseq [pI (range (dec numparts))]
           (let [pkey (getelem parts pI)
                 np (getprop @parent pkey)
                 np (if-not (isnode np)
                      (let [next-part (getelem parts (inc pI))
                            nn (if (pos? (bit-and T_number (typify next-part))) (alist) (lhm))]
                        (setprop @parent pkey nn) nn)
                      np)]
             (reset! parent np)))
         (if (identical? DELETE val)
           (delprop @parent (getelem parts -1))
           (setprop @parent (getelem parts -1) val))
         @parent)))))

;; ---------------------------------------------------------------------------
;; Injection state
;; ---------------------------------------------------------------------------

(defn- new-inj [fields]
  (let [m (java.util.HashMap.)]
    (doseq [[k v] fields] (.put m k v))
    (Inj. m)))

(defn- inj-descend [^Inj inj]
  (let [meta (ig inj :meta)
        d (.get ^Map meta "__d")]
    (.put ^Map meta "__d" (inc (if (nil? d) 0 d)))
    (let [path (ig inj :path)
          parentkey (getelem path -2)
          dparent (ig inj :dparent)
          dpath (ig inj :dpath)]
      (if (nil? dparent)
        (when (> (size dpath) 1)
          (is! inj :dpath (alist-of (concat dpath [parentkey]))))
        (when (some? parentkey)
          (is! inj :dparent (getprop dparent parentkey))
          (let [lastpart (getelem dpath -1)]
            (if (= lastpart (str "$:" parentkey))
              (is! inj :dpath (slice dpath -1))
              (is! inj :dpath (alist-of (concat dpath [parentkey]))))))))
    (ig inj :dparent)))

(defn- inj-child [^Inj inj keyI keys]
  (let [key (strkey (nth (vec keys) keyI))
        val (ig inj :val)
        cinj (new-inj
              {:mode (ig inj :mode) :full (ig inj :full) :keyI keyI :keys keys :key key
               :val (getprop val key) :parent val
               :path (alist-of (concat (ig inj :path) [key]))
               :nodes (alist-of (concat (ig inj :nodes) [val]))
               :handler (ig inj :handler) :errs (ig inj :errs) :meta (ig inj :meta)
               :base (ig inj :base) :modify (ig inj :modify)})]
    (is! cinj :prior inj)
    (is! cinj :dpath (alist-of (ig inj :dpath)))
    (is! cinj :dparent (ig inj :dparent))
    (is! cinj :extra (ig inj :extra))
    (is! cinj :root (ig inj :root))
    cinj))

(defn- inj-setval
  ([^Inj inj val] (inj-setval inj val nil))
  ([^Inj inj val ancestor]
   (let [[target key] (if (or (nil? ancestor) (< ancestor 2))
                        [(ig inj :parent) (ig inj :key)]
                        [(getelem (ig inj :nodes) (- ancestor)) (getelem (ig inj :path) (- ancestor))])]
     (if (nil? val)
       (delprop target key)
       (setprop target key val)))))

;; ---------------------------------------------------------------------------
;; inject
;; ---------------------------------------------------------------------------

(defn inject
  ([val store] (inject val store nil))
  ([val store injdef]
   (let [inj
         (if (inj? injdef)
           injdef
           (let [parent (doto (lhm) (.put S-DTOP val))
                 inj (new-inj
                      {:mode S-MVAL :full false :keyI 0 :keys (alist-of [S-DTOP]) :key S-DTOP
                       :val val :parent parent :path (alist-of [S-DTOP]) :nodes (alist-of [parent])
                       :handler _injecthandler :base S-DTOP
                       :modify (when injdef (getprop injdef "modify"))
                       :meta (getprop injdef "meta" (lhm))
                       :errs (getprop store S-DERRS (alist))})]
             (is! inj :dparent store)
             (is! inj :dpath (alist-of [S-DTOP]))
             (is! inj :root parent)
             (when (some? injdef)
               (when (getprop injdef "extra") (is! inj :extra (getprop injdef "extra")))
               (when (getprop injdef "handler") (is! inj :handler (getprop injdef "handler")))
               (when (getprop injdef "dparent") (is! inj :dparent (getprop injdef "dparent")))
               (when (getprop injdef "dpath") (is! inj :dpath (getprop injdef "dpath"))))
             inj))]
     (inj-descend inj)

     (let [val
           (cond
             (isnode val)
             (let [nodekeys (atom
                             (if (ismap val)
                               (let [ks (vec (map str (map-keys val)))
                                     normal (sort (clojure.core/filter #(not (.contains ^String % S-DS)) ks))
                                     trans (sort (clojure.core/filter #(.contains ^String % S-DS) ks))]
                                 (alist-of (concat normal trans)))
                               (alist-of (map str (range (.size ^List val))))))]
               (loop [nkI 0]
                 (when (< nkI (.size ^List @nodekeys))
                   (let [childinj (inj-child inj nkI @nodekeys)
                         nodekey (ig childinj :key)]
                     (is! childinj :mode S-MKEYPRE)
                     (let [prekey (_injectstr nodekey store childinj)]
                       (reset! nodekeys (ig childinj :keys))
                       (when (some? prekey)
                         (is! childinj :val (getprop val prekey))
                         (is! childinj :mode S-MVAL)
                         (inject (ig childinj :val) store childinj)
                         (reset! nodekeys (ig childinj :keys))
                         (is! childinj :mode S-MKEYPOST)
                         (_injectstr nodekey store childinj)
                         (reset! nodekeys (ig childinj :keys)))
                       (recur (inc (ig childinj :keyI)))))))
               val)

             (string? val)
             (do
               (is! inj :mode S-MVAL)
               (let [v (_injectstr val store inj)]
                 (when-not (identical? v SKIP) (inj-setval inj v))
                 v))

             :else val)]

       ;; Custom modification (runs after special commands).
       (when (and (ig inj :modify) (not (identical? val SKIP)))
         (let [mkey (ig inj :key) mparent (ig inj :parent) mval (getprop mparent mkey)]
           ((ig inj :modify) mval mkey mparent inj)))

       (is! inj :val val)

       (cond
         (and (nil? (ig inj :prior)) (some? (ig inj :root)) (haskey (ig inj :root) S-DTOP))
         (getprop (ig inj :root) S-DTOP)
         (and (= (ig inj :key) S-DTOP) (some? (ig inj :parent)) (haskey (ig inj :parent) S-DTOP))
         (getprop (ig inj :parent) S-DTOP)
         :else val)))))

(defn- _injecthandler [inj val ref store]
  (let [iscmd (and (isfunc val) (or (nil? ref) (and (string? ref) (.startsWith ^String ref S-DS))))]
    (cond
      iscmd (val inj val ref store)
      (and (= (ig inj :mode) S-MVAL) (ig inj :full)) (do (inj-setval inj val) val)
      :else val)))

(defn- _injectstr [val store inj]
  (if (or (not (string? val)) (= val S-MT))
    S-MT
    (let [m (re_find R-INJECT-FULL val)]
      (if m
        (do
          (when (inj? inj) (is! inj :full true))
          (let [pathref0 (nth m 1)
                pathref (if (> (count pathref0) 3)
                          (-> pathref0 (clojure.string/replace "$BT" S-BT) (clojure.string/replace "$DS" S-DS))
                          pathref0)]
            (getpath store pathref inj)))
        (let [out (re_replace R-INJECT-PART val
                              (fn [g]
                                (let [ref0 (nth g 1)
                                      ref (if (> (count ref0) 3)
                                            (-> ref0 (clojure.string/replace "$BT" S-BT) (clojure.string/replace "$DS" S-DS))
                                            ref0)]
                                  (when (inj? inj) (is! inj :full false))
                                  (let [found (getpath store ref inj)]
                                    (cond
                                      (nil? found) S-MT
                                      (string? found) (if (= found "__NULL__") "null" found)
                                      (isfunc found) found
                                      :else (try (json-encode found {}) (catch Throwable _ (stringify found))))))))]
          (if (and (inj? inj) (isfunc (ig inj :handler)))
            (do (is! inj :full true)
                ((ig inj :handler) inj out val store))
            out))))))

;; ---------------------------------------------------------------------------
;; Transform commands
;; ---------------------------------------------------------------------------

(defn- transform_DELETE [inj _val _ref _store]
  (delprop (ig inj :parent) (ig inj :key)) nil)

(defn- transform_COPY [inj _val _ref _store]
  (let [mode (ig inj :mode) key (ig inj :key)]
    (if (.startsWith ^String mode "key")
      key
      (let [dparent (ig inj :dparent) path (ig inj :path)
            out (if-not (isnode dparent)
                  (if (not= (size path) 2)
                    dparent
                    (if (parse-long-strict key) dparent nil))
                  (let [o (getprop dparent key)]
                    (if (and (nil? o) (some? key) (parse-long-strict key)) dparent o)))]
        (inj-setval inj out)
        out))))

(defn- transform_KEY [inj _val _ref _store]
  (let [mode (ig inj :mode) path (ig inj :path) parent (ig inj :parent)]
    (cond
      (= mode S-MKEYPRE) (ig inj :key)
      (not= mode S-MVAL) nil
      :else
      (let [keyspec (getprop parent S-BKEY)]
        (cond
          (some? keyspec) (do (delprop parent S-BKEY) (getprop (ig inj :dparent) keyspec))
          (and (ismap (ig inj :dparent)) (some? (ig inj :key)) (haskey (ig inj :dparent) (ig inj :key)))
          (getprop (ig inj :dparent) (ig inj :key))
          :else (let [meta (getprop parent S-BANNO)]
                  (getprop meta S-KEY (getprop path (- (size path) 2)))))))))

(defn- transform_ANNO [inj _val _ref _store]
  (delprop (ig inj :parent) S-BANNO) nil)

(defn- transform_MERGE [inj _val _ref _store]
  (let [mode (ig inj :mode) key (ig inj :key) parent (ig inj :parent)]
    (cond
      (= mode S-MKEYPRE) key
      (= mode S-MKEYPOST)
      (let [args0 (getprop parent key)
            args (if (islist args0) args0 (alist-of [args0]))]
        (delprop parent key)
        (merge (flatten (alist-of [(alist-of [parent]) args (alist-of [(clone parent)])])))
        key)
      (and (= mode S-MVAL) (islist parent))
      (if (and (= (strkey (ig inj :key)) "0") (> (size parent) 0))
        (do (.remove ^List parent (int 0)) (getprop parent 0))
        (getprop parent (ig inj :key)))
      :else nil)))

(defn- transform_EACH [inj _val _ref store]
  (let [keys_ (ig inj :keys) mode (ig inj :mode) path (ig inj :path)
        parent (ig inj :parent) nodes_ (ig inj :nodes)]
    (when (some? keys_)
      (slice keys_ 0 1 true))
    (if (or (not= mode S-MVAL) (nil? path) (nil? nodes_))
      nil
      (let [srcpath (when (> (size parent) 1) (.get ^List parent 1))
            child-tm (when (> (size parent) 2) (clone (.get ^List parent 2)))
            srcstore (getprop store (ig inj :base) store)
            src (getpath srcstore srcpath inj)
            tkey (getelem path -2)
            target (if (>= (.size ^List nodes_) 2) (.get ^List nodes_ (int (- (.size ^List nodes_) 2)))
                       (.get ^List nodes_ (int (dec (.size ^List nodes_)))))
            tval (alist)
            rval (atom (alist))]
        (when (isnode src)
          (if (islist src)
            (doseq [_ src] (.add tval (clone child-tm)))
            (doseq [k (map-keys src)]
              (let [cc (clone child-tm)]
                (when (ismap cc) (setprop cc S-BANNO (doto (lhm) (.put S-KEY k))))
                (.add tval cc))))
          (let [tcurrent (if (ismap src) (alist-of (map #(.get ^Map src %) (map-keys src))) src)]
            (when (> (size tval) 0)
              (let [ckey (getelem path -2)
                    tpath (if (> (count (vec path)) 0) (alist-of (subvec (vec path) 0 (dec (count (vec path))))) (alist))
                    dpath (alist-of [S-DTOP])]
                (when (and (string? srcpath) (not= srcpath S-MT))
                  (doseq [p (.split ^String srcpath "\\." -1)] (when (not= p S-MT) (.add dpath p))))
                (when (some? ckey) (.add dpath (str "$:" ckey)))
                (let [tcur (doto (lhm) (.put (str ckey) tcurrent))
                      tcur (if (> (size tpath) 1)
                             (let [pkey (getelem path -3 S-DTOP)]
                               (.add dpath (str "$:" pkey))
                               (doto (lhm) (.put (str pkey) tcur)))
                             tcur)
                      tinj (inj-child inj 0 (if (some? ckey) (alist-of [ckey]) (alist)))]
                  (is! tinj :path tpath)
                  (is! tinj :nodes (if (> (.size ^List nodes_) 0) (alist-of (subvec (vec nodes_) 0 (dec (count (vec nodes_))))) (alist)))
                  (is! tinj :parent (if (> (.size ^List (ig tinj :nodes)) 0) (.get ^List (ig tinj :nodes) (int (dec (.size ^List (ig tinj :nodes))))) nil))
                  (when (and (some? ckey) (some? (ig tinj :parent)))
                    (setprop (ig tinj :parent) ckey tval))
                  (is! tinj :val tval)
                  (is! tinj :dpath dpath)
                  (is! tinj :dparent tcur)
                  (inject tval store tinj)
                  (reset! rval (ig tinj :val)))))))
        (setprop target tkey @rval)
        (if (and (islist @rval) (> (size @rval) 0)) (.get ^List @rval 0) nil)))))

(defn- transform_PACK [inj _val _ref store]
  (let [mode (ig inj :mode) key (ig inj :key) path (ig inj :path)
        parent (ig inj :parent) nodes_ (ig inj :nodes)]
    (if (or (not= mode S-MKEYPRE) (not (string? key)) (nil? path) (nil? nodes_))
      nil
      (let [args-val (getprop parent key)]
        (if (or (not (islist args-val)) (< (size args-val) 2))
          nil
          (let [srcpath (.get ^List args-val 0)
                origchildspec (.get ^List args-val 1)
                tkey (getelem path -2)
                pathsize (size path)
                target (getelem nodes_ (- pathsize 2) (fn [] (getelem nodes_ (- pathsize 1))))
                srcstore (getprop store (ig inj :base) store)
                src0 (getpath srcstore srcpath inj)
                src (if-not (islist src0)
                      (if (ismap src0)
                        (let [ns (alist)]
                          (doseq [item (items src0)]
                            (setprop (nth item 1) S-BANNO (doto (lhm) (.put S-KEY (nth item 0))))
                            (.add ns (nth item 1)))
                          ns)
                        nil)
                      src0)]
            (if (nil? src)
              nil
              (let [keypath (getprop origchildspec S-BKEY)
                    childspec (delprop origchildspec S-BKEY)
                    child (getprop childspec S-BVAL childspec)
                    tval (lhm)]
                (doseq [item (items src)]
                  (let [srckey (nth item 0) srcnode (nth item 1)
                        k (cond
                            (nil? keypath) srckey
                            (and (string? keypath) (.startsWith ^String keypath S-BT))
                            (inject keypath (merge (alist-of [(lhm) store (doto (lhm) (.put S-DTOP srcnode))]) 1))
                            :else (getpath srcnode keypath inj))
                        tchild (clone child)]
                    (setprop tval k tchild)
                    (let [anno (getprop srcnode S-BANNO)]
                      (if (nil? anno) (delprop tchild S-BANNO) (setprop tchild S-BANNO anno)))))
                (let [rval (atom (lhm))]
                  (when-not (isempty tval)
                    (let [tsrc (lhm)]
                      (doseq [[i n] (map-indexed vector (vec src))]
                        (let [kn (cond
                                   (nil? keypath) i
                                   (and (string? keypath) (.startsWith ^String keypath S-BT))
                                   (inject keypath (merge (alist-of [(lhm) store (doto (lhm) (.put S-DTOP n))]) 1))
                                   :else (getpath n keypath inj))]
                          (setprop tsrc kn n)))
                      (let [tpath (slice (ig inj :path) -1)
                            ckey (getelem (ig inj :path) -2)
                            dpath (flatten (alist-of [S-DTOP (alist-of (.split ^String srcpath "\\." -1)) (str "$:" ckey)]))
                            tcur (doto (lhm) (.put (str ckey) tsrc))
                            tcur (if (> (size tpath) 1)
                                   (let [pkey (getelem (ig inj :path) -3 S-DTOP)]
                                     (.add ^List dpath (str "$:" pkey))
                                     (doto (lhm) (.put (str pkey) tcur)))
                                   tcur)
                            tinj (inj-child inj 0 (alist-of [ckey]))]
                        (is! tinj :path tpath)
                        (is! tinj :nodes (slice (ig inj :nodes) -1))
                        (is! tinj :parent (getelem (ig tinj :nodes) -1))
                        (is! tinj :val tval)
                        (is! tinj :dpath dpath)
                        (is! tinj :dparent tcur)
                        (inject tval store tinj)
                        (reset! rval (ig tinj :val)))))
                  (setprop target tkey @rval)
                  nil)))))))))

(defn- transform_REF [inj val _ref store]
  (let [nodes (ig inj :nodes)]
    (if (not= (ig inj :mode) S-MVAL)
      nil
      (let [refpath (getprop (ig inj :parent) 1)]
        (is! inj :keyI (size (ig inj :keys)))
        (let [spec-func (getprop store S-DSPEC)]
          (if-not (isfunc spec-func)
            nil
            (let [spec (spec-func)
                  ref (getpath spec refpath)
                  hasSubRef (atom false)]
              (when (isnode ref)
                (walk ref (fn [_k v _p _path] (when (= v "`$REF`") (reset! hasSubRef true)) v)))
              (let [tref (clone ref)
                    cpath (slice (ig inj :path) 0 (- (size (ig inj :path)) 3))
                    tpath (slice (ig inj :path) 0 (- (size (ig inj :path)) 1))
                    tcur (getpath store cpath)
                    tval (getpath store tpath)
                    rval (atom nil)]
                (if (and (some? ref) (or (not @hasSubRef) (some? tval)))
                  (let [cs (inj-child inj 0 (alist-of [(getelem tpath -1)]))]
                    (is! cs :path tpath)
                    (is! cs :nodes (slice (ig inj :nodes) 0 (- (size (ig inj :nodes)) 1)))
                    (is! cs :parent (getelem nodes -2))
                    (is! cs :val tref)
                    (is! cs :dparent tcur)
                    (inject tref store cs)
                    (reset! rval (ig cs :val)))
                  (reset! rval nil))
                (inj-setval inj @rval 2)
                (when (and (islist (ig inj :parent)) (ig inj :prior))
                  (is! (ig inj :prior) :keyI (dec (ig (ig inj :prior) :keyI))))
                val))))))))

;; FORMATTER
(defn- jsstr [v]
  (cond (nil? v) "null" (jbool? v) (if v "true" "false") :else (str v)))

(defn- fmt-number [_k v & _]
  (if (isnode v) v
      (let [n (try (double (if (string? v) (Double/parseDouble v) v)) (catch Exception _ 0.0))
            n (if (Double/isNaN n) 0.0 n)]
        (if (== n (Math/floor n)) (long n) n))))

(defn- fmt-integer [_k v & _]
  (if (isnode v) v
      (let [n (try (double (if (string? v) (Double/parseDouble v) v)) (catch Exception _ 0.0))
            n (if (Double/isNaN n) 0.0 n)]
        (long n))))

(def FORMATTER
  {"identity" (fn [_k v & _] v)
   "upper" (fn [_k v & _] (if (isnode v) v (clojure.string/upper-case (jsstr v))))
   "lower" (fn [_k v & _] (if (isnode v) v (clojure.string/lower-case (jsstr v))))
   "string" (fn [_k v & _] (if (isnode v) v (jsstr v)))
   "number" fmt-number
   "integer" fmt-integer
   "concat" (fn [k v & _]
              (if (and (nil? k) (islist v))
                (join (items v (fn [n] (if (isnode (nth n 1)) S-MT (jsstr (nth n 1))))) S-MT)
                v))})

(defn checkPlacement [modes ijname parentTypes inj]
  (let [mode-num (get MODE-TO-NUM (ig inj :mode) 0)]
    (cond
      (zero? (bit-and modes mode-num))
      (let [allowed (clojure.core/filter #(pos? (bit-and modes %)) [M_KEYPRE M_KEYPOST M_VAL])
            placements (join (items (alist-of allowed) (fn [n] (get PLACEMENT (nth n 1) ""))) ",")]
        (.add ^List (ig inj :errs)
              (str "$" ijname ": invalid placement as " (get PLACEMENT mode-num "")
                   ", expected: " placements "."))
        false)
      (not (isempty parentTypes))
      (let [ptype (typify (ig inj :parent))]
        (if (zero? (bit-and parentTypes ptype))
          (do (.add ^List (ig inj :errs)
                    (str "$" ijname ": invalid placement in parent " (typename ptype)
                         ", expected: " (typename parentTypes) "."))
              false)
          true))
      :else true)))

(defn injectorArgs [argTypes args]
  (let [numargs (size argTypes)
        found (object-array (inc numargs))]
    (aset found 0 nil)
    (loop [argI 0]
      (if (< argI numargs)
        (let [arg (getelem args argI)
              argType (typify arg)]
          (if (zero? (bit-and (nth (vec argTypes) argI) argType))
            (do (aset found 0
                      (str "invalid argument: " (stringify arg 22) " (" (typename argType)
                           " at position " (inc argI) ") is not of type: "
                           (typename (nth (vec argTypes) argI)) "."))
                (vec found))
            (do (aset found (inc argI) arg) (recur (inc argI)))))
        (vec found)))))

(defn injectChild [child store inj]
  (let [cinj (atom inj)
        prior (ig inj :prior)]
    (when (some? prior)
      (let [pprior (ig prior :prior)]
        (if (some? pprior)
          (let [c (inj-child pprior (ig prior :keyI) (ig prior :keys))]
            (is! c :val child)
            (setprop (ig c :parent) (ig prior :key) child)
            (reset! cinj c))
          (let [c (inj-child prior (ig inj :keyI) (ig inj :keys))]
            (is! c :val child)
            (setprop (ig c :parent) (ig inj :key) child)
            (reset! cinj c)))))
    (inject child store @cinj)
    @cinj))

(defn- transform_FORMAT [inj _val _ref store]
  (slice (ig inj :keys) 0 1 true)
  (if (not= (ig inj :mode) S-MVAL)
    nil
    (let [name (getprop (ig inj :parent) 1)
          child (getprop (ig inj :parent) 2)
          tkey (getelem (ig inj :path) -2)
          target (getelem (ig inj :nodes) -2 (fn [] (getelem (ig inj :nodes) -1)))
          cinj (injectChild child store inj)
          resolved (ig cinj :val)
          formatter (if (pos? (bit-and T_function (typify name))) name (getprop FORMATTER name))]
      (if (nil? formatter)
        (do (.add ^List (ig inj :errs) (str "$FORMAT: unknown format: " name ".")) nil)
        (let [out (walk resolved formatter)]
          (setprop target tkey out)
          out)))))

(defn- transform_APPLY [inj _val _ref store]
  (let [ijname "APPLY"]
    (if-not (checkPlacement M_VAL ijname T_list inj)
      nil
      (let [res (injectorArgs [T_function T_any] (slice (ig inj :parent) 1))
            err (nth res 0) apply-fn (nth res 1) child (when (> (count res) 2) (nth res 2))]
        (if (some? err)
          (do (.add ^List (ig inj :errs) (str "$" ijname ": " err)) nil)
          (let [tkey (getelem (ig inj :path) -2)
                target (getelem (ig inj :nodes) -2 (fn [] (getelem (ig inj :nodes) -1)))
                cinj (injectChild child store inj)
                resolved (ig cinj :val)
                out (try (apply-fn resolved store cinj)
                         (catch Throwable _
                           (try (apply-fn resolved store) (catch Throwable _ (apply-fn resolved)))))]
            (setprop target tkey out)
            out))))))

(defn transform
  ([data spec] (transform data spec nil))
  ([data spec injdef]
   (let [origspec spec
         spec (clone spec)
         extra (when injdef (getprop injdef "extra"))
         collect (and injdef (some? (getprop injdef "errs")))
         errs (if collect (getprop injdef "errs") (alist))
         extra-transforms (lhm)
         extra-data (lhm)]
     (when extra
       (doseq [[k v] (items extra)]
         (if (and (string? k) (.startsWith ^String k S-DS))
           (.put extra-transforms k v)
           (.put extra-data k v))))
     (let [data-clone (merge (alist-of [(if (isempty extra-data) nil (clone extra-data)) (clone data)]))
           store (lhm)]
       (.put store S-DTOP data-clone)
       (.put store S-DSPEC (fn [& _] origspec))
       (.put store "$BT" (fn [& _] S-BT))
       (.put store "$DS" (fn [& _] S-DS))
       (.put store "$WHEN" (fn [& _] (.toString (java.time.Instant/now))))
       (.put store "$DELETE" transform_DELETE)
       (.put store "$COPY" transform_COPY)
       (.put store "$KEY" transform_KEY)
       (.put store "$ANNO" transform_ANNO)
       (.put store "$MERGE" transform_MERGE)
       (.put store "$EACH" transform_EACH)
       (.put store "$PACK" transform_PACK)
       (.put store "$REF" transform_REF)
       (.put store "$FORMAT" transform_FORMAT)
       (.put store "$APPLY" transform_APPLY)
       (doseq [[k v] (items extra-transforms)] (.put store k v))
       (.put store S-DERRS errs)
       (let [idef (lhm)]
         (when (ismap injdef) (doseq [[k v] (items injdef)] (.put idef k v)))
         (.put idef "errs" errs)
         (let [out (inject spec store idef)]
           (when (and (> (size errs) 0) (not collect))
             (throw (RuntimeException. (join errs " | "))))
           out))))))

;; ---------------------------------------------------------------------------
;; validate
;; ---------------------------------------------------------------------------

(defn- validate_STRING [inj _val _ref _store]
  (let [out (getprop (ig inj :dparent) (ig inj :key)) t (typify out)]
    (cond
      (zero? (bit-and T_string t)) (do (.add ^List (ig inj :errs) (_invalidTypeMsg (ig inj :path) S-string t out "V1010")) nil)
      (= out S-MT) (do (.add ^List (ig inj :errs) (str "Empty string at " (pathify (ig inj :path) 1))) nil)
      :else out)))

(defn- validate_TYPE [inj _val ref _store]
  (let [tname (if (and (string? ref) (> (count ref) 1)) (clojure.string/lower-case (slice ref 1)) S-any)
        idx (.indexOf ^java.util.List (vec TYPENAME) tname)
        typev0 (if (>= idx 0) (bit-shift-left 1 (- 31 idx)) 0)
        typev (if (= tname S-nil) (bit-or typev0 T_null) typev0)
        out (getprop (ig inj :dparent) (ig inj :key))
        t (typify out)]
    (if (zero? (bit-and t typev))
      (do (.add ^List (ig inj :errs) (_invalidTypeMsg (ig inj :path) tname t out "V1001")) nil)
      out)))

(defn- validate_ANY [inj _val _ref _store]
  (getprop (ig inj :dparent) (ig inj :key)))

(defn- validate_CHILD [inj _val _ref _store]
  (let [mode (ig inj :mode) key (ig inj :key) parent (ig inj :parent)
        path (ig inj :path) keys (ig inj :keys)]
    (cond
      (= mode S-MKEYPRE)
      (let [childtm (getprop parent key)
            pkey (getelem path -2)
            tval (getprop (ig inj :dparent) pkey)]
        (cond
          (nil? tval) (let [tval (lhm)]
                        (doseq [ckey (keysof tval)] (setprop parent ckey (clone childtm)) (.add ^List keys ckey))
                        (delprop parent key) nil)
          (not (ismap tval))
          (do (.add ^List (ig inj :errs) (_invalidTypeMsg (slice path 0 (dec (size path))) S-object (typify tval) tval "V0220")) nil)
          :else
          (do (doseq [ckey (keysof tval)] (setprop parent ckey (clone childtm)) (.add ^List keys ckey))
              (delprop parent key) nil)))

      (= mode S-MVAL)
      (let [childtm (getprop parent 1)]
        (cond
          (not (islist parent)) (do (.add ^List (ig inj :errs) "Invalid $CHILD as value") nil)
          (nil? (ig inj :dparent)) (do (.clear ^List parent) nil)
          (not (islist (ig inj :dparent)))
          (do (.add ^List (ig inj :errs) (_invalidTypeMsg (slice path 0 (dec (size path))) S-list (typify (ig inj :dparent)) (ig inj :dparent) "V0230"))
              (is! inj :keyI (size parent)) (ig inj :dparent))
          :else
          (do (doseq [n (items (ig inj :dparent))] (setprop parent (nth n 0) (clone childtm)))
              (while (> (.size ^List parent) (.size ^List (ig inj :dparent))) (.remove ^List parent (int (dec (.size ^List parent)))))
              (is! inj :keyI 0)
              (getprop (ig inj :dparent) 0))))
      :else nil)))

(defn- validate_ONE [inj _val _ref store]
  (let [mode (ig inj :mode) parent (ig inj :parent) keyI (ig inj :keyI)]
    (when (= mode S-MVAL)
      (if (or (not (islist parent)) (not= keyI 0))
        (do (.add ^List (ig inj :errs) (str "The $ONE validator at field " (pathify (ig inj :path) 1 1) " must be the first element of an array.")) nil)
        (do
          (is! inj :keyI (size (ig inj :keys)))
          (inj-setval inj (ig inj :dparent) 2)
          (is! inj :path (slice (ig inj :path) 0 (dec (size (ig inj :path)))))
          (is! inj :key (getelem (ig inj :path) -1))
          (let [tvals (alist-of (subvec (vec parent) 1))]
            (if (= (size tvals) 0)
              (do (.add ^List (ig inj :errs) (str "The $ONE validator at field " (pathify (ig inj :path) 1 1) " must have at least one argument.")) nil)
              (let [matched (atom false)]
                (doseq [tval tvals :while (not @matched)]
                  (let [terrs (alist)
                        vstore (merge (alist-of [(lhm) store]) 1)]
                    (.put ^Map vstore S-DTOP (ig inj :dparent))
                    (let [vcurrent (validate (ig inj :dparent) tval (doto (lhm) (.put "extra" vstore) (.put "errs" terrs) (.put "meta" (ig inj :meta))))]
                      (inj-setval inj vcurrent -2)
                      (when (= (size terrs) 0) (reset! matched true)))))
                (when-not @matched
                  (let [valdesc (clojure.string/join ", " (map #(stringify (nth % 1)) (items tvals)))
                        valdesc (re_replace R-TRANSFORM-NAME valdesc (fn [g] (clojure.string/lower-case (nth g 1))))]
                    (.add ^List (ig inj :errs)
                          (_invalidTypeMsg (ig inj :path)
                                           (str (if (> (size tvals) 1) "one of " "") valdesc)
                                           (typify (ig inj :dparent)) (ig inj :dparent) "V0210"))))))))))))

(defn- validate_EXACT [inj _val _ref _store]
  (let [mode (ig inj :mode) parent (ig inj :parent) key (ig inj :key) keyI (ig inj :keyI)]
    (if (= mode S-MVAL)
      (if (or (not (islist parent)) (not= keyI 0))
        (do (.add ^List (ig inj :errs) (str "The $EXACT validator at field " (pathify (ig inj :path) 1 1) " must be the first element of an array.")) nil)
        (do
          (is! inj :keyI (size (ig inj :keys)))
          (inj-setval inj (ig inj :dparent) 2)
          (is! inj :path (slice (ig inj :path) 0 (dec (size (ig inj :path)))))
          (is! inj :key (getelem (ig inj :path) -1))
          (let [tvals (alist-of (subvec (vec parent) 1))]
            (if (= (size tvals) 0)
              (do (.add ^List (ig inj :errs) (str "The $EXACT validator at field " (pathify (ig inj :path) 1 1) " must have at least one argument.")) nil)
              (let [currentstr (atom nil) matched (atom false)]
                (doseq [tval tvals :while (not @matched)]
                  (let [em (= tval (ig inj :dparent))
                        em (if (and (not em) (isnode tval))
                             (do (when (nil? @currentstr) (reset! currentstr (stringify (ig inj :dparent))))
                                 (= (stringify tval) @currentstr))
                             em)]
                    (when em (reset! matched true))))
                (when-not @matched
                  (let [valdesc (clojure.string/join ", " (map #(stringify (nth % 1)) (items tvals)))
                        valdesc (re_replace R-TRANSFORM-NAME valdesc (fn [g] (clojure.string/lower-case (nth g 1))))]
                    (.add ^List (ig inj :errs)
                          (_invalidTypeMsg (ig inj :path)
                                           (str (if (> (size (ig inj :path)) 1) "" "value ")
                                                "exactly equal to " (if (= (size tvals) 1) "" "one of ") valdesc)
                                           (typify (ig inj :dparent)) (ig inj :dparent) "V0110")))))))))
      (delprop parent key))))

(defn- _validation [pval key parent inj]
  (when (and (some? inj) (not (identical? pval SKIP)))
    (let [exact (getprop (ig inj :meta) S-BEXACT false)
          cval (getprop (ig inj :dparent) key)]
      (when-not (and (not exact) (nil? cval))
        (let [ptype (typify pval)]
          (when-not (and (pos? (bit-and T_string ptype)) (.contains ^String (str pval) S-DS))
            (let [ctype (typify cval)]
              (cond
                (and (not= ptype ctype) (some? pval))
                (.add ^List (ig inj :errs) (_invalidTypeMsg (ig inj :path) (typename ptype) ctype cval "V0010"))

                (ismap cval)
                (if-not (ismap pval)
                  (.add ^List (ig inj :errs) (_invalidTypeMsg (ig inj :path) (typename ptype) ctype cval "V0020"))
                  (let [ckeys (keysof cval) pkeys (keysof pval)]
                    (if (and (> (count pkeys) 0) (not (true? (getprop pval "`$OPEN`"))))
                      (let [badkeys (clojure.core/filter #(not (haskey pval %)) ckeys)]
                        (when (> (size badkeys) 0)
                          (.add ^List (ig inj :errs)
                                (str "Unexpected keys at field " (pathify (ig inj :path) 1) S-VIZ (join (alist-of badkeys) ", ")))))
                      (do (merge (alist-of [pval cval]))
                          (when (isnode pval) (delprop pval "`$OPEN`"))))))

                (islist cval)
                (when-not (islist pval)
                  (.add ^List (ig inj :errs) (_invalidTypeMsg (ig inj :path) (typename ptype) ctype cval "V0030")))

                exact
                (when (not= cval pval)
                  (let [pathmsg (if (> (size (ig inj :path)) 1) (str "at field " (pathify (ig inj :path) 1) ": ") "")]
                    (.add ^List (ig inj :errs) (str "Value " pathmsg (str cval) " should equal " (str pval) "."))))

                :else (setprop parent key cval)))))))))

(defn- _validatehandler [inj val ref store]
  (let [m (when (string? ref) (re_find R-META-PATH ref))]
    (if (some? m)
      (do
        (if (= (nth m 2) "=")
          (inj-setval inj (alist-of [S-BEXACT val]))
          (inj-setval inj val))
        (is! inj :keyI -1)
        SKIP)
      (_injecthandler inj val ref store))))

(defn validate
  ([data spec] (validate data spec nil))
  ([data spec injdef]
   (let [extra (getprop injdef "extra")
         collect (and injdef (some? (getprop injdef "errs")))
         errs (if collect (getprop injdef "errs") (alist))
         base (lhm)]
     (doseq [[k v] [["$DELETE" nil] ["$COPY" nil] ["$KEY" nil] ["$META" nil]
                    ["$MERGE" nil] ["$EACH" nil] ["$PACK" nil]
                    ["$STRING" validate_STRING] ["$NUMBER" validate_TYPE] ["$INTEGER" validate_TYPE]
                    ["$DECIMAL" validate_TYPE] ["$BOOLEAN" validate_TYPE] ["$NULL" validate_TYPE]
                    ["$NIL" validate_TYPE] ["$MAP" validate_TYPE] ["$LIST" validate_TYPE]
                    ["$FUNCTION" validate_TYPE] ["$INSTANCE" validate_TYPE]
                    ["$ANY" validate_ANY] ["$CHILD" validate_CHILD] ["$ONE" validate_ONE]
                    ["$EXACT" validate_EXACT]]]
       (.put base k v))
     (let [store (merge (alist-of [base (if (nil? extra) (lhm) extra) (doto (lhm) (.put "$ERRS" errs))]) 1)
           meta (getprop injdef "meta" (lhm))]
       (setprop meta S-BEXACT (getprop meta S-BEXACT false))
       (let [out (transform data spec (doto (lhm)
                                        (.put "meta" meta)
                                        (.put "extra" store)
                                        (.put "modify" _validation)
                                        (.put "handler" _validatehandler)
                                        (.put "errs" errs)))]
         (when (and (> (size errs) 0) (not collect))
           (throw (RuntimeException. (clojure.string/join " | " (vec errs)))))
         out)))))

(defn- _invalidTypeMsg [path needtype vt v _whence]
  (let [vs (if (nil? v) "no value" (stringify v))]
    (str "Expected "
         (if (> (size path) 1) (str "field " (pathify path 1) " to be ") "")
         (str needtype)
         ", but found "
         (if (some? v) (str (typename vt) S-VIZ) "")
         vs ".")))

;; ---------------------------------------------------------------------------
;; select
;; ---------------------------------------------------------------------------

(defn- select_AND [inj _val _ref store]
  (when (= (ig inj :mode) S-MKEYPRE)
    (let [terms (getprop (ig inj :parent) (ig inj :key))
          ppath (slice (ig inj :path) -1)
          point (getpath store ppath)
          vstore (merge (alist-of [(lhm) store]) 1)]
      (.put ^Map vstore S-DTOP point)
      (doseq [term terms]
        (let [terrs (alist)]
          (validate point term (doto (lhm) (.put "extra" vstore) (.put "errs" terrs) (.put "meta" (ig inj :meta))))
          (when (not= (size terrs) 0)
            (.add ^List (ig inj :errs) (str "AND:" (pathify ppath) "⨯" (stringify point) " fail:" (stringify terms))))))
      (let [gkey (getelem (ig inj :path) -2) gp (getelem (ig inj :nodes) -2)]
        (setprop gp gkey point))))
  nil)

(defn- select_OR [inj _val _ref store]
  (when (= (ig inj :mode) S-MKEYPRE)
    (let [terms (getprop (ig inj :parent) (ig inj :key))
          ppath (slice (ig inj :path) -1)
          point (getpath store ppath)
          vstore (merge (alist-of [(lhm) store]) 1)
          done (atom false)]
      (.put ^Map vstore S-DTOP point)
      (doseq [term terms :while (not @done)]
        (let [terrs (alist)]
          (validate point term (doto (lhm) (.put "extra" vstore) (.put "errs" terrs) (.put "meta" (ig inj :meta))))
          (when (= (size terrs) 0)
            (let [gkey (getelem (ig inj :path) -2) gp (getelem (ig inj :nodes) -2)]
              (setprop gp gkey point) (reset! done true)))))
      (when-not @done
        (.add ^List (ig inj :errs) (str "OR:" (pathify ppath) "⨯" (stringify point) " fail:" (stringify terms))))))
  nil)

(defn- select_NOT [inj _val _ref store]
  (when (= (ig inj :mode) S-MKEYPRE)
    (let [term (getprop (ig inj :parent) (ig inj :key))
          ppath (slice (ig inj :path) -1)
          point (getpath store ppath)
          vstore (merge (alist-of [(lhm) store]) 1)
          terrs (alist)]
      (.put ^Map vstore S-DTOP point)
      (validate point term (doto (lhm) (.put "extra" vstore) (.put "errs" terrs) (.put "meta" (ig inj :meta))))
      (when (= (size terrs) 0)
        (.add ^List (ig inj :errs) (str "NOT:" (pathify ppath) "⨯" (stringify point) " fail:" (stringify term))))
      (let [gkey (getelem (ig inj :path) -2) gp (getelem (ig inj :nodes) -2)]
        (setprop gp gkey point))))
  nil)

(defn- num-cmp [a b op]
  (try
    (let [x (double a) y (double b)]
      (case op :gt (> x y) :lt (< x y) :gte (>= x y) :lte (<= x y)))
    (catch Exception _ false)))

(defn- select_CMP [inj _val ref store]
  (when (= (ig inj :mode) S-MKEYPRE)
    (let [term (getprop (ig inj :parent) (ig inj :key))
          gkey (getelem (ig inj :path) -2)
          ppath (slice (ig inj :path) -1)
          point (getpath store ppath)
          pass (cond
                 (= ref "$GT") (num-cmp point term :gt)
                 (= ref "$LT") (num-cmp point term :lt)
                 (= ref "$GTE") (num-cmp point term :gte)
                 (= ref "$LTE") (num-cmp point term :lte)
                 (= ref "$LIKE") (boolean (re_test (re_compile term) (stringify point)))
                 :else false)]
      (if pass
        (let [gp (getelem (ig inj :nodes) -2)] (setprop gp gkey point))
        (.add ^List (ig inj :errs) (str "CMP: " (pathify ppath) "⨯" (stringify point) " fail:" ref " " (stringify term))))))
  nil)

(defn select [children query]
  (if-not (isnode children)
    (alist)
    (let [children (if (ismap children)
                     (alist-of (map (fn [n] (setprop (nth n 1) S-DKEY (nth n 0)) (nth n 1)) (items children)))
                     (alist-of (map-indexed (fn [i n] (if (ismap n) (do (setprop n S-DKEY i) n) n)) (vec children))))
          results (alist)
          extra (doto (lhm)
                  (.put "$AND" select_AND) (.put "$OR" select_OR) (.put "$NOT" select_NOT)
                  (.put "$GT" select_CMP) (.put "$LT" select_CMP) (.put "$GTE" select_CMP)
                  (.put "$LTE" select_CMP) (.put "$LIKE" select_CMP))
          q (clone query)]
      (walk q (fn [_k v _p _path] (when (ismap v) (setprop v "`$OPEN`" (getprop v "`$OPEN`" true))) v))
      (doseq [child children]
        (let [errs (alist)
              injdef (doto (lhm) (.put "errs" errs) (.put "meta" (doto (lhm) (.put S-BEXACT true))) (.put "extra" extra))]
          (validate child (clone q) injdef)
          (when (= (size errs) 0) (.add results child))))
      results)))

;; ---------------------------------------------------------------------------
;; JSON builders
;; ---------------------------------------------------------------------------

(defn jm [& kv]
  (let [kvsize (count kv) o (lhm) kvv (vec kv)]
    (doseq [i (range 0 kvsize 2)]
      (let [k0 (nth kvv i)
            k (cond (nil? k0) "null" (string? k0) k0 :else (stringify k0))]
        (.put o k (if (< (inc i) kvsize) (nth kvv (inc i)) nil))))
    o))

(defn jt [& v]
  (alist-of v))

;; ---------------------------------------------------------------------------
;; StructUtility container (parity with other ports)
;; ---------------------------------------------------------------------------

(def tn typename)

(defn struct-utility []
  {:clone clone :delprop delprop :escre escre :escurl escurl :filter filter
   :flatten flatten :getdef getdef :getelem getelem :getpath getpath :getprop getprop
   :haskey haskey :inject inject :isempty isempty :isfunc isfunc :iskey iskey
   :islist islist :ismap ismap :isnode isnode :items items :jm jm :jt jt
   :join join :joinurl joinurl :jsonify jsonify :keysof keysof :merge merge
   :pad pad :pathify pathify :replace replace :select select :setpath setpath
   :setprop setprop :size size :slice slice :stringify stringify :strkey strkey
   :transform transform :typify typify :typename typename :validate validate :walk walk
   :re_compile re_compile :re_find re_find :re_find_all re_find_all
   :re_replace re_replace :re_test re_test :re_escape re_escape
   :SKIP SKIP :DELETE DELETE :tn tn
   :checkPlacement checkPlacement :injectorArgs injectorArgs :injectChild injectChild})
