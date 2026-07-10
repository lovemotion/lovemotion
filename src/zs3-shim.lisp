;;;; zs3-shim.lisp — teach zs3's ListBucketResult binder the DO dialect.
;;;;
;;;; zs3 (1.3.4) parses bucket listings with a strictly ordered XML
;;;; binder shaped for AWS:
;;;;
;;;;   AWS: Name Prefix Marker [NextMarker] MaxKeys [Delimiter]
;;;;        IsTruncated Contents*            (Owner before StorageClass)
;;;;   DO:  Name Prefix MaxKeys IsTruncated Contents* Marker
;;;;        (StorageClass before Owner, plus a nonstandard <Type>)
;;;;
;;;; Same elements, different order — zs3 signals XML-BINDING-ERROR on
;;;; the DO wire. Binders live in a name-keyed table, so re-running
;;;; DEFBINDER for LIST-BUCKET-RESULT with every dialect difference
;;;; wrapped in OPTIONAL replaces the strict one process-wide; both
;;;; orderings parse. The DSL's operators (BIND, OPTIONAL, SEQUENCE)
;;;; are matched by symbol identity and not exported, hence IN-PACKAGE
;;;; rather than a forest of zs3:: prefixes. Verified against zs3
;;;; 1.3.4 — re-check this file when that pin moves.

(in-package #:zs3)

(defbinder list-bucket-result
  ("ListBucketResult"
   ("Name" (bind :bucket-name))
   ("Prefix" (bind :prefix))
   (optional
    ("Marker" (bind :marker)))            ; AWS position
   (optional
    ("NextMarker" (bind :next-marker)))
   ("MaxKeys" (bind :max-keys))
   (optional
    ("Delimiter" (bind :delimiter)))
   ("IsTruncated" (bind :truncatedp))
   (sequence :keys
             ("Contents"
              ("Key" (bind :key))
              ("LastModified" (bind :last-modified))
              ("ETag" (bind :etag))
              (optional
               ("ChecksumAlgorithm"))
              (optional
               ("ChecksumType"))
              ("Size" (bind :size))
              (optional                    ; AWS: Owner before StorageClass
               ("Owner"
                ("ID" (bind :owner-id))
                (optional ("DisplayName" (bind :owner-display-name)))))
              ("StorageClass" (bind :storage-class))
              (optional                    ; DO: Owner after StorageClass
               ("Owner"
                ("ID" (bind :owner-id))
                (optional ("DisplayName" (bind :owner-display-name)))))
              (optional
               ("Type"))))                 ; DO extension, ignored
   (optional
    ("Marker" (bind :marker)))            ; DO position: after Contents
   (sequence :common-prefixes
             ("CommonPrefixes"
              ("Prefix" (bind :prefix))))))
