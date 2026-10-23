(ns app.main
  (:require
   [greet.core :as greet])
  (:gen-class))

(defn -main
  [& _args]
  (println (greet/greeting "Polylith")))
