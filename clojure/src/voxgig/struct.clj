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
(def ^:private HELDNULL (Object.))

(def ^:const MAXDEPTH 32)

;; Path processing regexes.
(def ^:private R-META-PATH (Pattern/compile "^([^$]+)\\$([=~])(.+)$"))
(def ^:private R-DOUBLE-DOLLAR (Pattern/compile "\\$\\$"))
(def ^:private R-INJECT-FULL (Pattern/compile "^`(\\$[A-Z]+|[^`]*)[0-9]*`$"))
(def ^:private R-INJECT-PART (Pattern/compile "`([^`]*)`"))
(def ^:private R-TRANSFORM-NAME (Pattern/compile "`\\$([A-Z]+)`"))
(def ^:private R-CHECKER-NAME (Pattern/compile "^\\$[A-Z]+$"))

(def ^:private CONDENSE_VERSION 1)
(def ^:private CONDENSE_MAP 0)
(def ^:private CONDENSE_LIST 1)
(def ^:private CONDENSE_STR 2)
(def ^:private CONDENSE_NUM 3)
(def ^:private CONDENSE_TRUE 4)
(def ^:private CONDENSE_FALSE 5)
(def ^:private CONDENSE_NULL 6)
(def ^:private S-condense "$condense")
(def ^:private S-condsym "sym")
(def ^:private S-condnode "node")
(def ^:private S-condroot "root")
(def ^:private CONDENSE-IMMUTABLE
  "struct: condensed structures are immutable - expand() first, then modify the copy")

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
         validate transform select jsonify FORMATTER
         iscondensed expand condenseresolve condensematerialise condensekey)

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

;; A list key's index, possibly negative, or nil: an integral number, or the
;; string String(n) prints for one ("01", " 1", "+1", "1.0" and "-0" are not).
(defn- listindex [key]
  (cond
    (jdouble? key) (let [d (double key)]
                     (when (and (== d (Math/rint d)) (not (Double/isInfinite d))) (unchecked-long d)))
    (or (string? key) (number? key))
    (let [k (str key)]
      (when (re-matches #"0|-?[1-9][0-9]*" k)
        (try (Long/parseLong k)
             (catch NumberFormatException _ (if (.startsWith k "-") Long/MIN_VALUE Long/MAX_VALUE)))))
    :else nil))

;; The index a list read takes key to, or nil: a non-negative list key in range.
(defn- readindex [^List lst key]
  (let [ki (listindex key)]
    (when (and ki (<= 0 ki) (< ki (.size lst))) ki)))

;; Only a string or a number names a property.
(defn- readkey? [key] (or (string? key) (number? key)))

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
         (when-let [ki (when (islist val) (listindex key))]
           (let [len (.size ^List val)
                 ;; A negative key counts from the end.
                 nk (if (neg? ki) (+ len ki) ki)]
             (when (and (<= 0 nk) (< nk len))
               (reset! out (.get ^List val (int nk))))))
         (if (nil? @out)
           (if (isfunc alt) (alt) alt)
           @out))))))

(defn getprop
  ([val key] (getprop val key nil))
  ([val key alt]
   (if (or (nil? val) (nil? key))
     alt
     (let [out (_lookup val key)]
       (if (or (nil? out) (identical? out NOARG)) alt out)))))

(defn- _lookup [val key]
  (cond
    (or (nil? val) (nil? key)) nil
    (ismap val) (when (readkey? key) (.get ^Map val (str key)))
    (islist val) (when-let [ki (readindex val key)] (.get ^List val (int ki)))
    :else nil))

;; Literal presence, beside _lookup: a nil the node holds is a null, not an absent key.
(defn- _holds [val key]
  (cond
    (nil? key) false
    (ismap val) (and (readkey? key) (.containsKey ^Map val (str key)))
    (islist val) (some? (readindex val key))
    :else false))

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
    (when (iscondensed parent) (throw (RuntimeException. ^String CONDENSE-IMMUTABLE)))
    (cond
      (ismap parent) (.put ^Map parent (str key) val)
      (islist parent)
      (let [ki (listindex key)]
        (when ki
          (let [^List p parent len (.size p)]
            (if (>= ki 0)
              (let [ki (min ki len)]
                (if (>= ki len) (.add p val) (.set p (int ki) val)))
              (.add p 0 val)))))))
  parent)

(defn delprop [parent key]
  (when (iskey key)
    (when (iscondensed parent) (throw (RuntimeException. ^String CONDENSE-IMMUTABLE)))
    (cond
      (ismap parent) (.remove ^Map parent (str key))
      (islist parent)
      (let [ki (listindex key)]
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
                                            (if (or (and (islist val) (islist tval)) (and (ismap val) (ismap tval)))
                                              (do (.set cur (int pI) tval) val)
                                              ;; Otherwise the override wins: it is copied, taking nothing
                                              ;; from the destination, so no later merge writes into it.
                                              (do (.set cur (int pI) (if (islist val) (alist) (lhm)))
                                                  (.set dst (int pI) nil)
                                                  val)))))))
                         after (fn [key _val parent path]
                                 (let [cI (size path)]
                                   (if (< cI 1)
                                     (if (> (.size cur) 0) (.get cur 0) _val)
                                     (let [target (when (< (dec cI) (.size cur)) (.get cur (int (dec cI))))
                                           value (when (< cI (.size cur)) (.get cur (int cI)))]
                                       (setprop target key value)
                                       ;; walk writes this back into the override, so it is the
                                       ;; override's own child, leaving the override unchanged.
                                       (_lookup parent key)))))]
                     (reset! out (walk obj {:before before :after after}))))))
             (when (= md 0)
               (let [o (getprop objs (dec lenlist) nil)]
                 (reset! out (cond (islist o) (alist) (ismap o) (lhm) :else o))))
             @out)))))))

;; ---------------------------------------------------------------------------
;; getpath / setpath
;; ---------------------------------------------------------------------------

;; A number part reads as String(n) prints it; any part neither string nor
;; number makes the whole path miss.
(defn- pathparts ^ArrayList [path]
  (when (every? #(or (string? %) (number? %)) path)
    (alist-of (map condensekey path))))

(defn getpath
  ([store path] (getpath store path nil))
  ([store path injdef]
   (let [parts (cond
                 (islist path) (pathparts path)
                 (string? path) (alist-of (.split ^String path "\\." -1))
                 (number? path) (alist-of [(condensekey path)])
                 :else nil)
         condensed (and (some? parts) (iscondensed store))
         direct (and condensed
                     (nil? (if (inj? injdef) (ig injdef :base) (when injdef (getprop injdef S-base)))))
         store (if (and condensed (not direct)) (expand store) store)]
     (cond
       (nil? parts)
       nil

       ;; Reads only the nodes on the path. A base changes what the path
       ;; resolves against, so that read walks the expanded copy instead.
       direct
       (condensematerialise store (condenseresolve store (_lookup store S-condroot) parts))

       :else
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
   (when (iscondensed store) (throw (RuntimeException. ^String CONDENSE-IMMUTABLE)))
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
     (cond
       (nil? val) (delprop target key)
       (identical? val HELDNULL) (setprop target key nil)
       :else (setprop target key val)))))

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
                 (if (identical? v HELDNULL) nil v)))

             :else val)]

       ;; Custom modification (runs after special commands).
       (when (and (ig inj :modify) (not (identical? val SKIP)))
         (let [mkey (ig inj :key) mparent (ig inj :parent) mval (getprop mparent mkey)]
           ((ig inj :modify) mval mkey mparent inj)))

       (is! inj :val val)

       (cond
         ;; Read literally: a null a list directive set at $TOP is the result.
         (and (nil? (ig inj :prior)) (_holds (ig inj :root) S-DTOP))
         (_lookup (ig inj :root) S-DTOP)
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
  (let [out (_lookup (ig inj :dparent) (ig inj :key)) t (typify out)]
    (cond
      (zero? (bit-and T_string t)) (do (.add ^List (ig inj :errs) (_invalidTypeMsg (ig inj :path) S-string t out "V1010")) nil)
      (= out S-MT) (do (.add ^List (ig inj :errs) (str "Empty string at " (pathify (ig inj :path) 1))) nil)
      :else out)))

;; A null the data holds comes back as HELDNULL, which inj-setval writes:
;; it deletes the slot for nil, and a list would shift down.
(defn- _keepnull [inj out]
  (if (and (nil? out) (= (ig inj :mode) S-MVAL) (true? (ig inj :full)) (_holds (ig inj :dparent) (ig inj :key)))
    HELDNULL
    out))

(defn- validate_TYPE [inj _val ref _store]
  (let [tname (if (and (string? ref) (> (count ref) 1)) (clojure.string/lower-case (slice ref 1)) S-any)
        idx (.indexOf ^java.util.List (vec TYPENAME) tname)
        typev0 (if (>= idx 0) (bit-shift-left 1 (- 31 idx)) 0)
        typev (if (= tname S-nil) (bit-or typev0 T_null) typev0)
        dparent (ig inj :dparent)
        key (ig inj :key)
        out (_lookup dparent key)
        ;; One nil: only the slot tells a missing field (no value) from a held null.
        t (if (or (some? out) (_holds dparent key)) (typify out) T_noval)]
    (if (zero? (bit-and t typev))
      (do (.add ^List (ig inj :errs) (_invalidTypeMsg (ig inj :path) tname t out "V1001")) nil)
      (_keepnull inj out))))

(defn- validate_ANY [inj _val _ref _store]
  (_keepnull inj (_lookup (ig inj :dparent) (ig inj :key))))

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
          ;; _validation reports the mismatch, once.
          (not (ismap tval)) nil
          :else
          (do (doseq [ckey (keysof tval)] (setprop parent ckey (clone childtm)) (.add ^List keys ckey))
              (delprop parent key) nil)))

      (= mode S-MVAL)
      (let [childtm (getprop parent 1)]
        (cond
          (not (islist parent)) (do (.add ^List (ig inj :errs) "Invalid $CHILD as value") nil)
          (nil? (ig inj :dparent)) (do (.clear ^List parent) nil)
          (not (islist (ig inj :dparent)))
          (do (is! inj :keyI (size parent)) (ig inj :dparent))
          :else
          (do (doseq [n (items (ig inj :dparent))] (setprop parent (nth n 0) (clone childtm)))
              (while (> (.size ^List parent) (.size ^List (ig inj :dparent))) (.remove ^List parent (int (dec (.size ^List parent)))))
              ;; NOTE: modifying inj! This extends the child value loop in inject
              ;; to cover every cloned child.
              (doseq [ckeyI (range (size keys) (size parent))] (.add ^List keys (strkey ckeyI)))
              ;; Restart the child value loop at the first element (the loop
              ;; increments keyI on resume) so that the first element is also
              ;; validated against the child template.
              (is! inj :keyI -1)
              ;; SKIP leaves the cloned child template in place at the first
              ;; element so the resumed loop can validate it.
              SKIP)))
      :else nil)))

;; The data value at a list directive's slot, and whether the slot holds one.
;; The directive's own dparent was read with getprop, which reports a stored
;; null as absent, and with one nil only the slot can tell them apart.
(defn- _slotval [inj]
  (let [prior (ig inj :prior)
        [cval held] (if (nil? prior)
                      [(ig inj :dparent) (some? (ig inj :dparent))]
                      [(_lookup (ig prior :dparent) (ig prior :key)) (_holds (ig prior :dparent) (ig prior :key))])]
    ;; A trial hands an absent value down as NOARG: the slot holds no value.
    (if (identical? cval NOARG) [nil false] [cval held])))

;; inj-setval deletes for nil, so a null the slot holds is set directly.
(defn- _slotset [inj cval held]
  (if (and (nil? cval) held)
    (setprop (getelem (ig inj :nodes) -2) (getelem (ig inj :path) -2) nil)
    (inj-setval inj cval 2)))

;; JSON equality: numbers by value, lists in order, maps by key in any order.
(defn- _deepequal [a b]
  (let [atype (typify a)]
    (cond
      (and (number? a) (number? b)) (== a b)
      (= a b) true
      (or (not= atype (typify b)) (zero? (bit-and (bit-or T_list T_map) atype))) false
      :else
      (let [akeys (keysof a) bkeys (keysof b)]
        (and (= (count akeys) (count bkeys))
             (every? true? (map (fn [ak bk] (and (= ak bk) (_deepequal (_lookup a ak) (_lookup b bk))))
                                akeys bkeys)))))))

;; Every member val has is in out, unchanged. A member only out has is a
;; default the spec supplied, and is ignored.
(defn- _keeps [val out]
  (if (or (zero? (bit-and (bit-or T_list T_map) (typify val)))
          (not= (islist val) (islist out))
          (not (isnode out)))
    (_deepequal val out)
    (every? (fn [k] (and (_holds out k) (_keeps (_lookup val k) (_lookup out k)))) (keysof val))))

;; A spec admits a value when validating the value against it finds no error
;; and gives back the value as it is. Any output keeps an absent value, which
;; goes down as NOARG so that the nested validation reads it as no value.
(defn- _admits [val held spec inj store]
  (let [tval (if held val NOARG)
        terrs (alist)
        vstore (merge (alist-of [(lhm) store]) 1)]
    (.put ^Map vstore S-DTOP tval)
    (let [out (validate tval spec (doto (lhm) (.put "extra" vstore) (.put "errs" terrs) (.put "meta" (ig inj :meta))))]
      (and (zero? (size terrs)) (or (not held) (_keeps val out))))))

;; The bounds of a $NOF count, and the words for it, which are absent when
;; the count is invalid. Without a max, the bound is the number of specs.
;; An integral decimal counts as that integer, as 2.0 is 2 in JavaScript.
(defn- _nofcount [cnt numtvals]
  (let [whole (fn [n] (if (and (jdouble? n) (== n (Math/rint (double n))) (< (Math/abs (double n)) 9.0E18))
                        (long n)
                        n))
        isnat (fn [n] (and (pos? (bit-and T_integer (typify n))) (>= n 0)))
        cnt (whole cnt)]
    (if (isnat cnt)
      [cnt cnt (if (zero? cnt) "none" (str "exactly " cnt))]
      (let [cmin (whole (_lookup cnt "min"))
            cmax (whole (_lookup cnt "max"))
            valid (and (ismap cnt)
                       (pos? (size cnt))
                       (= (size cnt) (+ (if (nil? cmin) 0 1) (if (nil? cmax) 0 1)))
                       (or (nil? cmin) (isnat cmin))
                       (or (nil? cmax) (isnat cmax))
                       (or (nil? cmin) (nil? cmax) (<= cmin cmax)))]
        (if-not valid
          [0 0 nil]
          (let [lo (if (nil? cmin) 0 cmin)
                hi (if (nil? cmax) numtvals cmax)]
            [lo hi (cond
                     (nil? cmax) (str "at least " lo)
                     (zero? hi) "none"
                     (nil? cmin) (str "at most " hi)
                     (== lo hi) (str "exactly " lo)
                     :else (str lo " to " hi))]))))))

;; The counting list directives. Without a count, every spec has to admit.
(defn- _validatecount [inj store name counted]
  (let [mode (ig inj :mode) parent (ig inj :parent) keyI (ig inj :keyI)]
    (cond
      (not= mode S-MVAL) nil

      (or (not (islist parent)) (not= keyI 0))
      (do (.add ^List (ig inj :errs) (str "The " name " validator at field " (pathify (ig inj :path) 1 1) " must be the first element of an array.")) nil)

      :else
      (let [[cval held] (_slotval inj)]
        (is! inj :keyI (size (ig inj :keys)))
        ;; Replace the directive's list with the data value. Each return is SKIP, so
        ;; that inject leaves the detached list alone and validates nothing in it.
        (_slotset inj cval held)
        (is! inj :path (slice (ig inj :path) -1))
        (let [cnt (when counted (_lookup parent 1))
              ^List tvals (alist-of (drop (if counted 2 1) parent))
              numtvals (size tvals)
              field (str "The " name " validator at field " (pathify (ig inj :path) 1))]
          (if (zero? numtvals)
            (.add ^List (ig inj :errs) (str field (if counted " must have a count and" " must have") " at least one argument."))
            (let [[lo hi countdesc] (if counted (_nofcount cnt numtvals) [numtvals numtvals "all"])]
              (if (nil? countdesc)
                (.add ^List (ig inj :errs) (str field " has an invalid count: " (stringify cnt) "."))
                (let [admitted (loop [tI 0 admitted 0]
                                 (let [left (- numtvals tI)]
                                   ;; Stop once the specs left cannot change the verdict.
                                   (if (or (>= tI numtvals) (< hi admitted) (< (+ admitted left) lo)
                                           (and (<= lo admitted) (<= (+ admitted left) hi)))
                                     admitted
                                     (recur (inc tI) (if (_admits cval held (.get tvals (int tI)) inj store)
                                                       (inc admitted) admitted)))))]
                  (when (or (< admitted lo) (< hi admitted))
                    (let [valdesc (clojure.string/join ", " (map #(stringify (nth % 1)) (items tvals)))
                          valdesc (re_replace R-TRANSFORM-NAME valdesc (fn [g] (clojure.string/lower-case (nth g 1))))]
                      (.add ^List (ig inj :errs)
                            (_invalidTypeMsg (ig inj :path) (str countdesc " of " valdesc) (typify cval) cval "V0310"))))))))
          SKIP)))))

(defn- validate_EXACT [inj _val _ref _store]
  (let [mode (ig inj :mode) parent (ig inj :parent) key (ig inj :key) keyI (ig inj :keyI)]
    (if (= mode S-MVAL)
      (if (or (not (islist parent)) (not= keyI 0))
        (do (.add ^List (ig inj :errs) (str "The $EXACT validator at field " (pathify (ig inj :path) 1 1) " must be the first element of an array.")) nil)
        (let [[cval held] (_slotval inj)]
          (is! inj :keyI (size (ig inj :keys)))
          ;; Replace [$EXACT, ...] with the data value; SKIP keeps inject off the detached list.
          (_slotset inj cval held)
          (is! inj :path (slice (ig inj :path) 0 (dec (size (ig inj :path)))))
          (let [tvals (alist-of (subvec (vec parent) 1))]
            (cond
              (= (size tvals) 0)
              (.add ^List (ig inj :errs) (str "The $EXACT validator at field " (pathify (ig inj :path) 1 1) " must have at least one argument."))

              ;; An absent value equals no argument.
              (and held (some #(_deepequal % cval) tvals))
              nil

              :else
              (let [valdesc (clojure.string/join ", " (map #(stringify (nth % 1)) (items tvals)))
                    valdesc (re_replace R-TRANSFORM-NAME valdesc (fn [g] (clojure.string/lower-case (nth g 1))))]
                (.add ^List (ig inj :errs)
                      (_invalidTypeMsg (ig inj :path)
                                       (str (if (> (size (ig inj :path)) 1) "" "value ")
                                            "exactly equal to " (if (= (size tvals) 1) "" "one of ") valdesc)
                                       (typify cval) cval "V0110")))))
          SKIP))
      (do (delprop parent key) nil))))

;; Count the specs that admit the value: ['`$NOF`', count, spec, ...], where
;; count is an integer, or a map holding min, max or both.
(defn- validate_NOF [inj _val _ref store] (_validatecount inj store "$NOF" true))

;; Every spec admits the value: ['`$ALL`', spec, ...].
(defn- validate_ALL [inj _val _ref store] (_validatecount inj store "$ALL" false))

;; The bounds of a $LEN bound, with -1 for no maximum, and the words for it,
;; which are absent when the bound is invalid.
(defn- _lenbound [bound]
  (let [[lo hi countdesc] (_nofcount bound -1)]
    (if (nil? countdesc)
      [0 0 nil]
      [lo hi (str "of length " (cond
                                 (== lo hi) lo
                                 (== -1 hi) (str "at least " lo)
                                 (zero? lo) (str "at most " hi)
                                 :else (str lo " to " hi)))])))

;; The words for a $RANGE bound, which are absent when the bound is invalid.
(defn- _rangedesc [bound]
  (when (ismap bound)
    (let [bmin (_lookup bound "min")
          bmax (_lookup bound "max")
          bgt (_lookup bound "gt")
          blt (_lookup bound "lt")
          lower (if (nil? bmin) bgt bmin)
          upper (if (nil? bmax) blt bmax)
          isnum (fn [n] (or (nil? n) (pos? (bit-and T_number (typify n)))))
          valid (and (pos? (size bound))
                     (= (size bound) (count (remove nil? [bmin bmax bgt blt])))
                     (or (nil? bmin) (nil? bgt))
                     (or (nil? bmax) (nil? blt))
                     (isnum bmin) (isnum bmax) (isnum bgt) (isnum blt)
                     (or (nil? lower) (nil? upper) (<= lower upper)))]
      (when valid
        (clojure.string/join " and "
                             (remove nil? [(cond (some? bmin) (str "at least " (stringify bmin))
                                                 (some? bgt) (str "greater than " (stringify bgt)))
                                           (cond (some? bmax) (str "at most " (stringify bmax))
                                                 (some? blt) (str "less than " (stringify blt)))]))))))

;; A number within a valid $RANGE bound.
(defn- _inrange [bound val]
  (let [bmin (_lookup bound "min")
        bmax (_lookup bound "max")
        bgt (_lookup bound "gt")
        blt (_lookup bound "lt")]
    (and (or (nil? bmin) (<= bmin val))
         (or (nil? bmax) (<= val bmax))
         (or (nil? bgt) (< bgt val))
         (or (nil? blt) (< val blt)))))

;; The bounding list directives: a bound, then at most one spec that must also admit.
(defn- _validatebound [inj store name]
  (let [mode (ig inj :mode) parent (ig inj :parent) keyI (ig inj :keyI)]
    (cond
      (not= mode S-MVAL) nil

      (or (not (islist parent)) (not= keyI 0))
      (do (.add ^List (ig inj :errs) (str "The " name " validator at field " (pathify (ig inj :path) 1 1) " must be the first element of an array.")) nil)

      :else
      (let [[cval held] (_slotval inj)]
        (is! inj :keyI (size (ig inj :keys)))
        ;; As for the counting directives: SKIP keeps inject off the detached list.
        (_slotset inj cval held)
        (is! inj :path (slice (ig inj :path) -1))
        (let [field (str "The " name " validator at field " (pathify (ig inj :path) 1))
              nargs (dec (size parent))]
          (if (or (< nargs 1) (< 2 nargs))
            (.add ^List (ig inj :errs) (str field " must have a bound and at most one spec."))
            (let [bound (_lookup parent 1)
                  islen (= "$LEN" name)
                  [lo hi desc] (if islen (_lenbound bound) [0 0 (_rangedesc bound)])
                  ctype (typify cval)]
              (cond
                (nil? desc)
                (.add ^List (ig inj :errs) (str field " has an invalid bound: " (stringify bound) "."))

                (and (= 2 nargs) (not (_admits cval held (_lookup parent 2) inj store)))
                (let [specdesc (re_replace R-TRANSFORM-NAME (stringify (_lookup parent 2))
                                           (fn [g] (clojure.string/lower-case (nth g 1))))]
                  (.add ^List (ig inj :errs) (_invalidTypeMsg (ig inj :path) specdesc ctype cval "V0410")))

                (zero? (bit-and (if islen (bit-or T_string T_list T_map) T_number) ctype))
                (.add ^List (ig inj :errs)
                      (_invalidTypeMsg (ig inj :path) (if islen "string, list or map" S-number) ctype cval "V0420"))

                ;; size counts a string in UTF-16 units, not code points.
                (not (if islen
                       (let [len (if (string? cval) (.codePointCount ^String cval 0 (.length ^String cval)) (size cval))]
                         (and (<= lo len) (or (== -1 hi) (<= len hi))))
                       (_inrange bound cval)))
                (.add ^List (ig inj :errs)
                      (_invalidTypeMsg (ig inj :path) (str (if (> (size (ig inj :path)) 1) "" "value ") desc) ctype cval "V0430"))))))
        SKIP))))

;; The value's length is within a bound: ['`$LEN`', bound, spec?], where the
;; bound is as for a $NOF count. A string's length is in code points.
(defn- validate_LEN [inj _val _ref store] (_validatebound inj store "$LEN"))

;; The value is a number within a bound: ['`$RANGE`', bound, spec?], where the
;; bound holds min or gt, max or lt, or one of each.
(defn- validate_RANGE [inj _val _ref store] (_validatebound inj store "$RANGE"))

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
                      ;; Literal presence: the shape DECLARES the key even when
                      ;; its value is nil. Canonical uses `NONE === _lookup`;
                      ;; `haskey` is Group A (value-based) and would drop records
                      ;; with a nil field from an open ($AND) select.
                      (let [badkeys (clojure.core/filter
                                     #(not (and (instance? Map pval)
                                                (.containsKey ^Map pval (str %))))
                                     ckeys)]
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

;; Names a validate spec may use besides its checkers: transform's that it keeps, and $OPEN.
(def ^:private VALIDATE-NAMES
  #{"$TOP" "$SPEC" "$BT" "$DS" "$WHEN" "$ANNO" "$REF" "$FORMAT" "$APPLY" "$OPEN"})

;; The name a whole-string reference gives, when it is a checker name in any case.
(defn- _refname [val]
  (let [m (when (string? val) (re_find R-INJECT-FULL val))]
    (when (and (some? m) (re_test R-CHECKER-NAME (.toUpperCase ^String (nth m 1) java.util.Locale/ROOT)))
      (nth m 1))))

;; Unknown: undefined and upper case, or a defined name in another case. Null disables a name.
(defn- _unknownname [name store]
  (let [known (fn [n] (or (contains? VALIDATE-NAMES n) (some? (_lookup store n))))
        upper (.toUpperCase ^String name java.util.Locale/ROOT)]
    (and (not (known name)) (or (= upper name) (known upper)))))

;; Report each checker the spec names that validate lacks; $EXACT's arguments are literals.
(defn- _checknames [spec store path errs]
  (let [name (_refname spec)]
    (cond
      (some? name)
      (when (_unknownname name store)
        (.add ^List errs (str "Unknown validator " name " at field " (pathify (alist-of path)) ".")))

      (and (islist spec) (= "$EXACT" (_refname (_lookup spec 0))))
      nil

      :else
      (doseq [key (keysof spec)]
        (when (ismap spec) (_checknames key store path errs))
        (_checknames (_lookup spec key) store (conj path key) errs)))))

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
                    ["$ANY" validate_ANY] ["$CHILD" validate_CHILD]
                    ["$EXACT" validate_EXACT] ["$NOF" validate_NOF] ["$ALL" validate_ALL]
                    ["$LEN" validate_LEN] ["$RANGE" validate_RANGE]]]
       (.put base k v))
     (let [store (merge (alist-of [base (if (nil? extra) (lhm) extra) (doto (lhm) (.put "$ERRS" errs))]) 1)
           meta (getprop injdef "meta" (lhm))
           numerrs (size errs)]
       (setprop meta S-BEXACT (getprop meta S-BEXACT false))
       ;; A spec that names an unknown checker validates nothing.
       (_checknames spec store [] errs)
       (let [out (if (< numerrs (size errs))
                   (clone data)
                   (transform data spec (doto (lhm)
                                          (.put "meta" meta)
                                          (.put "extra" store)
                                          (.put "modify" _validation)
                                          (.put "handler" _validatehandler)
                                          (.put "errs" errs))))]
         (when (and (> (size errs) 0) (not collect))
           (throw (RuntimeException. (clojure.string/join " | " (vec errs)))))
         out)))))

(defn- _invalidTypeMsg [path needtype vt v _whence]
  (let [novalue (or (nil? v) (identical? v NOARG))
        vs (if novalue "no value" (stringify v))]
    (str "Expected "
         (if (> (size path) 1) (str "field " (pathify path 1) " to be ") "")
         (str needtype)
         ", but found "
         (if novalue "" (str (typename vt) S-VIZ))
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
;; condense
;; ---------------------------------------------------------------------------

;; Code-point order, the order the format sorts symbols in. String.compareTo
;; orders by code unit, which would put U+10000 before U+FFFF.
(defn- condensecmp [^String a ^String b]
  (let [na (.length a) nb (.length b)]
    (loop [i 0 j 0]
      (if (and (< i na) (< j nb))
        (let [ca (.codePointAt a (int i)) cb (.codePointAt b (int j))]
          (if (== ca cb)
            (recur (+ i (Character/charCount ca)) (+ j (Character/charCount cb)))
            (if (< ca cb) -1 1)))
        (compare (- na i) (- nb j))))))

;; The version has to match, not merely be a number: a later format read with
;; this one's schema would decode wrongly without failing.
(defn iscondensed
  ([] false)
  ([val]
   (and (ismap val)
        (let [v (_lookup val S-condense)] (and (number? v) (== v CONDENSE_VERSION)))
        (islist (_lookup val S-condsym))
        (islist (_lookup val S-condnode))
        (number? (_lookup val S-condroot)))))

(defn- condensecollect [val ^java.util.Set acc]
  (cond
    (ismap val) (doseq [k (map-keys val)]
                  (.add acc (str k))
                  (condensecollect (.get ^Map val k) acc))
    (islist val) (doseq [x val] (condensecollect x acc))
    (string? val) (.add acc val))
  acc)

;; An integral number keys as a long, so 1 and 1.0 share one node.
(defn- condensenumkey [n]
  (cond
    (jdouble? n) (let [d (double n)]
                   (if (and (== d (Math/rint d)) (< (Math/abs d) 9.0E18)) (long d) d))
    (instance? Integer n) (long n)
    :else n))

;; Post-order, so a subtree is interned before its parent refers to it, and
;; map pairs in ascending symbol id, so that a lookup can bisect them.
(defn- condensebuild [val ^Map symid intern]
  (cond
    (ismap val)
    (let [enc (alist-of [CONDENSE_MAP])]
      (doseq [k (sort condensecmp (map str (map-keys val)))]
        (.add enc (.get symid k))
        (.add enc (condensebuild (.get ^Map val k) symid intern)))
      (intern enc))

    (islist val)
    (let [enc (alist-of [CONDENSE_LIST])]
      (doseq [x val] (.add enc (condensebuild x symid intern)))
      (intern enc))

    (string? val) (intern (alist-of [CONDENSE_STR (.get symid val)]))
    (and (number? val) (not (jbool? val))) (intern (alist-of [CONDENSE_NUM val]))
    (true? val) (intern (alist-of [CONDENSE_TRUE]))
    (false? val) (intern (alist-of [CONDENSE_FALSE]))
    :else (intern (alist-of [CONDENSE_NULL]))))

(defn condense [val]
  (let [sym (vec (sort condensecmp (condensecollect val (java.util.HashSet.))))
        symid (java.util.HashMap.)
        nodes (alist)
        seen (java.util.HashMap.)
        intern (fn [^List enc]
                 (let [k (mapv condensenumkey enc)
                       hit (.get seen k)]
                   (if (some? hit)
                     hit
                     (let [idx (long (.size nodes))]
                       (.add nodes enc)
                       (.put seen k idx)
                       idx))))]
    (doseq [[i s] (map-indexed vector sym)] (.put symid s (long i)))
    (let [root (condensebuild val symid intern)]
      (doto (lhm)
        (.put S-condense CONDENSE_VERSION)
        (.put S-condsym (alist-of sym))
        (.put S-condnode nodes)
        (.put S-condroot root)))))

;; The string form a key takes, as canonical's '' + key gives it.
(defn- condensekey [key]
  (cond
    (string? key) key
    (jdouble? key) (let [d (double key)]
                     (if (and (== d (Math/rint d)) (< (Math/abs d) 1.0E15)) (str (long d)) (str d)))
    :else (jsstr key)))

(defn- condenseindex [idx]
  (cond
    (integer? idx) idx
    (jdouble? idx) (let [d (double idx)]
                     (when (and (== d (Math/rint d)) (< (Math/abs d) 2.0E9)) (long d)))
    :else nil))

(defn- condensefound [idx] (and (number? idx) (not (neg? idx))))

(defn- condensesym [cd id]
  (let [sym (_lookup cd S-condsym)
        i (condenseindex id)]
    (when (and (islist sym) (some? i) (<= 0 i) (< i (.size ^List sym)))
      (.get ^List sym (int i)))))

;; Node idx as the list of its encoding, or nil when there is no such node.
(defn- condenseenc [cd idx]
  (let [node (_lookup cd S-condnode)
        i (condenseindex idx)]
    (when (and (islist node) (some? i) (<= 0 i) (< i (.size ^List node)))
      (let [enc (.get ^List node (int i))]
        (cond
          (islist enc) enc
          (nil? enc) nil
          :else (alist))))))

(defn- condenseis [^List enc kind]
  (let [k (when (pos? (.size enc)) (.get enc 0))]
    (and (number? k) (== k kind))))

(defn- condensesymid [cd ^String key]
  (let [sym (_lookup cd S-condsym)]
    (if-not (islist sym)
      -1
      (loop [lo 0 hi (dec (.size ^List sym))]
        (if (<= lo hi)
          (let [mid (quot (+ lo hi) 2)
                s (.get ^List sym (int mid))]
            (cond
              (= s key) mid
              (and (string? s) (neg? (condensecmp s key))) (recur (inc mid) hi)
              :else (recur lo (dec mid))))
          -1)))))

(defn- condensechild [cd idx key]
  (let [^List enc (condenseenc cd idx)]
    (cond
      (or (nil? enc) (not (readkey? key))) -1

      (condenseis enc CONDENSE_MAP)
      (let [symid (condensesymid cd (condensekey key))]
        (if (neg? symid)
          -1
          (loop [lo 0 hi (dec (quot (dec (.size enc)) 2))]
            (if (<= lo hi)
              (let [mid (quot (+ lo hi) 2)
                    k (.get enc (int (inc (* 2 mid))))]
                (cond
                  (and (number? k) (== k symid)) (.get enc (int (+ 2 (* 2 mid))))
                  (and (number? k) (< k symid)) (recur (inc mid) hi)
                  :else (recur lo (dec mid))))
              -1))))

      (condenseis enc CONDENSE_LIST)
      (let [i (listindex key)]
        (if (and i (<= 0 i) (< i (dec (.size enc))))
          (.get enc (int (inc i)))
          -1))

      :else -1)))

;; Walk a path from node idx: the node index reached, or -1.
(defn- condenseresolve [cd idx path]
  (let [parts (cond
                (islist path) (vec path)
                (string? path) (if (= path S-MT) [] (vec (.split ^String path "\\." -1)))
                (or (nil? path) (identical? path NOARG)) []
                :else [(condensekey path)])]
    (loop [at idx ps (seq parts)]
      (cond
        (nil? ps) at
        (and (number? at) (neg? at)) -1
        (= S-MT (first ps)) (recur at (next ps))
        :else (recur (condensechild cd at (first ps)) (next ps))))))

;; A fresh tree each call: no materialisation shares a container with another,
;; even where the condensed form shares the node.
(defn- condensematerialise [cd idx]
  (letfn [(rebuild [i]
            (when-let [^List enc (condenseenc cd i)]
              (let [n (.size enc)]
                (cond
                  (condenseis enc CONDENSE_MAP)
                  (let [out (lhm)]
                    (doseq [j (range 1 n 2)]
                      (.put out (condensekey (condensesym cd (.get enc (int j))))
                            (rebuild (when (< (inc j) n) (.get enc (int (inc j)))))))
                    out)

                  (condenseis enc CONDENSE_LIST)
                  (let [out (alist)]
                    (doseq [j (range 1 n)] (.add out (rebuild (.get enc (int j)))))
                    out)

                  (condenseis enc CONDENSE_STR) (when (> n 1) (condensesym cd (.get enc 1)))
                  (condenseis enc CONDENSE_NUM) (when (> n 1) (.get enc 1))
                  (condenseis enc CONDENSE_TRUE) true
                  (condenseis enc CONDENSE_FALSE) false
                  :else nil))))]
    (when-not (and (number? idx) (neg? idx))
      (rebuild idx))))

(defn expand [cd]
  (if (iscondensed cd) (condensematerialise cd (_lookup cd S-condroot)) cd))

(defn- condensekeys [cd idx]
  (let [^List enc (condenseenc cd idx)]
    (cond
      (nil? enc) []
      (condenseis enc CONDENSE_MAP) (mapv #(condensesym cd (.get enc (int %))) (range 1 (.size enc) 2))
      (condenseis enc CONDENSE_LIST) (mapv str (range (dec (.size enc))))
      :else [])))

(defn- condensesize [cd idx]
  (let [^List enc (condenseenc cd idx)]
    (cond
      (nil? enc) 0
      (condenseis enc CONDENSE_MAP) (quot (dec (.size enc)) 2)
      (condenseis enc CONDENSE_LIST) (dec (.size enc))
      :else 0)))

;; A cursor, as a map of closures: :get, :keys, :has and :at take an optional
;; path, the rest take nothing. :ref hands out ONE shared materialisation per
;; node, through a memo every view reached by :at shares; mutating it changes
;; what every other :ref of that node sees.
(defn condenseview
  ([cd] (condenseview cd nil nil))
  ([cd idx] (condenseview cd idx nil))
  ([cd idx memo]
   (let [start (if (nil? idx) (if (iscondensed cd) (_lookup cd S-condroot) -1) idx)
         ^Map refmemo (if (nil? memo) (java.util.HashMap.) memo)
         walkto (fn [path] (condenseresolve cd start path))
         pathfn (fn [f] (fn ([] (f nil)) ([path] (f path))))]
     {:get (pathfn #(condensematerialise cd (walkto %)))
      :keys (pathfn #(condensekeys cd (walkto %)))
      :has (pathfn #(condensefound (walkto %)))
      :at (pathfn #(condenseview cd (walkto %) refmemo))
      :value (fn [] (condensematerialise cd start))
      :size (fn [] (condensesize cd start))
      :exists (fn [] (condensefound start))
      :ref (fn []
             (let [k (condensekey start)]
               (when-not (.containsKey refmemo k)
                 (.put refmemo k (condensematerialise cd start)))
               (.get refmemo k)))})))

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
   :checkPlacement checkPlacement :injectorArgs injectorArgs :injectChild injectChild
   :condense condense :condenseview condenseview :expand expand :iscondensed iscondensed})
