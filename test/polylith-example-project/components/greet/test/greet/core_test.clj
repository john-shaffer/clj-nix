(ns greet.core-test
  (:require
   [clojure.test :refer [deftest is]]
   [greet.core :as greet]))

(deftest greeting-test
  (is (= "Hello, you!" (greet/greeting "you"))))
