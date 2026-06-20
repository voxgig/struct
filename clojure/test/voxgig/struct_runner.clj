;; Test runner for the shared JSON corpus (build/test/test.json).
;; Self-contained: includes a small JSON reader that builds the same mutable
;; Java collections the library uses (LinkedHashMap / ArrayList), so the
;; library is exercised exactly as in production. No third-party deps.

(ns voxgig.struct-runner
  (:require [voxgig.struct :as s]
            [clojure.string :as str])
  (:import [java.util LinkedHashMap ArrayList List Map]))

;; ---------------------------------------------------------------------------
;; Minimal JSON reader -> LinkedHashMap / ArrayList / Long / Double / String /
;; Boolean / nil
;; ---------------------------------------------------------------------------

(defn- json-read [^String s]
  (let [n (count s) pos (int-array 1)]
    (letfn [(peek-c [] (when (< (aget pos 0) n) (.charAt s (aget pos 0))))
            (next-c [] (let [c (.charAt s (aget pos 0))] (aset pos 0 (inc (aget pos 0))) c))
            (skip-ws [] (while (and (< (aget pos 0) n)
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
              (next-c) ;; {
              (let [m (LinkedHashMap.)]
                (skip-ws)
                (if (= (peek-c) \})
                  (do (next-c) m)
                  (loop []
                    (skip-ws)
                    (let [k (parse-str)]
                      (skip-ws) (next-c) ;; :
                      (let [v (parse-val)]
                        (.put m k v))
                      (skip-ws)
                      (let [c (next-c)]
                        (if (= c \,) (recur) m)))))))
            (parse-arr []
              (next-c) ;; [
              (let [a (ArrayList.)]
                (skip-ws)
                (if (= (peek-c) \])
                  (do (next-c) a)
                  (loop []
                    (let [v (parse-val)]
                      (.add a v))
                    (skip-ws)
                    (let [c (next-c)]
                      (if (= c \,) (recur) a))))))
            (parse-str []
              (next-c) ;; opening "
              (let [sb (StringBuilder.)]
                (loop []
                  (let [c (next-c)]
                    (cond
                      (= c \") (.toString sb)
                      (= c \\)
                      (let [e (next-c)]
                        (case e
                          \" (.append sb \") \\ (.append sb \\) \/ (.append sb \/)
                          \n (.append sb \newline) \t (.append sb \tab) \r (.append sb \return)
                          \b (.append sb \backspace) \f (.append sb \formfeed)
                          \u (let [hex (subs s (aget pos 0) (+ (aget pos 0) 4))]
                               (aset pos 0 (+ (aget pos 0) 4))
                               (.append sb (char (Integer/parseInt hex 16))))
                          (.append sb e))
                        (recur))
                      :else (do (.append sb c) (recur)))))))
            (parse-bool []
              (if (= (peek-c) \t)
                (do (aset pos 0 (+ (aget pos 0) 4)) true)
                (do (aset pos 0 (+ (aget pos 0) 5)) false)))
            (parse-null []
              (aset pos 0 (+ (aget pos 0) 4)) nil)
            (parse-num []
              (let [start (aget pos 0)]
                (while (and (< (aget pos 0) n)
                            (let [c (.charAt s (aget pos 0))]
                              (or (Character/isDigit c) (= c \-) (= c \+) (= c \.) (= c \e) (= c \E))))
                  (aset pos 0 (inc (aget pos 0))))
                (let [tok (subs s start (aget pos 0))]
                  (if (or (.contains tok ".") (.contains tok "e") (.contains tok "E"))
                    (Double/parseDouble tok)
                    (Long/parseLong tok)))))]
      (parse-val))))

;; ---------------------------------------------------------------------------
;; fixJSON / canonicalize / equality
;; ---------------------------------------------------------------------------

(def NULLMARK "__NULL__")
(def UNDEFMARK "__UNDEF__")
(def EXISTSMARK "__EXISTS__")

(defn fix-json [v flag-null]
  (cond
    (nil? v) (if flag-null NULLMARK nil)
    (s/ismap v) (let [o (LinkedHashMap.)]
                  (doseq [k (.keySet ^Map v)] (.put o (str k) (fix-json (.get ^Map v k) flag-null)))
                  o)
    (s/islist v) (let [a (ArrayList.)]
                   (doseq [x v] (.add a (fix-json x flag-null)))
                   a)
    :else v))

(defn canon [v]
  (cond
    (s/ismap v) (into (sorted-map) (map (fn [k] [(str k) (canon (.get ^Map v k))]) (.keySet ^Map v)))
    (s/islist v) (mapv canon (vec v))
    :else v))

(defn eqv [a b] (= (canon a) (canon b)))

;; ---------------------------------------------------------------------------
;; match support
;; ---------------------------------------------------------------------------

(defn matchval [check base]
  (let [check (if (or (= check UNDEFMARK) (= check NULLMARK)) nil check)]
    (cond
      (eqv check base) true
      (string? check)
      (let [basestr (s/stringify base)
            m (re-matches #"^/(.+)/$" check)]
        (if m
          (boolean (re-find (re-pattern (second m)) basestr))
          (str/includes? (str/lower-case basestr) (str/lower-case (s/stringify check)))))
      (s/isfunc check) true
      :else false)))

(defn do-match [check base]
  (let [base (s/clone base)]
    (s/walk check
            (fn [_k val _p path]
              (when-not (s/isnode val)
                (let [baseval (s/getpath base path)]
                  (cond
                    (eqv baseval val) nil
                    (and (= val UNDEFMARK) (nil? baseval)) nil
                    (and (= val EXISTSMARK) (some? baseval)) nil
                    (not (matchval val baseval))
                    (throw (AssertionError.
                            (str "MATCH: " (str/join "." (vec path)) ": ["
                                 (s/stringify val) "] <=> [" (s/stringify baseval) "]"))))))
              val))))

;; ---------------------------------------------------------------------------
;; Per-entry runner
;; ---------------------------------------------------------------------------

(defn- omap [& kvs]
  (let [m (LinkedHashMap.)]
    (doseq [[k v] (partition 2 kvs)] (.put m k v))
    m))

(defn- resolve-args [^Map entry subject]
  (cond
    (.containsKey entry "ctx") [(.get entry "ctx")]
    (.containsKey entry "args") (vec (.get entry "args"))
    (.containsKey entry "in") [(s/clone (.get entry "in"))]
    :else []))

(defn- safe-call [subject args]
  (if (empty? args)
    (try (subject) (catch clojure.lang.ArityException _ (subject nil)))
    (apply subject args)))

(defn check-result [^Map entry args res]
  (let [matched (atom false)]
    (when (.containsKey entry "match")
      (do-match (.get entry "match")
                (omap "in" (.get entry "in") "args" (s/clone (ArrayList. ^java.util.Collection args))
                      "out" (.get entry "res") "ctx" (.get entry "ctx")))
      (reset! matched true))
    (let [out (.get entry "out")]
      (cond
        (eqv out res) nil
        (and @matched (or (= out NULLMARK) (nil? out))) nil
        :else
        (throw (AssertionError.
                (str "Expected: " (s/stringify out) ", got: " (s/stringify res))))))))

(defn handle-error [^Map entry err]
  (let [entry-err (when (.containsKey entry "err") (.get entry "err"))
        msg (or (.getMessage ^Throwable err) (str err))]
    (if (.containsKey entry "err")
      (if (or (= entry-err true) (matchval entry-err msg))
        (when (.containsKey entry "match")
          (do-match (.get entry "match")
                    (omap "in" (.get entry "in") "out" (.get entry "res")
                          "ctx" (.get entry "ctx") "err" msg)))
        (throw (AssertionError. (str "ERROR MATCH: [" (s/stringify entry-err) "] <=> [" msg "]"))))
      (throw (if (instance? AssertionError err) err (AssertionError. (str err)))))))

(def ^:dynamic *results* nil)

(defn- record! [group name ok? msg]
  (swap! *results* update (if ok? :pass :fail) (fnil conj []) {:group group :name name :msg msg}))

(defn run-set
  ([group node subject] (run-set group node {} subject))
  ([group node flags subject]
   (let [flag-null (get flags "null" true)
         fixed (fix-json node flag-null)
         testset (.get ^Map fixed "set")]
     (doseq [^Map entry testset]
       (try
         (when (and (not (.containsKey entry "out")) flag-null)
           (.put entry "out" NULLMARK))
         (let [args (resolve-args entry subject)
               res (fix-json (safe-call subject args) flag-null)]
           (.put entry "res" res)
           (check-result entry args res))
         (record! group (str (.get entry "name")) true nil)
         (catch Throwable err
           (try
             (handle-error entry err)
             (record! group (str (.get entry "name")) true nil)
             (catch Throwable e2
               (record! group (str (.get entry "name")) false (.getMessage e2))))))))))

(defn run-single
  "For the few specs that are a single {in,out} rather than a {set}."
  [group node actual-fn]
  (try
    (let [expected (.get ^Map node "out")
          actual (actual-fn (.get ^Map node "in"))]
      (if (eqv expected actual)
        (record! group "single" true nil)
        (record! group "single" false (str "Expected: " (s/stringify expected) ", got: " (s/stringify actual)))))
    (catch Throwable e (record! group "single" false (.getMessage e)))))

;; ---------------------------------------------------------------------------
;; Spec access helpers + field getters
;; ---------------------------------------------------------------------------

(defn- gp [^Map m & ks] (reduce (fn [acc k] (when acc (.get ^Map acc k))) m ks))
(defn- vget [vin k] (when (s/ismap vin) (.get ^Map vin k)))
(defn- vhas [vin k] (and (s/ismap vin) (.containsKey ^Map vin k)))

;; ---------------------------------------------------------------------------
;; Test groups
;; ---------------------------------------------------------------------------

(declare run-walk-log walk-copy-subject walk-depth-subject)

(defn null-modifier [val key parent & _]
  (cond
    (= val NULLMARK) (s/setprop parent key nil)
    (string? val) (s/setprop parent key (str/replace val NULLMARK "null"))))

(defn run-all [spec]
  (let [minor (gp spec "minor")
        walk (gp spec "walk")
        mergeS (gp spec "merge")
        getpathS (gp spec "getpath")
        injectS (gp spec "inject")
        transformS (gp spec "transform")
        validateS (gp spec "validate")
        selectS (gp spec "select")
        sentinels (gp spec "sentinels")]

    ;; minor
    (run-set "minor.isnode" (gp minor "isnode") s/isnode)
    (run-set "minor.ismap" (gp minor "ismap") s/ismap)
    (run-set "minor.islist" (gp minor "islist") s/islist)
    (run-set "minor.iskey" (gp minor "iskey") {"null" false} s/iskey)
    (run-set "minor.strkey" (gp minor "strkey") {"null" false} s/strkey)
    (run-set "minor.isempty" (gp minor "isempty") {"null" false} s/isempty)
    (run-set "minor.isfunc" (gp minor "isfunc") s/isfunc)
    (run-set "minor.clone" (gp minor "clone") {"null" false} s/clone)
    (run-set "minor.escre" (gp minor "escre") s/escre)
    (run-set "minor.escurl" (gp minor "escurl") s/escurl)
    (run-set "minor.stringify" (gp minor "stringify") {"null" false}
             (fn [vin] (if (vhas vin "val") (s/stringify (vget vin "val") (vget vin "max")) (s/stringify))))
    (run-set "minor.jsonify" (gp minor "jsonify") {"null" false}
             (fn [vin] (s/jsonify (vget vin "val") (vget vin "flags"))))
    (run-set "minor.getelem" (gp minor "getelem") {"null" false}
             (fn [vin] (let [alt (vget vin "alt")]
                         (if (nil? alt) (s/getelem (vget vin "val") (vget vin "key"))
                             (s/getelem (vget vin "val") (vget vin "key") alt)))))
    (run-set "minor.delprop" (gp minor "delprop")
             (fn [vin] (s/delprop (vget vin "parent") (vget vin "key"))))
    (run-set "minor.size" (gp minor "size") {"null" false} s/size)
    (run-set "minor.slice" (gp minor "slice") {"null" false}
             (fn [vin] (s/slice (vget vin "val") (vget vin "start") (vget vin "end"))))
    (run-set "minor.pad" (gp minor "pad") {"null" false}
             (fn [vin] (s/pad (vget vin "val") (vget vin "pad") (vget vin "char"))))
    (run-set "minor.pathify" (gp minor "pathify") {"null" false}
             (fn [vin] (if (vhas vin "path") (s/pathify (vget vin "path") (vget vin "from"))
                           (s/pathify s/NOARG (vget vin "from")))))
    (run-set "minor.items" (gp minor "items") s/items)
    (run-set "minor.getprop" (gp minor "getprop") {"null" false}
             (fn [vin] (let [alt (vget vin "alt")]
                         (if (nil? alt) (s/getprop (vget vin "val") (vget vin "key"))
                             (s/getprop (vget vin "val") (vget vin "key") alt)))))
    (run-set "minor.setprop" (gp minor "setprop")
             (fn [vin] (s/setprop (vget vin "parent") (vget vin "key") (vget vin "val"))))
    (run-set "minor.haskey" (gp minor "haskey") {"null" false}
             (fn [vin] (s/haskey (vget vin "src") (vget vin "key"))))
    (run-set "minor.keysof" (gp minor "keysof") s/keysof)
    (run-set "minor.join" (gp minor "join") {"null" false}
             (fn [vin] (s/join (vget vin "val") (vget vin "sep") (vget vin "url"))))
    (run-set "minor.typify" (gp minor "typify") {"null" false} s/typify)
    (run-set "minor.setpath" (gp minor "setpath") {"null" false}
             (fn [vin] (s/setpath (vget vin "store") (vget vin "path") (vget vin "val"))))
    (run-set "minor.filter" (gp minor "filter")
             (let [checkmap {"gt3" (fn [n] (> (nth n 1) 3)) "lt3" (fn [n] (< (nth n 1) 3))}]
               (fn [vin] (s/filter (vget vin "val") (get checkmap (vget vin "check"))))))
    (run-set "minor.typename" (gp minor "typename") s/typename)
    (run-set "minor.flatten" (gp minor "flatten")
             (fn [vin] (s/flatten (vget vin "val") (vget vin "depth"))))

    ;; walk
    (run-walk-log "walk.log" (gp walk "log"))
    (run-set "walk.basic" (gp walk "basic")
             (fn [vin] (s/walk vin (fn [_k val _p path]
                                     (if (string? val)
                                       (str val "~" (str/join "." (map str (vec path))))
                                       val)))))
    (run-set "walk.copy" (gp walk "copy") walk-copy-subject)
    (run-set "walk.depth" (gp walk "depth") {"null" false} walk-depth-subject)

    ;; merge
    (run-single "merge.basic" (gp mergeS "basic") (fn [in] (s/merge (s/clone in))))
    (run-set "merge.cases" (gp mergeS "cases") s/merge)
    (run-set "merge.array" (gp mergeS "array") s/merge)
    (run-set "merge.integrity" (gp mergeS "integrity") s/merge)
    (run-set "merge.depth" (gp mergeS "depth")
             (fn [vin] (s/merge (vget vin "val") (vget vin "depth"))))

    ;; getpath
    (run-set "getpath.basic" (gp getpathS "basic")
             (fn [vin] (s/getpath (vget vin "store") (vget vin "path"))))
    (run-set "getpath.relative" (gp getpathS "relative")
             (fn [vin] (let [dpath (vget vin "dpath")
                             dpath (when (string? dpath) (let [a (ArrayList.)] (doseq [x (.split ^String dpath "\\." -1)] (.add a x)) a))
                             injdef (omap "dparent" (vget vin "dparent") "dpath" dpath)]
                         (s/getpath (vget vin "store") (vget vin "path") injdef))))
    (run-set "getpath.special" (gp getpathS "special")
             (fn [vin] (s/getpath (vget vin "store") (vget vin "path") (vget vin "inj"))))
    (run-set "getpath.handler" (gp getpathS "handler")
             (fn [vin] (let [handler (fn [inj val ref store] (if (s/isfunc val) (val) val))
                             store (omap "$TOP" (vget vin "store") "$FOO" (fn [& _] "foo"))]
                         (s/getpath store (vget vin "path") (omap "handler" handler)))))

    ;; inject
    (run-single "inject.basic" (gp injectS "basic")
                (fn [in] (s/inject (s/clone (.get ^Map in "val")) (s/clone (.get ^Map in "store")))))
    (run-set "inject.string" (gp injectS "string")
             (fn [vin] (s/inject (vget vin "val") (vget vin "store")
                                 (omap "modify" null-modifier "extra" (vget vin "current")))))
    (run-set "inject.deep" (gp injectS "deep")
             (fn [vin] (s/inject (vget vin "val") (vget vin "store"))))

    ;; transform
    (run-single "transform.basic" (gp transformS "basic")
                (fn [in] (s/transform (.get ^Map in "data") (.get ^Map in "spec") (.get ^Map in "store"))))
    (doseq [g ["paths" "cmds" "each" "pack" "ref"]]
      (run-set (str "transform." g) (gp transformS g)
               (fn [vin] (s/transform (vget vin "data") (vget vin "spec") (vget vin "store")))))
    (run-set "transform.modify" (gp transformS "modify")
             (fn [vin] (s/transform (vget vin "data") (vget vin "spec")
                                    (omap "modify" (fn [val key parent inj]
                                                     (when (and (some? key) (some? parent) (string? val))
                                                       (s/setprop parent key (str "@" val))))
                                          "extra" (vget vin "store")))))
    (run-set "transform.format" (gp transformS "format") {"null" false}
             (fn [vin] (s/transform (vget vin "data") (vget vin "spec"))))
    (run-set "transform.apply" (gp transformS "apply")
             (fn [vin] (s/transform (vget vin "data") (vget vin "spec"))))

    ;; validate
    (run-set "validate.basic" (gp validateS "basic") {"null" false}
             (fn [vin] (s/validate (vget vin "data") (vget vin "spec"))))
    (doseq [g ["child" "one" "exact"]]
      (run-set (str "validate." g) (gp validateS g)
               (fn [vin] (s/validate (vget vin "data") (vget vin "spec")))))
    (run-set "validate.invalid" (gp validateS "invalid") {"null" false}
             (fn [vin] (s/validate (vget vin "data") (vget vin "spec"))))
    (run-set "validate.special" (gp validateS "special")
             (fn [vin] (s/validate (vget vin "data") (vget vin "spec") (vget vin "inj"))))

    ;; select
    (doseq [g ["basic" "operators" "edge" "alts"]]
      (run-set (str "select." g) (gp selectS g)
               (fn [vin] (s/select (vget vin "obj") (vget vin "query")))))

    ;; sentinels
    (run-set "sentinels.getprop_unify" (gp sentinels "getprop_unify") {"null" false}
             (fn [vin] (s/getprop (vget vin "val") (vget vin "key") (vget vin "alt"))))
    (run-set "sentinels.getelem_absent" (gp sentinels "getelem_absent") {"null" false}
             (fn [vin] (s/getelem (vget vin "val") (vget vin "key") (vget vin "alt"))))
    (run-set "sentinels.haskey_unify" (gp sentinels "haskey_unify") {"null" false}
             (fn [vin] (s/haskey (vget vin "val") (vget vin "key"))))
    (run-set "sentinels.isempty_unify" (gp sentinels "isempty_unify") {"null" false} s/isempty)
    (run-set "sentinels.isnode_unify" (gp sentinels "isnode_unify") {"null" false} s/isnode)
    (run-set "sentinels.stringify_null" (gp sentinels "stringify_null") {"null" false}
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
      (if (eqv (s/getprop (.get ^Map test-data "out") "after") log)
        (record! group "log" true nil)
        (record! group "log" false (str "Expected: " (s/stringify (s/getprop (.get ^Map test-data "out") "after"))
                                        ", got: " (s/stringify log)))))
    (catch Throwable e (record! group "log" false (.getMessage e)))))

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
;; main
;; ---------------------------------------------------------------------------

(defn -main [& args]
  (let [testfile (or (first args) "../build/test/test.json")
        raw (slurp testfile)
        alltests (json-read raw)
        spec (.get ^Map alltests "struct")]
    (binding [*results* (atom {:pass [] :fail []})]
      (run-all spec)
      (let [r @*results*
            np (count (:pass r))
            nf (count (:fail r))]
        (doseq [f (:fail r)]
          (println "FAIL" (:group f) (:name f) "-" (:msg f)))
        (println)
        (println (str "PASS " np "  FAIL " nf))
        (when (pos? nf) (System/exit 1))))))
