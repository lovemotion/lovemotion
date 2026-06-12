(defpackage #:lovemotion.engine.rules.values
  (:use #:cl)
  (:import-from #:lovemotion.engine.rules #:defrule)
  (:import-from #:lovemotion.model.companion
                #:companion-attachment-style #:companion-lifestyle-axes))

(in-package #:lovemotion.engine.rules.values)

;;; Values rules assess core behavioral compatibility.
;;; "Not identical — complementary" is the guiding principle from the spec.
;;; Attachment theory gives us a well-validated compatibility framework here.

(defun attachment-score (style-a style-b)
  "Returns 0.0–1.0 compatibility for a pair of attachment styles.
   Secure as anchor is broadly positive. Anxious+avoidant is the known trap."
  (flet ((s (x) (if x (string-downcase (string x)) nil)))
    (let ((a (s style-a)) (b (s style-b)))
      (cond
        ((or (null a) (null b))                                     0.50) ; unknown — neutral
        ((and (string= a "secure")       (string= b "secure"))      1.00)
        ((and (string= a "secure")       (string= b "anxious"))     0.65)
        ((and (string= a "anxious")      (string= b "secure"))      0.65)
        ((and (string= a "secure")       (string= b "avoidant"))    0.55)
        ((and (string= a "avoidant")     (string= b "secure"))      0.55)
        ((and (string= a "secure")       (string= b "disorganized")) 0.45)
        ((and (string= a "disorganized") (string= b "secure"))      0.45)
        ((and (string= a "anxious")      (string= b "anxious"))     0.35)
        ((and (string= a "avoidant")     (string= b "avoidant"))    0.30)
        ((and (string= a "disorganized") (string= b "disorganized")) 0.25)
        ;; Anxious+avoidant: the pursuer/distancer dynamic — lowest cross-style score
        ((or (and (string= a "anxious")  (string= b "avoidant"))
             (and (string= a "avoidant") (string= b "anxious")))    0.20)
        (t                                                           0.40)))))

(defrule attachment-style-compatibility
  :category :values
  :weight 0.15
  :veto-threshold nil
  :description "Attachment styles are compatible for long-term pairing"
  :evaluate (lambda (a b)
              (attachment-score (companion-attachment-style a)
                                (companion-attachment-style b))))

;;; Lifestyle-axes are a plist of behavioral signals HeyU pushes with each snapshot.
;;; Examples: (:fitness "high" :social "medium" :creativity "high")
;;; We score on Jaccard-like intersection: shared keys with matching values
;;; divided by the union of all keys. Partial overlap is fine — over-alignment
;;; can indicate homophily traps; some divergence enriches pairing.

(defun plist-keys (plist)
  "Return list of keys (every other element starting at 0) from a plist."
  (loop for (k) on plist by #'cddr collect k))

(defun plist-get (plist key)
  "Get value for key in plist; nil if absent."
  (getf plist key))

(defun lifestyle-axes-similarity (axes-a axes-b)
  "Jaccard similarity over shared lifestyle axis keys + value agreement."
  (let* ((keys-a (plist-keys (or axes-a '())))
         (keys-b (plist-keys (or axes-b '())))
         (all-keys (union keys-a keys-b))
         (union-count (length all-keys)))
    (if (zerop union-count)
        0.50                            ; no data from either — neutral
        (let ((match-count
               (count-if (lambda (k)
                           (let ((va (plist-get axes-a k))
                                 (vb (plist-get axes-b k)))
                             (and va vb (equalp va vb))))
                         all-keys)))
          ;; Floor at 0.35: different axes doesn't mean incompatible,
          ;; just signals different self-reporting rather than lifestyle clash.
          (max 0.35 (float (/ match-count union-count)))))))

(defrule lifestyle-axes-alignment
  :category :values
  :weight 0.10
  :veto-threshold nil
  :description "Lifestyle behavioral axes show compatible patterns"
  :evaluate (lambda (a b)
              (lifestyle-axes-similarity (companion-lifestyle-axes a)
                                         (companion-lifestyle-axes b))))
