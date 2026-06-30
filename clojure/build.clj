(ns build
  "Build + Clojars deploy for the Clojure port.

  Usage:
    clojure -T:build jar      ; build target/struct-clojure-<ver>.jar + pom
    clojure -T:build deploy   ; jar, then upload to Clojars

  Deploy auth: deps-deploy reads CLOJARS_USERNAME / CLOJARS_PASSWORD from the
  environment (the password is a Clojars DEPLOY TOKEN, not the account
  password). Clojars does not require GPG signatures, so releases are unsigned."
  (:require [clojure.string :as str]
            [clojure.tools.build.api :as b]
            [deps-deploy.deps-deploy :as dd]))

(def lib 'com.voxgig/struct-clojure)
(def version (str/trim (slurp "VERSION")))
(def class-dir "target/classes")
(def basis (delay (b/create-basis {:project "deps.edn"})))
(def jar-file (format "target/%s-%s.jar" (name lib) version))

(defn clean [_]
  (b/delete {:path "target"}))

(defn jar [_]
  (clean nil)
  (b/write-pom
   {:class-dir class-dir
    :lib lib
    :version version
    :basis @basis
    :src-dirs ["src"]
    :pom-data [[:description
                "Voxgig Struct — utilities for transforming JSON-like data structures (Clojure port)."]
               [:url "https://github.com/voxgig/struct"]
               [:licenses
                [:license
                 [:name "MIT License"]
                 [:url "https://opensource.org/licenses/MIT"]]]
               [:scm
                [:url "https://github.com/voxgig/struct"]
                [:connection "scm:git:https://github.com/voxgig/struct.git"]
                [:developerConnection "scm:git:git@github.com:voxgig/struct.git"]]]})
  (b/copy-dir {:src-dirs ["src"] :target-dir class-dir})
  (b/jar {:class-dir class-dir :jar-file jar-file}))

(defn deploy [_]
  (jar nil)
  (dd/deploy {:installer :remote
              :sign-releases? false
              :artifact (b/resolve-path jar-file)
              :pom-file (b/pom-path {:lib lib :class-dir class-dir})}))
