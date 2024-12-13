(in-package #:org.shirakumo.fraf.trial)

(declaim (type (function (primitive primitive simple-vector (unsigned-byte 32) (unsigned-byte 32)))
               +generic-hit-detector+))
(define-global +generic-hit-detector+ (lambda (a b h s e) s))

;; FIXME: none of these properly take the scaling
;;        of the transform into account.

(defmethod detect-hits ((a primitive) (b 3ds:container) hits start end)
  (declare (type (unsigned-byte 32) start end))
  (declare (type (simple-vector #.(1- (ash 1 32)))))
  (3ds:do-overlapping (element b a start)
    (setf start (detect-hits a element hits start end))
    (when (<= end start)
      (return-from detect-hits start))))

(defmethod detect-hits ((a 3ds:container) (b primitive) hits start end)
  (declare (type (unsigned-byte 32) start end))
  (declare (type (simple-vector #.(1- (ash 1 32)))))
  (3ds:do-overlapping (element a b start)
    (setf start (detect-hits element b hits start end))
    (when (<= end start)
      (return-from detect-hits start))))

(defmethod detect-hits ((sequence sequence) other hits start end)
  (sequences:dosequence (a sequence start)
    (unless (eq a other)
      (setf start (detect-hits a other hits start end))
      (when (<= end start)
        (return-from detect-hits start)))))

(defmethod detect-hits (other (sequence sequence) hits start end)
  (sequences:dosequence (b sequence start)
    (unless (eq b other)
      (setf start (detect-hits other b hits start end))
      (when (<= end start)
        (return-from detect-hits start)))))

(defmethod detect-hits ((container 3ds:container) (self (eql T)) hits start end)
  (declare (type (unsigned-byte 32) start end))
  (declare (type (simple-vector #.(1- (ash 1 32)))))
  (3ds:do-pairs (a b container start)
    (setf start (detect-hits a b hits start end))
    (when (<= end start)
      (return-from detect-hits start))))

(defmethod detect-hits ((sequence sequence) (self (eql T)) hits start end)
  (let ((i 0) (length (length sequence)))
    (sequences:dosequence (a sequence start)
      (loop for j from (1+ i) below length
            for b = (elt sequence j)
            do (setf start (detect-hits a b hits start end))
               (when (<= end start)
                 (return-from detect-hits start)))
      (incf i))))

(define-intersection-test (global-bounds-cache global-bounds-cache)
  (let ((al (varr3 (global-location a)))
        (bl (varr3 (global-location b)))
        (ao (varr3 (global-bounds-cache-box-offset a)))
        (bo (varr3 (global-bounds-cache-box-offset b)))
        (as (varr3 (global-bounds-cache-aabb a)))
        (bs (varr3 (global-bounds-cache-aabb b))))
    (flet ((test (i)
             (<= (abs (- (+ (aref al i) (aref ao i))
                         (+ (aref bl i) (aref bo i))))
                 (+ (aref as i) (aref bs i)))))
      (and (test 0) (test 1) (test 2)))))

(define-hit-detector (global-bounds-cache global-bounds-cache)
  (declare (optimize speed))
  (let ((al (varr3 (global-location a)))
        (bl (varr3 (global-location b)))
        (ao (varr3 (global-bounds-cache-box-offset a)))
        (bo (varr3 (global-bounds-cache-box-offset b)))
        (as (varr3 (global-bounds-cache-aabb a)))
        (bs (varr3 (global-bounds-cache-aabb b))))
    (flet ((test (i)
             (<= (abs (- (+ (aref al i) (aref ao i))
                         (+ (aref bl i) (aref bo i))))
                 (+ (aref as i) (aref bs i)))))
      (when (and (test 0) (test 1) (test 2))
        (!v- (hit-normal hit) (the vec3 (global-location a)) (the vec3 (global-location b)))
        ;; FIXME: compute hit-location
        (setf (hit-a hit) a)
        (setf (hit-b hit) b)
        (incf start)))))

(define-hit-detector (trial:primitive trial:primitive)
  (setf trial:start (funcall +generic-hit-detector+ a b trial:hits trial:start trial:end)))

(define-hit-detector (all-space trial:primitive)
  (global-location b (hit-location hit))
  (setf (hit-depth hit) 0.0)
  (vsetf (hit-normal hit) 0 1 0)
  (finish-hit))

(define-hit-detector (half-space vec3)
  (let ((dist (- (v. (plane-normal a) b)
                 (plane-offset a))))
    (when (< dist 0)
      (v<- (hit-location hit) b)
      (setf (hit-depth hit) (- dist))
      (v<- (hit-normal hit) (plane-normal a))
      (finish-hit))))

(define-distance (sphere sphere)
  (- (vdistance (global-location a) (global-location b))
     (sphere-radius a) (sphere-radius b)))

(define-intersection-test (sphere sphere)
  (< (vdistance (global-location a) (global-location b))
     (+ (sphere-radius a) (sphere-radius b))))

(define-hit-detector (sphere sphere)
  (let ((al (vec3)) (bl (vec3)))
    (declare (dynamic-extent al bl))
    (global-location a al)
    (global-location b bl)
    (let* ((dx (nv- bl al))
           (len (vlength dx)))
      (when (and (< 0 len)
                 (<= len (+ (sphere-radius a) (sphere-radius b))))
        (v<- (hit-normal hit) dx)
        (nv* (hit-normal hit) (/ -1.0 len))
        (v<- (hit-location hit) al)
        (nv+* (hit-location hit) dx 0.5)
        (setf (hit-depth hit) (- (+ (sphere-radius a) (sphere-radius b)) len))
        (finish-hit)))))

(define-distance (sphere half-space)
  (- (v. (plane-normal b) (global-location a))
     (sphere-radius a)
     (plane-offset b)))

(define-intersection-test (sphere half-space)
  (< (v. (plane-normal b) (global-location a))
     (+ (sphere-radius a) (plane-offset b))))

(define-hit-detector (sphere half-space)
  (let* ((al (global-location a))
         (dist (- (v. (plane-normal b) al)
                  (sphere-radius a)
                  (plane-offset b))))
    (when (< dist 0)
      (v<- (hit-normal hit) (plane-normal b))
      (setf (hit-depth hit) (- dist))
      (v<- (hit-location hit) al)
      (nv+* (hit-location hit) (plane-normal b) (- (sphere-radius a)))
      (finish-hit))))

(define-distance (sphere plane)
  (- (abs (- (v. (plane-normal b) (global-location a))
             (plane-offset b)))
     (sphere-radius a)))

(define-intersection-test (sphere plane)
  (< (abs (- (v. (plane-normal b) (global-location a))
             (plane-offset b)))
     (sphere-radius a)))

(define-hit-detector (sphere plane)
  (let* ((al (global-location a))
         (dist (- (v. (plane-normal b) al)
                  (plane-offset b))))
    (when (< (* dist dist) (* (sphere-radius a) (sphere-radius a)))
      (v<- (hit-normal hit) (plane-normal b))
      (setf (hit-depth hit) (- dist))
      (when (< dist 0)
        (nv- (hit-normal hit))
        (setf (hit-depth hit) (- (hit-depth hit))))
      (incf (hit-depth hit) (sphere-radius a))
      (v<- (hit-location hit) al)
      (nv+* (hit-location hit) (hit-normal hit) (- (sphere-radius a)))
      (finish-hit))))

#++(define-intersection-test (sphere pill))
#++(define-distance (sphere pill))
#++(define-hit-detector (sphere pill))

#++(define-intersection-test (sphere cylinder))
#++(define-distance (sphere cylinder))
#++(define-hit-detector (sphere cylinder))

#++(define-intersection-test (sphere box))
#++(define-distance (sphere box))
(define-hit-detector (sphere box)
  (let ((center (vec3))
        (radius (sphere-radius a))
        (bs (box-bsize b)))
    (declare (dynamic-extent center))
    (global-location a center)
    (ntransform-inverse center (box-transform b))
    (unless (or (< (vx bs) (- (abs (vx center)) radius))
                (< (vy bs) (- (abs (vy center)) radius))
                (< (vz bs) (- (abs (vz center)) radius)))
      (let ((closest (vec 0 0 0))
            (dist 0.0))
        (declare (dynamic-extent closest))
        (macrolet ((test-axis (axis)
                     `(progn
                        (setf dist (,axis center))
                        (when (< (,axis bs) dist) (setf dist (,axis bs)))
                        (when (< dist (- (,axis bs))) (setf dist (- (,axis bs))))
                        (setf (,axis closest) dist))))
          (test-axis vx3)
          (test-axis vy3)
          (test-axis vz3))
        (setf dist (vsqrdistance closest center))
        (unless (< (* radius radius) dist)
          (setf (hit-depth hit) (- radius (sqrt dist)))
          (when (< 0.0 (hit-depth hit))
            (n*m (box-transform b) closest)
            (v<- (hit-normal hit) center)
            (n*m (box-transform b) (hit-normal hit))
            (nv- (hit-normal hit) closest)
            (if (= 0 (vsqrlength (hit-normal hit)))
                (v<- (hit-normal hit) +vy3+)
                (nvunit (hit-normal hit)))
            (v<- (hit-location hit) closest)
            (finish-hit)))))))

#++(define-intersection-test (sphere triangle))
#++(define-distance (sphere triangle))
#++(define-hit-detector (sphere triangle))

(define-hit-detector (sphere vec3)
  (let ((al (vec3)))
    (declare (dynamic-extent al))
    (global-location a al)
    (let ((dist (vsqrdistance al b)))
      (when (< dist (* (sphere-radius a) (sphere-radius a)))
        (v<- (hit-location hit) b)
        (setf (hit-depth hit) (sqrt dist))
        (nvunit (!v- (hit-normal hit) b al))
        (finish-hit)))))

#++(define-intersection-test (cylinder half-space))
#++(define-distance (cylinder half-space))
#++(define-hit-detector (cylinder half-space))

#++(define-intersection-test (cylinder plane))
#++(define-distance (cylinder plane))
#++(define-hit-detector (cylinder plane))

#++(define-intersection-test (cylinder pill))
#++(define-distance (cylinder pill))
#++(define-hit-detector (cylinder pill))

#++(define-intersection-test (cylinder cylinder))
#++(define-distance (cylinder cylinder))
#++(define-hit-detector (cylinder cylinder))

#++(define-intersection-test (cylinder triangle))
#++(define-distance (cylinder triangle))
#++(define-hit-detector (cylinder triangle))

(define-hit-detector (cylinder vec3)
  (let ((bl (vcopy b)))
    (declare (dynamic-extent bl))
    (ntransform-inverse bl (primitive-transform a))
    (let ((dist (+ (expt (vx bl) 2) (expt (vz bl) 2))))
      (when (and (< (abs (vy bl)) (cylinder-height a))
                 (< dist (expt (cylinder-radius a) 2)))
        (v<- (hit-location hit) bl)
        (setf (hit-depth hit) (sqrt dist))
        (nvunit (vsetf (hit-normal hit) (vx bl) 0 (vy bl)))
        (finish-hit)))))

#++(define-intersection-test (pill half-space))
#++(define-distance (pill half-space))
#++(define-hit-detector (pill half-space))

#++(define-intersection-test (pill plane))
#++(define-distance (pill plane))
#++(define-hit-detector (pill plane))

#++(define-intersection-test (pill pill))
#++(define-distance (pill pill))
#++(define-hit-detector (pill pill))

#++(define-intersection-test (pill triangle))
#++(define-distance (pill triangle))
#++(define-hit-detector (pill triangle))

(define-hit-detector (pill vec3)
  (let ((bl (vcopy b)))
    (declare (dynamic-extent bl))
    (ntransform-inverse bl (primitive-transform a))
    (let ((dist (+ (expt (vx bl) 2) (expt (vz bl) 2))))
      (when (and (< dist (expt (pill-radius a) 2)))
        (cond ((< (abs (vy bl)) (pill-height a)) ; cylinder hit
               (v<- (hit-location hit) bl)
               (setf (hit-depth hit) (sqrt dist))
               (nvunit (vsetf (hit-normal hit) (vx bl) 0 (vy bl)))
               (finish-hit))
              ((< 0 (vy bl) (+ (pill-height a) (pill-radius a))) ; top sphere hit
               (v<- (hit-location hit) bl)
               (let ((p (vec3 0 (pill-height a) 0)))
                 (declare (dynamic-extent p))
                 (setf (hit-depth hit) (vdistance bl p))
                 (nvunit (!v- (hit-normal hit) bl p)))
               (finish-hit))
              ((< (- (+ (pill-height a) (pill-radius a))) (vy bl) 0) ; bottom sphere hit
               (v<- (hit-location hit) bl)
               (let ((p (vec3 0 (- (pill-height a)) 0)))
                 (declare (dynamic-extent p))
                 (setf (hit-depth hit) (vdistance bl p))
                 (nvunit (!v- (hit-normal hit) bl p)))
               (finish-hit)))))))

#++(define-intersection-test (box half-space))
#++(define-distance (box half-space))
(define-hit-detector (box half-space)
  (let* ((bs (box-bsize a))
         (tf (primitive-transform a))
         (pd (plane-normal b))
         (po (plane-offset b))
         (a (vec3 (+ (vx bs)) (+ (vy bs)) (+ (vz bs))))
         (b (vec3 (- (vx bs)) (+ (vy bs)) (+ (vz bs))))
         (c (vec3 (+ (vx bs)) (- (vy bs)) (+ (vz bs))))
         (d (vec3 (- (vx bs)) (- (vy bs)) (+ (vz bs))))
         (e (vec3 (+ (vx bs)) (+ (vy bs)) (- (vz bs))))
         (f (vec3 (- (vx bs)) (+ (vy bs)) (- (vz bs))))
         (g (vec3 (+ (vx bs)) (- (vy bs)) (- (vz bs))))
         (h (vec3 (- (vx bs)) (- (vy bs)) (- (vz bs)))))
    (declare (dynamic-extent a b c d e f g h))
    (flet ((test (p)
             (n*m tf p)
             (let ((dist (v. p pd)))
               (when (<= dist po)
                 (v<- (hit-location hit) pd)
                 (nv* (hit-location hit) po)
                 (nv+ (hit-location hit) p)
                 (v<- (hit-normal hit) pd)
                 (setf (hit-depth hit) (- po dist))
                 (finish-hit)))))
      (test a)
      (test b)
      (test c)
      (test d)
      (test e)
      (test f)
      (test g)
      (test h))))

#++(define-intersection-test (box cylinder))
#++(define-distance (box cylinder))
#++(define-hit-detector (box cylinder))

#++(define-intersection-test (box pill))
#++(define-distance (box pill))
#++(define-hit-detector (box pill))

#++(define-intersection-test (box triangle))
#++(define-distance (box triangle))
#++(define-hit-detector (box triangle))

(defun box-to-axis (box axis)
  (let ((bs (box-bsize box))
        (tf (box-transform box))
        (col (vec3 0 0 0)))
    (declare (dynamic-extent col))
    (+ (* (vx bs) (abs (v. axis (mcol3 tf 0 col))))
       (* (vy bs) (abs (v. axis (mcol3 tf 1 col))))
       (* (vz bs) (abs (v. axis (mcol3 tf 2 col)))))))

(defun box-depth-on-axis (a b axis center)
  (- (+ (box-to-axis a axis)
        (box-to-axis b axis))
     (abs (v. center axis))))

(defun box-contact-point (apoint aaxis asize bpoint baxis bsize one-p)
  (let* ((a-sqrlen (vsqrlength aaxis))
         (b-sqrlen (vsqrlength baxis))
         (a-b (v. aaxis baxis))
         (to-st (v- apoint bpoint))
         (a-sta (v. aaxis to-st))
         (b-sta (v. baxis to-st))
         (denominator (- (* a-sqrlen b-sqrlen) (* a-b a-b))))
    (declare (dynamic-extent to-st))
    (cond ((< (abs denominator) 0.0001)  ; Some kinda precision constant
           (if one-p apoint bpoint))
          (T
           (let ((mua (/ (- (* a-b b-sta) (* b-sqrlen a-sta)) denominator))
                 (mub (/ (- (* a-sqrlen b-sta) (* a-b a-sta)) denominator)))
             (cond ((or (< asize mua)
                        (< mua (- asize))
                        (< bsize mub)
                        (< mub (- bsize)))
                    (if one-p apoint bpoint))
                   (T
                    (nv+ (nv* (nv+ (v* aaxis mua) apoint) 0.5)
                         (nv* (nv+ (v* baxis mub) bpoint) 0.5)))))))))

#++(define-intersection-test (box box))
#++(define-distance (box box))
(define-hit-detector (box box)
  (let* ((smallest-depth most-positive-single-float)
         (smallest-single most-positive-fixnum)
         (smallest most-positive-fixnum)
         (atf (box-transform a))
         (btf (box-transform b))
         (center (nv- (mcol3 btf 3) (mcol3 atf 3))))
    (block NIL
      (macrolet ((try-axis (axis i)
                   `(let ((axis ,axis))
                      (when (<= 0.0001 (vsqrlength axis))
                        (nvunit axis)
                        (let ((new-depth (box-depth-on-axis a b axis center)))
                          (cond ((< new-depth 0)
                                 (return))
                                ((< new-depth smallest-depth)
                                 (setf smallest-depth new-depth)
                                 (setf smallest ,i)
                                 NIL)))))))
        (try-axis (mcol3 atf 0) 0)
        (try-axis (mcol3 atf 1) 1)
        (try-axis (mcol3 atf 2) 2)
        (try-axis (mcol3 btf 0) 3)
        (try-axis (mcol3 btf 1) 4)
        (try-axis (mcol3 btf 2) 5)
        (setf smallest-single smallest)
        (try-axis (vc (mcol3 atf 0) (mcol3 btf 0)) 6)
        (try-axis (vc (mcol3 atf 0) (mcol3 btf 1)) 7)
        (try-axis (vc (mcol3 atf 0) (mcol3 btf 2)) 8)
        (try-axis (vc (mcol3 atf 1) (mcol3 btf 0)) 9)
        (try-axis (vc (mcol3 atf 1) (mcol3 btf 1)) 10)
        (try-axis (vc (mcol3 atf 1) (mcol3 btf 2)) 11)
        (try-axis (vc (mcol3 atf 2) (mcol3 btf 0)) 12)
        (try-axis (vc (mcol3 atf 2) (mcol3 btf 1)) 13)
        (try-axis (vc (mcol3 atf 2) (mcol3 btf 2)) 14))
      (flet ((point-face ()
               (let ((normal (mcol3 atf smallest)))
                 (when (< 0 (v. normal center))
                   (nv- normal))
                 (let ((vert (vcopy (box-bsize b))))
                   (when (< (v. (mcol3 btf 0) normal) 0) (setf (vx vert) (- (vx vert))))
                   (when (< (v. (mcol3 btf 1) normal) 0) (setf (vy vert) (- (vy vert))))
                   (when (< (v. (mcol3 btf 2) normal) 0) (setf (vz vert) (- (vz vert))))
                   (v<- (hit-normal hit) normal)
                   (v<- (hit-location hit) (n*m btf vert))
                   (setf (hit-depth hit) smallest-depth)
                   (finish-hit)))))
        (cond ((< smallest 3)
               (point-face))
              ((< smallest 6)
               ;; Same algo but in reverse, so just flip it.
               (rotatef a b)
               (rotatef atf btf)
               (decf smallest 3)
               (nv- center)
               (point-face))
              (T
               (decf smallest 6)
               (let* ((aaxis-idx (floor smallest 3))
                      (baxis-idx (mod smallest 3))
                      (aaxis (mcol3 atf aaxis-idx))
                      (baxis (mcol3 btf baxis-idx))
                      (axis (nvunit (vc aaxis baxis)))
                      (aedge-point (vcopy (box-bsize a)))
                      (bedge-point (vcopy (box-bsize b))))
                 (declare (dynamic-extent aaxis baxis axis aedge-point bedge-point))
                 (when (< 0 (v. axis center))
                   (nv- axis))

                 ;; WTF
                 (dotimes (i 3)
                   (cond ((= i aaxis-idx)
                          (setf (vref aedge-point i) 0.0))
                         ((< 0 (v. (mcol3 atf i) axis))
                          (setf (vref aedge-point i) (- (vref aedge-point i)))))
                   (cond ((= i baxis-idx)
                          (setf (vref bedge-point i) 0.0))
                         ((< (v. (mcol3 btf i) axis) 0)
                          (setf (vref bedge-point i) (- (vref bedge-point i))))))
                 
                 (n*m atf aedge-point)
                 (n*m btf bedge-point)

                 (setf (hit-depth hit) smallest-depth)
                 (v<- (hit-normal hit) axis)
                 (v<- (hit-location hit) (box-contact-point aedge-point aaxis (vref (box-bsize a) aaxis-idx)
                                                            bedge-point baxis (vref (box-bsize b) baxis-idx)
                                                            (< 2 smallest-single)))
                 (finish-hit))))))))

(define-hit-detector (box vec3)
  (let* ((atf (primitive-transform a))
         (rel (ntransform-inverse b atf))
         (bsize (box-bsize a))
         (normal (hit-normal hit))
         (min-depth most-positive-single-float))
    (block NIL
      (macrolet ((try-axis (axis i)
                   `(let ((depth (- (,axis bsize) (abs (,axis rel)))))
                      (when (< depth 0) (return))
                      (when (< depth min-depth)
                        (setf min-depth depth)
                        (mcol3 atf ,i normal)
                        (when (< (,axis rel)) (nv- normal))))))
        (try-axis vx 0)
        (try-axis vy 1)
        (try-axis vz 2))
      (v<- (hit-location hit) b)
      (setf (hit-depth hit) min-depth)
      (finish-hit))))

#++(define-intersection-test (triangle triangle))
#++(define-distance (triangle triangle))
#++(define-hit-detector (triangle triangle))

(progn
  (defconstant MPR-HIT-DEPTH-LIMIT 0.1)
  
  (defun detect-hits-mpr+sttb (a b hits start end)
    (declare (optimize speed))
    (declare (type (simple-array hit (*)) hits))
    (declare (type (unsigned-byte 32) start end))
    (let ((start2 (the (unsigned-byte 32) (org.shirakumo.fraf.trial.mpr:detect-hits a b hits start end))))
      (if (and (< start start2) (< MPR-HIT-DEPTH-LIMIT (hit-depth (aref hits start))))
          (org.shirakumo.fraf.trial.sttb:detect-hits a b hits start end)
          start2)))

  (setf +generic-hit-detector+ #'detect-hits-mpr+sttb))
