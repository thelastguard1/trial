#|
 This file is a part of trial
 (c) 2016 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.fraf.trial)
(in-readtable :qtools)

(define-widget main (QGLWidget display input-handler fullscreenable executable window)
  ((scene :initform (make-instance 'scene) :accessor scene)
   (hud :initform (make-instance 'hud) :accessor hud)
   (controller :initform (make-instance 'controller)))
  (:default-initargs
   :name :main))

(define-initializer (main setup -10)
  (setf (q+:window-title main) "Trial")
  (setf (display controller) main)
  (enter controller scene)
  (enter hud scene)
  (issue scene 'reload-scene)
  (start scene))

(define-finalizer (main teardown)
  (v:info :trial.main "RAPTURE")
  (acquire-context main :force T)
  (finalize controller)
  (finalize scene)
  (dolist (pool (pools))
    (mapc #'offload (assets pool))))

(defmethod handle (event (main main))
  (issue (scene main) event))

(defmethod setup-scene :around ((main main))
  (with-simple-restart (continue "Skip loading the rest of the scene and hope for the best.")
    (call-next-method)))

;; FIXME: proper LOADing of a map
(defmethod setup-scene ((main main))
  (let ((scene (scene main)))
    ;;(enter (make-instance 'skybox) scene)
    (enter (make-instance 'space-axes) scene)
    (enter (make-instance 'player) scene)
    (enter (make-instance 'following-camera :name :camera :target (unit :player scene)) scene)
    (enter (make-instance 'selection-buffer :name :selection-buffer) scene)))

(defmethod render :before (source (target main))
  (issue (scene target) 'tick)
  (process (scene target)))

(defmethod paint ((source main) (target main))
  (paint (scene source) target)
  (paint (hud source) target))

(defun launch (&rest initargs)
  (v:output-here)
  (v:info :trial.main "GENESIS")
  #+linux (q+:qcoreapplication-set-attribute (q+:qt.aa_x11-init-threads))
  (with-main-window (window (apply #'make-instance 'main initargs)
                     #-darwin :main-thread #-darwin NIL)))

(defun launch-with-launcher (&rest initargs)
  #+linux (q+:qcoreapplication-set-attribute (q+:qt.aa_x11-init-threads))
  (ensure-qapplication)
  (let ((opts NIL))
    (with-finalizing ((launcher (make-instance 'launcher)))
      (with-main-window (w launcher #-darwin :main-thread #-darwin NIL))
      (setf opts (init-options launcher)))
    (apply #'launch (append initargs opts))))
