;; Smoke test for the Clojure test provider port. Prints summary stats that
;; must match the canonical TS output documented in PROVIDER work.
;;
;; Run (once a Clojure toolchain is available), from this directory:
;;   clojure -M smoke.clj
;; or with the file on the classpath:
;;   clojure -M -m voxgig.proto.smoke

(ns voxgig.proto.smoke
  (:require [voxgig.proto.provider :as p]
            [clojure.string :as str]))

(defn- fmt-value
  "Render an expectation value for display: JNULL -> null, strings bare,
   everything else via compact JSON."
  [v]
  (cond
    (= v p/JNULL) "null"
    (string? v) v
    :else (p/compact-json v)))

(defn run []
  (let [prov (p/load)
        fns (p/functions prov)]
    (println (str "functions: " (str/join ", " fns)))

    (let [all (mapcat (fn [fnname] (p/entries prov fnname)) fns)
          total (count all)
          expect-kinds (reduce (fn [acc e]
                                 (update acc (name (get-in e [:expect :kind])) (fnil inc 0)))
                               {} all)
          input-kinds (reduce (fn [acc e]
                                (update acc (name (get-in e [:input :kind])) (fnil inc 0)))
                              {} all)]
      (println (str "total entries: " total))
      (println (str "expect kinds: "
                    (str/join ", " (map (fn [k] (str k "=" (get expect-kinds k)))
                                        (sort (keys expect-kinds))))))
      (println (str "input kinds: "
                    (str/join ", " (map (fn [k] (str k "=" (get input-kinds k)))
                                        (sort (keys input-kinds)))))))

    (let [e (first (p/entries prov "getpath" "basic"))]
      (println (str "getpath/basic[0]: "
                    "id=" (:id e)
                    ", doc=" (:doc e)
                    ", input.kind=" (name (get-in e [:input :kind]))
                    ", expect.kind=" (name (get-in e [:expect :kind]))
                    ", expect.value=" (fmt-value (get-in e [:expect :value])))))

    ;; ─── helper sanity checks ──────────────────────────────────────────────
    (println (str "equal(null, absent) lenient: "
                  (p/equal p/JNULL nil)))
    (println (str "equal-strict distinguishes null vs __NULL__-collapse: "
                  (p/equal-strict nil "__NULL__") " / " (p/equal-strict nil 1)))
    (println (str "error-matches substring case-insensitive: "
                  (p/error-matches {:any false :text "Foo" :regex false} "a foobar error")))
    (println (str "struct-match failure: "
                  (p/struct-match {"a" {"b" 2}} {"a" {"b" 3}})))))

(defn -main [& _] (run))

;; Allow `clojure -M smoke.clj` (script style) to execute directly.
(run)
