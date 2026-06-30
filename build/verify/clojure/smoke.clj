;; Universal struct smoke: getpath({ db: { host: "localhost" } }, "db.host").
;; Runs against the published com.voxgig/struct-clojure resolved from Clojars.
(ns smoke
  (:require [voxgig.struct :as struct]))

(defn -main [& _]
  (let [got (struct/getpath {"db" {"host" "localhost"}} "db.host")]
    (if (= got "localhost")
      (println "OK clojure: getpath(db.host) = localhost")
      (do
        (println (str "FAIL clojure: getpath(db.host) = " (pr-str got) " (want localhost)"))
        (System/exit 1)))))
