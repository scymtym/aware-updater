#.(progn
    (ql:quickload '("alexandria" "inferior-shell" "hunchentoot" "cl-who" "drakma"))
    nil)

(cl:defpackage #:cse.aware.updater
  (:use
   #:cl)

  (:shadow
   #:restart)

  (:local-nicknames
   (#:a #:alexandria)
   (#:s #:inferior-shell))

  (:export
   #:main))

(cl:in-package #:cse.aware.updater)

;;; Configuration

(defvar *aware-image*
  "hub-cse.bob.ci.cit-ec.net/aware-wildfly-iata:staging")

(defvar *corlab-github-username*)

(defvar *corlab-github-token*)

;;; Helpers

(defun run (pipeline &rest arguments)
  (apply #'s:run pipeline :output       *standard-output*
                          :error-output *standard-output*
                          arguments))

;;; Systemd service

(defun stop-aware-service ()
  (run '("sudo" "systemctl" "--no-pager" "stop" "aware.service")))

(defun start-aware-service ()
  (run '("sudo" "systemctl" "--no-pager" "start" "aware.service")))

;;; Network

(defun network-connectivity ()
  (let* ((content (with-output-to-string (*standard-output*)
                    (run '("nmcli" "--terse" "general" "status"))))
         (strings (nth-value 1 (ppcre:scan-to-strings "([^:]+):([^:]+):([^:]+):([^:]+):([^:]+):([^:]+)" content))))
    (values (aref strings 0) (aref strings 1) (aref strings 2)
            (aref strings 3) (aref strings 4))))

(defun parse-output (stream)
  (let ((content (a:read-stream-content-into-string stream))
        (result  '()))
    (ppcre:do-register-groups (name value) ("([^:]+):(.*)\\n" content)
      (push (list name value) result))
    result))

(defun connection-information (connection-id)
  (let ((content (handler-case
                     (with-output-to-string (*standard-output*)
                       (run `("nmcli" "--terse" "con" "show" ,connection-id)))
                   (error ()
                     (return-from connection-information nil))))
        ssid key-management ip-address gateway dns)
    (loop :for (name value) :in (parse-output (make-string-input-stream content))
          :when (string= name "802-11-wireless.ssid")
            :do (setf ssid value)
          :when (string= name "802-11-wireless-security.key-mgmt")
            :do (setf key-management value)
          :when (string= name "IP4.ADDRESS[1]")
            :do (setf ip-address value)
          :when (string= name "IP4.GATEWAY")
            :do (setf gateway value)
          :when (string= name "IP4.DNS[1]")
            :do (setf dns value))
    (values ssid key-management ip-address gateway dns)))

(defun connection-up (connection-id)
  (run `("sudo" "nmcli" "connection" "up" ,connection-id)))

(defun connection-down (connection-id)
  (run `("sudo" "nmcli" "connection" "down" ,connection-id)))

;;; Container update

(defun image-hash ()
  (let* ((output (with-output-to-string (*standard-output*)
                   (run '("docker" "inspect" "aware-server"))))
         (strings (nth-value
                   1 (ppcre:scan-to-strings "\"Image\": \"([^\"]+)\"" output))))
    (aref strings 0)))

(defun pull-image ()
  (run `("docker" "pull" ,*aware-image*)))

(defun clone-configuration (clone-directory)
  (let* ((username       *corlab-github-username*)
         (token          *corlab-github-token*)
         (url            (format nil "https://~A:~A@github.com/corlab/aware-config/" username token))
         (name           (a:lastcar (pathname-directory clone-directory)))
         (base-directory (merge-pathnames
                          (make-pathname :directory '(:relative :back))
                          clone-directory)))
    (run `("git" "clone" ,url ,name) :directory base-directory)))

(defun copy-configuration-files (from-directory)
  (let ((to-directory   #P"/home/iata/aware/"))
    (labels ((copy (from-file to-file)
               (format t "~56A -> ~56A~%" from-file to-file)
               (a:copy-file from-file to-file))
             (copy* (from-file to-file)
               (copy (merge-pathnames from-file from-directory)
                     (merge-pathnames to-file   to-directory))))
      (copy* "iata/stages/generic.xml" "aware_data/stages/generic.xml")
      (loop :for from-file :in (directory (merge-pathnames "iata/workplaces/*.xml"
                                                           from-directory))
            :for to-file   =   (merge-pathnames
                                (make-pathname :name      (pathname-name from-file)
                                               :type      (pathname-type from-file)
                                               :directory '(:relative "aware_data" "workplaces"))
                                to-directory)
            :do (copy from-file to-file))
      (loop :for from-file :in (directory (merge-pathnames "iata/statemachines/*.xml"
                                                           from-directory))
            :for to-file   =   (merge-pathnames
                                (make-pathname :name      (pathname-name from-file)
                                               :type      (pathname-type from-file)
                                               :directory '(:relative "aware_data" "statemachines"))
                                to-directory)
            :do (copy from-file to-file)))))

(defun update-configuration ()
  (let ((clone-directory (uiop:ensure-directory-pathname "/tmp/aware-config/")))
    (unwind-protect
         (progn
           (clone-configuration clone-directory)
           (copy-configuration-files clone-directory))
      (uiop:delete-directory-tree clone-directory :validate (constantly t)))))

(defun rebuild-container ()
  (flet ((compose (&rest arguments)
           (run `("docker-compose" "--no-ansi"
                                   ;; "--ansi" "never" ; in newer versions
                                   ,@arguments)
                :directory "/home/iata/aware/")))
    (compose "up" "--build" "--force-recreate" "--no-start")))

(defun update-aware-service ()
  (pull-image)
  (update-configuration)
  (rebuild-container))

;;;

(defun update-aware ()
  (stop-aware-service)
  (update-aware-service)
  (start-aware-service))

;;; Web stuff

(macrolet ((include-resource (name url)
             (let ((variable-name (a:symbolicate '#:* name '#:*))
                   (location      (format nil "/~(~A~)" name)))
               `(progn
                  (defvar ,variable-name
                    (let ((url ,url))
                      (format *trace-output* "; Retrieving ~A~%" url)
                      (drakma:http-request url)))

                  (hunchentoot:define-easy-handler (,name :uri ,location) ()
                    ,variable-name)))))
  (include-resource bootstrap.min.css
                    "https://cdn.jsdelivr.net/npm/bootstrap@5.0.2/dist/css/bootstrap.min.css")
  (include-resource bootstrap.bundle.min.js
                    "https://cdn.jsdelivr.net/npm/bootstrap@5.0.2/dist/js/bootstrap.bundle.min.js"))

(defun include-bootstrap (stream)
  (who:with-html-output (stream)
    (:link :href      "bootstrap.min.css"
           :rel       "stylesheet"
           :integrity "sha384-EVSTQN3/azprG1Anm3QDgpJLIm9Nao0Yz1ztcQTwFspd3yD65VohhpuuCOmLASjC")
    (:script :src       "bootstrap.bundle.min.js"
             :integrity "sha384-MrcW6ZMFYlzcLA8Nl+NtUVF0sA7MsXsP1UyJoMp4YLEuNSfAP+JcXn/tWtIaxVXM")))

(defun button (stream href text &key extra-class)
  (let ((class (format nil "btn~@[ ~A~]" extra-class)))
   (who:with-html-output (stream)
     (:a :class class :href href text))))

(defun render-connection (stream connection-id controllable?)
  (multiple-value-bind (ssid key-management ip-address gateway dns)
      (connection-information connection-id)
    (who:with-html-output (stream)
      (:div :class "col"
            (:div :class "card"
                  (:div :class (if ip-address
                                   "card-header bg-success"
                                   "card-header bg-secondary")
                        (:h5 :class "card-title" (who:fmt "~@(~A~) Connection" connection-id)))
                  (:div :class "card-body"
                        (:table :class "table"
                         (when ssid
                           (who:htm (:tr (:td "SSID") (:td (:code (who:str ssid))))))
                         (when key-management
                           (who:htm (:tr (:td "Key management") (:td (:code (who:str key-management))))))
                         (when ip-address
                           (who:htm (:tr (:td "IP Address") (:td (:code (who:str ip-address))))))
                         (when (and gateway (not (a:emptyp gateway)))
                           (who:htm (:tr (:td "Gateway") (:td (:code (who:str gateway))))))
                         (when dns
                           (who:htm (:tr (:td "DNS Server") (:td (:code (who:str dns)))))))
                        (when controllable?
                          (if ip-address
                              (who:htm
                               (:a :class "btn btn-warning" :href (format nil "connection/down?connection=~A" connection-id)
                                   "Disable"))
                              (who:htm
                               (:a :class "btn btn-primary" :href (format nil "connection/up?connection=~A" connection-id)
                                   "Enable"))))))))))

(hunchentoot:define-easy-handler (home :uri "/") ()
  (who:with-html-output-to-string (stream)
    (:html
     (:head
      (include-bootstrap stream)
      (:title "Home"))
     (:body
      (:div :class "container"
            (:h2 "Network")
            (:div :class "row"
                  (render-connection stream "ethernet" nil)
                  (render-connection stream "wifi" t)
                  ; (render-connection stream "citec" t)
                  )
            (:br)
            (:h2 "AWAre")
            (:p (:a :class "btn btn-primary"
                    :href (let ((ip-address (ppcre:regex-replace "/.*$" (nth-value 2 (connection-information "ethernet")) "")))
                            (format nil "http://~A:8080" ip-address))
                    :target "window"
                    "Open AWAre"))
            (:div :class "row"
                  (:div :class "col"
                        (:div :class "card"
                              (:div :class "card-header"
                                    (:h5 :class "card-title" "Restart AWAre System"))
                              (:div :class "card-body"
                                    (:p :class "card-text" "Restart the AWAre system")
                                    (:div :class "alert alert-info" :role "alert"
                                          "All running process instances will be canceled.")
                                    (:div :class "alert alert-info" :role "alert"
                                          "This can take a while. Intermediate progress is not reported.")
                                    (:a :class "btn btn-warning" :href "restart" "Restart"))))
                  (:div :class "col"
                        (:div :class "card"
                              (:div :class "card-header"
                                    (:h5 :class "card-title" "Update AWAre System"))
                              (:div :class "card-body"
                                    (:p :class "card-text" "Update software and configuration of the AWAre system")
                                    (:p :class "card-text" "Current AWAre image: "
                                        (a:if-let ((hash (ignore-errors (image-hash))))
                                          (who:htm (:code :style "font-size: small" (who:str hash)))
                                          (who:htm (:span :class "text-danger" "???"))))
                                    (:div :class "alert alert-info" :role "alert"
                                          "This can take several minutes. Intermediate progress is not reported.")
                                    (:a :class "btn btn-warning" :href "update" "Update"))))
                  (:div :class "col"
                        (:div :class "card"
                              (:div :class "card-header"
                                    (:h5 :class "card-title" "Show AWAre Logs"))
                              (:div :class "card-body"
                                    (:p :class "card-text" "Shows most recent log entries of the AWAre server")
                                    (:a :class "btn btn-primary" :href "logs" "Logs"))))))))))

(defun call-with-shown-output (stream continuation)
  (who:with-html-output (stream)
    (flet ((out (string)
             (who:str (ppcre:regex-replace-all "[[0-9]+m[[0-9]+m" string ""))))
     (let ((output (make-string-output-stream)))
       (handler-case
           (progn
             (let ((*standard-output* output))
               (funcall continuation))
             (who:htm
              (:div :class "alert alert-success" :role "alert"
                    (:pre (:code (out (let ((output (get-output-stream-string output)))
                                        (if (a:emptyp output)
                                            "«no output»"
                                            output))))))))
         (serious-condition (condition)
           (who:htm
            (:div :class "alert alert-danger" :role "alert"
                  (:pre
                   (:code
                    (out (princ-to-string condition))
                    (out (get-output-stream-string output))))))))))))

(hunchentoot:define-easy-handler (restart :uri "/restart") ()
  (who:with-html-output-to-string (stream)
    (:html
     (:head
      (include-bootstrap stream)
      (:title "Restart"))
     (:body
      (:div :class "container"
            (:h2 "Result")
            (call-with-shown-output
             stream (lambda ()
                      (stop-aware-service)
                      (start-aware-service)))
            (:a :class "btn btn-primary" :href "/" "Back"))))))

(hunchentoot:define-easy-handler (update :uri "/update") ()
  (who:with-html-output-to-string (stream)
    (:html
     (:head
      (include-bootstrap stream)
      (:title "Update"))
     (:body
      (:div :class "container"
            (:h2 "Result")
            (call-with-shown-output stream 'update-aware)
            (:a :class "btn btn-primary" :href "/" "Back"))))))

(hunchentoot:define-easy-handler (logs :uri "/logs") ()
  (who:with-html-output-to-string (stream)
    (:html
     (:head
      (include-bootstrap stream)
      (:title "Logs"))
     (:body
      (:div :class "container"
            (:h2 "Logs")
            (call-with-shown-output
             stream (lambda ()
                      (run '("docker"
                             "logs" "--tail" "1000" "aware-server"))))
            (:a :class "btn btn-primary" :href "/" "Back"))))))

(hunchentoot:define-easy-handler (handler-connection-up :uri "/connection/up") (connection)
  (ignore-errors (connection-up connection))
  (hunchentoot:redirect "/"))

(hunchentoot:define-easy-handler (handler-connection-down :uri "/connection/down") (connection)
  (connection-down connection)
  (hunchentoot:redirect "/"))

(defun main (&key (address "0.0.0.0") (port 4040))
  (let ((terminate? nil)
        (acceptor   (make-instance 'hunchentoot:easy-acceptor
                                   :address address
                                   :port    port)))
    (hunchentoot:start acceptor)
    (format t "Listening on ~A:~A~%" address port)
    (flet ((handler (&rest args)
             (declare (ignore args))
             (format t "Terminating~%")
             (setf terminate? t)))
      (sb-unix::enable-interrupt sb-unix:sigint  #'handler)
      (sb-unix::enable-interrupt sb-unix:sigterm #'handler))
    (unwind-protect
         (loop :until terminate? :do (sleep 2))
      (hunchentoot:stop acceptor))))
