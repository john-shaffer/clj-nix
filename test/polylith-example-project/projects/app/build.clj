(ns build
  (:require
   [clojure.tools.build.api :as b]))

(def class-dir "target/classes")

(defn uber
  [_]
  (let [basis (b/create-basis)]
    (b/compile-clj {:basis basis
                    :class-dir class-dir
                    :ns-compile ['app.main]})
    (b/uber {:basis basis
             :class-dir class-dir
             :main 'app.main
             :uber-file "target/app.jar"})))
