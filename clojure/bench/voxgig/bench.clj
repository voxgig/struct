;; Performance bench for the Clojure port. Emits one JSON line per
;; build/bench/README.md; diagnostics go to stderr.
(ns voxgig.bench
  (:require [voxgig.struct :as s]
            [clojure.string :as str])
  (:import [java.util LinkedHashMap ArrayList]))

(defn envi [k d]
  (let [v (System/getenv k)]
    (if (and v (re-matches #"\d+" v)) (Integer/parseInt v) d)))

(defn build [w d leaf]
  (if (zero? d)
    (long leaf)
    (let [m (LinkedHashMap.)]
      (dotimes [i w] (.put m (str "k" i) (build w (dec d) leaf)))
      m)))

(defn nodecount [w d]
  (loop [i 0 p 1 n 0] (if (> i d) n (recur (inc i) (* p w) (+ n p)))))

(def sink (atom 0))

(defn measure [warm runs f]
  (dotimes [_ warm] (f))
  (let [ts (vec (for [_ (range runs)]
                  (let [a (System/nanoTime)] (f) (/ (double (- (System/nanoTime) a)) 1e6))))
        srt (sort ts)]
    {:min_ms (first srt)
     :median_ms (nth srt (quot (count srt) 2))
     :mean_ms (/ (reduce + srt) (count srt))}))

(defn -main [& _]
  (let [W (envi "BENCH_WIDTH" 5) D (envi "BENCH_DEPTH" 6) WARM (envi "BENCH_WARMUP" 3)
        RUNS (envi "BENCH_RUNS" 21) GP (envi "BENCH_GETPATH_ITERS" 2000)
        tree (build W D 0) nodes (nodecount W D)
        treeA (build W D 1) treeB (build W D 2)
        path (str/join "." (repeat D "k0"))
        cb (fn [_k v _p pth] (swap! sink + (count pth)) v)
        mlist (doto (ArrayList.) (.add treeA) (.add treeB))
        specs [["clone" nodes #(when (s/clone tree) (swap! sink inc))]
               ["walk" nodes #(s/walk tree {:before cb})]
               ["merge" nodes #(when (s/merge mlist) (swap! sink inc))]
               ["stringify" nodes #(swap! sink + (count (s/stringify tree)))]
               ["getpath" GP #(swap! sink +
                                (loop [i 0 a 0]
                                  (if (< i GP)
                                    (recur (inc i) (if (= 0 (s/getpath tree path)) (inc a) a))
                                    a)))]]
        ops (doall (for [[op uc f] specs] (merge {:op op :runs RUNS :unit_count uc} (measure WARM RUNS f))))]
    (binding [*out* *err*] (println (str "clojure: sink=" @sink)))
    (println (str "{\"lang\":\"clojure\",\"runtime\":\"clojure " (clojure-version)
                  "\",\"nodes\":" nodes
                  ",\"params\":{\"width\":" W ",\"depth\":" D ",\"warmup\":" WARM
                  ",\"runs\":" RUNS ",\"getpath_iters\":" GP "},\"ops\":["
                  (str/join "," (for [o ops]
                                  (str "{\"op\":\"" (:op o) "\",\"runs\":" (:runs o)
                                       ",\"unit_count\":" (:unit_count o)
                                       ",\"min_ms\":" (double (:min_ms o))
                                       ",\"median_ms\":" (double (:median_ms o))
                                       ",\"mean_ms\":" (double (:mean_ms o)) "}")))
                  "]}"))))
