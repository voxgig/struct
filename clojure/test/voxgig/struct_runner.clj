;; The shared corpus, run on the shared runner.
;;
;; The in-situ runner - a JSON reader, `fix-json`, `canon`/`eqv`, `matchval`,
;; `do-match`, `resolve-args`, `check-result` and `handle-error`, all of it
;; this port's own copy of omni's algorithm - is gone. Every group is driven
;; through voxgig/omni, so this file only says WHICH subject answers each group
;; and with which flags.
;;
;; omni is consumed as a local checkout: the Makefile puts its `src` on the
;; test classpath via $OMNI_HOME. Only the tests use it - `deps.edn` never
;; names it, so nothing published depends on omni (register 4.13).
;;
;; Flags mirror canonical: typescript/test/utility/StructUtility.test.ts.

(ns voxgig.struct-runner
  (:require [voxgig.struct :as s]
            [voxgig.omni.runner :as omni]
            [voxgig.omni.util :as ou]
            [clojure.string :as str])
  (:import [java.util LinkedHashMap ArrayList List Map]))

(def NULLMARK "__NULL__")

;; ---------------------------------------------------------------------------
;; The bridge
;; ---------------------------------------------------------------------------

;; omni's model -> this port's. omni holds persistent Clojure data; this port
;; holds MUTABLE java.util collections, because the canonical algorithm rewrites
;; nodes in place and needs them reference-stable. So this really does copy.
;;
;; ABSENT becomes nil, because that is all this port has - one nil for both
;; canonical `undefined` and JSON null, like the Python, Dart and Lua ports.
;; Where the corpus needs the two apart, `run-set` says it by calling the
;; subject with NO argument rather than with nil; see `safe-call`.
;;
;; An integral number comes back as a Long, not a Double. omni's JSON reader
;; parses every numeric token with Double/parseDouble - reasonable for a model
;; whose only number is "JSON number" - but this port's `typify` answers
;; T_integer or T_decimal from the JVM type, so 36 would classify as a decimal
;; and `getelem(list, 0.0)` would miss its index. This port's own reader chose
;; the JVM type from the token, and the corpus has no integral-with-point
;; literal for the two to disagree on. struct/go's shim needed the same
;; normalisation (voxgig/omni#13).
(defn tostruct [val]
  (cond
    (ou/isabsent val) nil
    (ou/ismap val) (let [m (LinkedHashMap.)]
                     (doseq [[k v] val] (.put m (str k) (tostruct v)))
                     m)
    (ou/islist val) (let [a (ArrayList.)]
                      (doseq [v val] (.add a (tostruct v)))
                      a)
    (and (ou/isnum val) (not (integer? val))
         (== (double val) (Math/rint (double val)))
         (< (Math/abs (double val)) 9007199254740992.0))
    (long val)
    :else val))

;; This port's model -> omni's. A function or the NOARG sentinel has no JSON
;; form and omni only ever stringifies one, so it becomes its own rendering
;; rather than silently collapsing to nil.
(defn toomni [val]
  (cond
    (identical? val s/NOARG) ou/ABSENT
    (s/ismap val) (reduce (fn [out k] (assoc out (str k) (toomni (.get ^Map val k))))
                          (array-map)
                          (.keySet ^Map val))
    (s/islist val) (mapv toomni (vec val))
    (s/isfunc val) "[Function]"
    :else val))

;; ---------------------------------------------------------------------------
;; Result tracking
;; ---------------------------------------------------------------------------

(def ^:dynamic *results* nil)

(defn- record! [group ok? msg]
  (swap! *results* update (if ok? :pass :fail) (fnil conj []) {:group group :msg msg}))

(defn- errmsg [^Throwable err]
  (or (.getMessage err) (str err)))

;; ---------------------------------------------------------------------------
;; Running a group
;; ---------------------------------------------------------------------------

;; Each group is one assertion: omni stops at its first failing entry and
;; reports the index, the entry and both values.
;;
;; The subject is handed omni's arguments converted into this port's mutable
;; nodes, and hands the converted arguments BACK - `match.args` asserts an
;; in-place rewrite in eight of `minor/setpath`'s nine entries and all six of
;; `merge/integrity`. Clojure's own data is immutable and the conversion is a
;; copy either way, so returning them alongside the result (omni's
;; `runsetflags-args`) is the only channel there is. rust, cpp, ocaml, elixir
;; and haskell needed the same entry point for the same reason.
;;
;; The subject is VARIADIC - `(apply subject args)` - so a group can name a
;; library function directly, the way this file always has.
;;
;; A ZERO-ARGUMENT entry (no `in`, no `args`, no `ctx`) reaches here as a
;; single ABSENT cell, and this port answers it by calling the subject with no
;; argument at all. That is the honest reading, and it is the only way a port
;; with one nil for both can separate `{in: null, out: T_null}` from
;; `{out: T_noval}` in `minor/typify`. A function with no nullary arity throws
;; ArityException; nil is right for those (isempty, clone, ...), which is the
;; fallback `safe-call` takes.
(defn- safe-call [subject args]
  (if (empty? args)
    (try (subject) (catch clojure.lang.ArityException _ (subject nil)))
    (apply subject args)))

(defn- zeroarg? [cells]
  (and (= 1 (count cells)) (ou/isabsent (first cells))))

(defn run-set
  ([runpack group node subject] (run-set runpack group node {} subject))
  ([runpack group node flags subject]
   (let [donull (get flags "null" true)
         call (fn [cells]
                (let [args (mapv tostruct cells)
                      res (safe-call subject (if (zeroarg? cells) [] args))]
                  [(mapv toomni args) (toomni res)]))]
     (try
       ((:runsetflags-args runpack) (toomni node) {:null donull :name group} call)
       (record! group true nil)
       (catch Throwable err (record! group false (errmsg err)))))))

;; `merge.basic`, `inject.basic` and `transform.basic` are single entries, not
;; sets, so the runner cannot drive them. Compared here, through omni's own
;; deepequal so the rule is the one every group uses.
(defn run-single [group node actual-fn]
  (try
    (let [expected (.get ^Map node "out")
          actual (actual-fn (.get ^Map node "in"))]
      (if (ou/deepequal (toomni expected) (toomni actual))
        (record! group true nil)
        (record! group false (str "Expected: " (s/stringify expected)
                                  ", got: " (s/stringify actual)))))
    (catch Throwable err (record! group false (errmsg err)))))

;; ---------------------------------------------------------------------------
;; Spec access helpers + field getters
;; ---------------------------------------------------------------------------

(defn- gp [^Map m & ks] (reduce (fn [acc k] (when acc (.get ^Map acc k))) m ks))
(defn- vget [vin k] (when (s/ismap vin) (.get ^Map vin k)))
(defn- vhas [vin k] (and (s/ismap vin) (.containsKey ^Map vin k)))

(defn- omap [& kvs]
  (let [m (LinkedHashMap.)]
    (doseq [[k v] (partition 2 kvs)] (.put m k v))
    m))

;; ---------------------------------------------------------------------------
;; Test groups
;; ---------------------------------------------------------------------------

(declare run-walk-log walk-copy-subject walk-depth-subject)

(defn null-modifier [val key parent & _]
  (cond
    (= val NULLMARK) (s/setprop parent key nil)
    (string? val) (s/setprop parent key (str/replace val NULLMARK "null"))))

(defn run-all [runpack spec]
  (let [minor (gp spec "minor")
        walk (gp spec "walk")
        mergeS (gp spec "merge")
        getpathS (gp spec "getpath")
        injectS (gp spec "inject")
        transformS (gp spec "transform")
        validateS (gp spec "validate")
        selectS (gp spec "select")
        sentinels (gp spec "sentinels")
        regexs (gp spec "regex")
        rs (fn rs
             ([group node subject] (run-set runpack group node {} subject))
             ([group node flags subject] (run-set runpack group node flags subject)))]

    ;; minor
    (rs "minor.isnode" (gp minor "isnode") s/isnode)
    (rs "minor.ismap" (gp minor "ismap") s/ismap)
    (rs "minor.islist" (gp minor "islist") s/islist)
    (rs "minor.iskey" (gp minor "iskey") {"null" false} s/iskey)
    (rs "minor.strkey" (gp minor "strkey") {"null" false} s/strkey)
    (rs "minor.isempty" (gp minor "isempty") {"null" false} s/isempty)
    (rs "minor.isfunc" (gp minor "isfunc") s/isfunc)
    (rs "minor.clone" (gp minor "clone") {"null" false} s/clone)
    (rs "minor.escre" (gp minor "escre") s/escre)
    (rs "minor.escurl" (gp minor "escurl") s/escurl)
    (rs "minor.stringify" (gp minor "stringify") {"null" false}
        (fn [vin] (if (vhas vin "val") (s/stringify (vget vin "val") (vget vin "max")) (s/stringify))))
    (rs "minor.jsonify" (gp minor "jsonify") {"null" false}
        (fn [vin] (s/jsonify (vget vin "val") (vget vin "flags"))))
    (rs "minor.getelem" (gp minor "getelem") {"null" false}
        (fn [vin] (let [alt (vget vin "alt")]
                    (if (nil? alt) (s/getelem (vget vin "val") (vget vin "key"))
                        (s/getelem (vget vin "val") (vget vin "key") alt)))))
    (rs "minor.delprop" (gp minor "delprop")
        (fn [vin] (s/delprop (vget vin "parent") (vget vin "key"))))
    (rs "minor.size" (gp minor "size") {"null" false} s/size)
    (rs "minor.slice" (gp minor "slice") {"null" false}
        (fn [vin] (s/slice (vget vin "val") (vget vin "start") (vget vin "end"))))
    (rs "minor.pad" (gp minor "pad") {"null" false}
        (fn [vin] (s/pad (vget vin "val") (vget vin "pad") (vget vin "char"))))
    (rs "minor.pathify" (gp minor "pathify") {"null" false}
        (fn [vin] (if (vhas vin "path") (s/pathify (vget vin "path") (vget vin "from"))
                      (s/pathify s/NOARG (vget vin "from")))))
    (rs "minor.items" (gp minor "items") s/items)
    (rs "minor.getprop" (gp minor "getprop") {"null" false}
        (fn [vin] (let [alt (vget vin "alt")]
                    (if (nil? alt) (s/getprop (vget vin "val") (vget vin "key"))
                        (s/getprop (vget vin "val") (vget vin "key") alt)))))
    (rs "minor.setprop" (gp minor "setprop")
        (fn [vin] (s/setprop (vget vin "parent") (vget vin "key") (vget vin "val"))))
    (rs "minor.haskey" (gp minor "haskey") {"null" false}
        (fn [vin] (s/haskey (vget vin "src") (vget vin "key"))))
    (rs "minor.keysof" (gp minor "keysof") s/keysof)
    (rs "minor.join" (gp minor "join") {"null" false}
        (fn [vin] (s/join (vget vin "val") (vget vin "sep") (vget vin "url"))))
    ;; The one group that needs to tell "no argument" from "a null argument":
    ;; the corpus has both `{in: null, out: T_null}` and `{out: T_noval}`.
    ;; omni supplies ABSENT for the second (register 4.12), and `run-set`
    ;; answers it by invoking `(s/typify)` with no argument at all.
    (rs "minor.typify" (gp minor "typify") {"null" false} s/typify)
    (rs "minor.setpath" (gp minor "setpath") {"null" false}
        (fn [vin] (s/setpath (vget vin "store") (vget vin "path") (vget vin "val"))))
    (rs "minor.filter" (gp minor "filter")
        (let [checkmap {"gt3" (fn [n] (> (nth n 1) 3)) "lt3" (fn [n] (< (nth n 1) 3))}]
          (fn [vin] (s/filter (vget vin "val") (get checkmap (vget vin "check"))))))
    (rs "minor.typename" (gp minor "typename") s/typename)
    (rs "minor.flatten" (gp minor "flatten")
        (fn [vin] (s/flatten (vget vin "val") (vget vin "depth"))))

    ;; walk
    (run-walk-log "walk.log" (gp walk "log"))
    (rs "walk.basic" (gp walk "basic")
        (fn [vin] (s/walk vin (fn [_k val _p path]
                                (if (string? val)
                                  (str val "~" (str/join "." (map str (vec path))))
                                  val)))))
    (rs "walk.copy" (gp walk "copy") walk-copy-subject)
    (rs "walk.depth" (gp walk "depth") {"null" false} walk-depth-subject)

    ;; merge
    (run-single "merge.basic" (gp mergeS "basic") (fn [in] (s/merge (s/clone in))))
    (rs "merge.cases" (gp mergeS "cases") s/merge)
    (rs "merge.array" (gp mergeS "array") s/merge)
    (rs "merge.integrity" (gp mergeS "integrity") s/merge)
    (rs "merge.depth" (gp mergeS "depth")
        (fn [vin] (s/merge (vget vin "val") (vget vin "depth"))))

    ;; getpath
    (rs "getpath.basic" (gp getpathS "basic")
        (fn [vin] (s/getpath (vget vin "store") (vget vin "path"))))
    (rs "getpath.relative" (gp getpathS "relative")
        (fn [vin] (let [dpath (vget vin "dpath")
                        dpath (when (string? dpath) (let [a (ArrayList.)] (doseq [x (.split ^String dpath "\\." -1)] (.add a x)) a))
                        injdef (omap "dparent" (vget vin "dparent") "dpath" dpath)]
                    (s/getpath (vget vin "store") (vget vin "path") injdef))))
    (rs "getpath.special" (gp getpathS "special")
        (fn [vin] (s/getpath (vget vin "store") (vget vin "path") (vget vin "inj"))))
    (rs "getpath.handler" (gp getpathS "handler")
        (fn [vin] (let [handler (fn [inj val ref store] (if (s/isfunc val) (val) val))
                        store (omap "$TOP" (vget vin "store") "$FOO" (fn [& _] "foo"))]
                    (s/getpath store (vget vin "path") (omap "handler" handler)))))

    ;; inject
    (run-single "inject.basic" (gp injectS "basic")
                (fn [in] (s/inject (s/clone (.get ^Map in "val")) (s/clone (.get ^Map in "store")))))
    (rs "inject.string" (gp injectS "string")
        (fn [vin] (s/inject (vget vin "val") (vget vin "store")
                            (omap "modify" null-modifier "extra" (vget vin "current")))))
    (rs "inject.deep" (gp injectS "deep")
        (fn [vin] (s/inject (vget vin "val") (vget vin "store"))))

    ;; transform
    (run-single "transform.basic" (gp transformS "basic")
                (fn [in] (s/transform (.get ^Map in "data") (.get ^Map in "spec") (.get ^Map in "store"))))
    (doseq [g ["paths" "cmds" "each" "pack" "ref"]]
      (rs (str "transform." g) (gp transformS g)
          (fn [vin] (s/transform (vget vin "data") (vget vin "spec") (vget vin "store")))))
    (rs "transform.modify" (gp transformS "modify")
        (fn [vin] (s/transform (vget vin "data") (vget vin "spec")
                               (omap "modify" (fn [val key parent inj]
                                                (when (and (some? key) (some? parent) (string? val))
                                                  (s/setprop parent key (str "@" val))))
                                     "extra" (vget vin "store")))))
    (rs "transform.format" (gp transformS "format") {"null" false}
        (fn [vin] (s/transform (vget vin "data") (vget vin "spec"))))
    (rs "transform.apply" (gp transformS "apply")
        (fn [vin] (s/transform (vget vin "data") (vget vin "spec"))))

    ;; validate
    (rs "validate.basic" (gp validateS "basic") {"null" false}
        (fn [vin] (s/validate (vget vin "data") (vget vin "spec"))))
    (doseq [g ["child" "one" "exact"]]
      (rs (str "validate." g) (gp validateS g)
          (fn [vin] (s/validate (vget vin "data") (vget vin "spec")))))
    (rs "validate.invalid" (gp validateS "invalid") {"null" false}
        (fn [vin] (s/validate (vget vin "data") (vget vin "spec"))))
    (rs "validate.special" (gp validateS "special")
        (fn [vin] (s/validate (vget vin "data") (vget vin "spec") (vget vin "inj"))))

    ;; select
    (doseq [g ["basic" "operators" "edge" "alts"]]
      (rs (str "select." g) (gp selectS g)
          (fn [vin] (s/select (vget vin "obj") (vget vin "query")))))

    ;; `null: false` keeps a JSON null an ACTUAL nil rather than the NULLMARK
    ;; string, so select sees a present-but-null field.
    (rs "select.nullkey" (gp selectS "nullkey") {"null" false}
        (fn [vin] (s/select (vget vin "obj") (vget vin "query"))))

    ;; regex (parity floor: Go stdlib regexp -- see design/REGEX_API.md)
    (rs "regex.test" (gp regexs "test")
        (fn [vin] (s/re_test (vget vin "pattern") (vget vin "input"))))
    (rs "regex.find" (gp regexs "find")
        (fn [vin] (s/re_find (vget vin "pattern") (vget vin "input"))))
    (rs "regex.find_all" (gp regexs "find_all")
        (fn [vin] (s/re_find_all (vget vin "pattern") (vget vin "input"))))
    (rs "regex.replace" (gp regexs "replace")
        (fn [vin] (s/re_replace (vget vin "pattern") (vget vin "input") (vget vin "replacement"))))
    (rs "regex.escape" (gp regexs "escape")
        (fn [vin] (s/re_escape (vget vin "val"))))

    ;; sentinels
    (rs "sentinels.getprop_unify" (gp sentinels "getprop_unify") {"null" false}
        (fn [vin] (s/getprop (vget vin "val") (vget vin "key") (vget vin "alt"))))
    (rs "sentinels.getelem_absent" (gp sentinels "getelem_absent") {"null" false}
        (fn [vin] (s/getelem (vget vin "val") (vget vin "key") (vget vin "alt"))))
    (rs "sentinels.haskey_unify" (gp sentinels "haskey_unify") {"null" false}
        (fn [vin] (s/haskey (vget vin "val") (vget vin "key"))))
    (rs "sentinels.isempty_unify" (gp sentinels "isempty_unify") {"null" false} s/isempty)
    (rs "sentinels.isnode_unify" (gp sentinels "isnode_unify") {"null" false} s/isnode)
    (rs "sentinels.stringify_null" (gp sentinels "stringify_null") {"null" false}
        (fn [vin] (s/stringify vin)))))

;; ---------------------------------------------------------------------------
;; Special walk subjects
;; ---------------------------------------------------------------------------

(defn run-walk-log [group node]
  (try
    (let [test-data (s/clone node)
          log (ArrayList.)
          walklog (fn [key val parent path]
                    (.add log (str "k=" (if (nil? key) (s/stringify) (s/stringify key))
                                   ", v=" (s/stringify val)
                                   ", p=" (if (nil? parent) (s/stringify) (s/stringify parent))
                                   ", t=" (s/pathify path)))
                    val)]
      (s/walk (.get ^Map test-data "in") walklog)
      (let [expected (s/getprop (.get ^Map test-data "out") "after")]
        (if (ou/deepequal (toomni expected) (toomni log))
          (record! group true nil)
          (record! group false (str "Expected: " (s/stringify expected)
                                    ", got: " (s/stringify log))))))
    (catch Throwable e (record! group false (errmsg e)))))

(defn walk-copy-subject [vin]
  (let [cur (atom (doto (ArrayList.) (.add nil)))]
    (letfn [(walkcopy [key val _parent path]
              (if (nil? key)
                (do (reset! cur (doto (ArrayList.) (.add nil)))
                    (.set ^List @cur 0 (cond (s/ismap val) (LinkedHashMap.) (s/islist val) (ArrayList.) :else val))
                    val)
                (let [i (s/size path)
                      v (if (s/isnode val)
                          (let [^List c @cur]
                            (while (<= (.size c) i) (.add c nil))
                            (let [nv (if (s/ismap val) (LinkedHashMap.) (ArrayList.))]
                              (.set c (int i) nv) nv))
                          val)]
                  (s/setprop (.get ^List @cur (int (dec i))) key v)
                  val)))]
      (s/walk vin {:before walkcopy})
      (.get ^List @cur 0))))

(defn walk-depth-subject [vin]
  (let [state (atom {:top nil :cur nil})]
    (letfn [(copy [key val _parent _path]
              (if (or (nil? key) (s/isnode val))
                (let [child (if (s/islist val) (ArrayList.) (LinkedHashMap.))]
                  (if (nil? key)
                    (swap! state assoc :top child :cur child)
                    (do (s/setprop (:cur @state) key child)
                        (swap! state assoc :cur child))))
                (s/setprop (:cur @state) key val))
              val)]
      (s/walk (vget vin "src") {:before copy :maxdepth (vget vin "maxdepth")})
      (:top @state))))

;; ---------------------------------------------------------------------------
;; The client path
;; ---------------------------------------------------------------------------

;; `DEF.client`, client-scoped options, and `contextify`. This port had no such
;; test. It is the only thing that exercises subject resolution through a
;; PROVIDER rather than through a callback this file hands over - so nothing
;; here had ever checked that a corpus `client` key resolves, or that a
;; `DEF.client` entry's options reach the subject.
;;
;; The subject talks to omni DIRECTLY, in omni's own value type: the runner
;; resolves it by name off the provider, so there is no `in` to convert and no
;; result for the bridge to convert back.
(defn- check [options args]
  (let [foo (get options "foo")
        foos (if (ou/isnone foo) "" (ou/stringify foo))
        ctx (first args)
        bar (get-in ctx ["meta" "bar"])
        bars (if (ou/isnone bar) "0" (ou/stringify bar))]
    (array-map "zed" (str "ZED" foos "_" bars))))

(defn- client-provider [options]
  {:subject (fn [name] (when (= "check" name) (fn [args] (check options args))))
   ;; A DEF.client entry becomes another provider, carrying its options.
   :client client-provider
   ;; This port adds nothing to a context; the hook must exist so omni
   ;; installs `client` on it.
   :contextify identity})

(defn run-client [testfile]
  (try
    (let [runner (omni/make-runner testfile (client-provider (array-map)))
          runpack (runner "check")]
      ;; No subject: the runner resolves it by name off the provider, which is
      ;; the whole point of the group.
      ((:runsetflags runpack) ((:set runpack) "basic") {:null true :name "check.basic"} nil)
      (record! "check.basic" true nil))
    (catch Throwable err (record! "check.basic" false (errmsg err)))))

;; ---------------------------------------------------------------------------
;; main
;; ---------------------------------------------------------------------------

(defn -main [& args]
  (let [testfile (or (first args) "../build/test/test.json")
        runner (omni/make-runner testfile)
        runpack (runner "struct")]
    (binding [*results* (atom {:pass [] :fail []})]
      (run-all runpack (tostruct (:spec runpack)))
      (run-client testfile)
      (let [r @*results*
            np (count (:pass r))
            nf (count (:fail r))]
        (doseq [f (:fail r)]
          (println "FAIL" (:group f) "-" (:msg f)))
        (println)
        (println (str (+ np nf) " groups, " nf " failed"))
        (when (pos? nf) (System/exit 1))))))
