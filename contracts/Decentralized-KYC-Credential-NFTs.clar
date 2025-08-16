(define-non-fungible-token kyc-credential uint)

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-invalid-status (err u102))
(define-constant err-expired (err u103))
(define-constant err-already-verified (err u104))
(define-constant err-not-found (err u105))

(define-data-var next-id uint u1)
(define-data-var verifier-address principal contract-owner)

(define-map credential-data
  uint 
  {
    owner: principal,
    status: (string-ascii 20),
    expiry: uint,
    verifier: principal,
    level: uint
  }
)

(define-map approved-verifiers principal bool)

(define-public (set-verifier (new-verifier principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set verifier-address new-verifier)
    (ok true)))

(define-public (add-approved-verifier (verifier principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set approved-verifiers verifier true)
    (ok true)))

(define-public (remove-approved-verifier (verifier principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-delete approved-verifiers verifier)
    (ok true)))

(define-public (mint-credential (recipient principal) (level uint) (expiry uint))
  (let 
    (
      (token-id (var-get next-id))
      (verifier tx-sender)
    )
    (asserts! (default-to false (map-get? approved-verifiers verifier)) err-not-authorized)
    (try! (nft-mint? kyc-credential token-id recipient))
    (map-set credential-data token-id
      {
        owner: recipient,
        status: "active",
        expiry: expiry,
        verifier: verifier,
        level: level
      }
    )
    (var-set next-id (+ token-id u1))
    (ok token-id)))

(define-public (revoke-credential (token-id uint))
  (let ((credential (unwrap! (map-get? credential-data token-id) err-not-found)))
    (asserts! (is-eq tx-sender (get verifier credential)) err-not-authorized)
    (map-set credential-data token-id
      (merge credential { status: "revoked" }))
    (ok true)))

(define-public (update-expiry (token-id uint) (new-expiry uint))
  (let ((credential (unwrap! (map-get? credential-data token-id) err-not-found)))
    (asserts! (is-eq tx-sender (get verifier credential)) err-not-authorized)
    (map-set credential-data token-id
      (merge credential { expiry: new-expiry }))
    (ok true)))

(define-public (upgrade-level (token-id uint) (new-level uint))
  (let ((credential (unwrap! (map-get? credential-data token-id) err-not-found)))
    (asserts! (is-eq tx-sender (get verifier credential)) err-not-authorized)
    (map-set credential-data token-id
      (merge credential { level: new-level }))
    (ok true)))

(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender sender) err-not-authorized)
    (nft-transfer? kyc-credential token-id sender recipient)))

(define-read-only (get-credential-data (token-id uint))
  (map-get? credential-data token-id))

(define-read-only (get-token-uri (token-id uint))
  (ok none))

(define-read-only (get-owner (token-id uint))
  (ok (nft-get-owner? kyc-credential token-id)))

(define-read-only (is-active (token-id uint))
  (ok (let ((credential (unwrap! (map-get? credential-data token-id) err-not-found)))
    (and 
      (is-eq (get status credential) "active")
      (> (get expiry credential) burn-block-height)))))
(define-read-only (is-approved-verifier (address principal))
  (default-to false (map-get? approved-verifiers address)))

(define-read-only (get-last-token-id)
  (- (var-get next-id) u1))

(define-public (batch-mint-credentials (recipients (list 50 principal)) (levels (list 50 uint)) (expiries (list 50 uint)))
  (let ((verifier tx-sender))
    (asserts! (default-to false (map-get? approved-verifiers verifier)) err-not-authorized)
    (asserts! (is-eq (len recipients) (len levels)) err-invalid-status)
    (asserts! (is-eq (len recipients) (len expiries)) err-invalid-status)
    (ok (get results (fold batch-mint-fold recipients { levels: levels, expiries: expiries, results: (list), index: u0 })))))

(define-private (batch-mint-fold (recipient principal) (data { levels: (list 50 uint), expiries: (list 50 uint), results: (list 50 uint), index: uint }))
  (let 
    (
      (token-id (var-get next-id))
      (verifier tx-sender)
      (level (unwrap-panic (element-at (get levels data) (get index data))))
      (expiry (unwrap-panic (element-at (get expiries data) (get index data))))
    )
    (match (nft-mint? kyc-credential token-id recipient)
      success (begin
        (map-set credential-data token-id
          {
            owner: recipient,
            status: "active",
            expiry: expiry,
            verifier: verifier,
            level: level
          }
        )
        (var-set next-id (+ token-id u1))
        {
          levels: (get levels data),
          expiries: (get expiries data),
          results: (unwrap-panic (as-max-len? (append (get results data) token-id) u50)),
          index: (+ (get index data) u1)
        })
      error (merge data { index: (+ (get index data) u1) }))))

(define-public (batch-revoke-credentials (token-ids (list 50 uint)))
  (let ((verifier tx-sender))
    (ok (fold batch-revoke-fold token-ids (list)))))

(define-private (batch-revoke-fold (token-id uint) (results (list 50 bool)))
  (match (map-get? credential-data token-id)
    credential (if (is-eq tx-sender (get verifier credential))
      (begin
        (map-set credential-data token-id
          (merge credential { status: "revoked" }))
        (unwrap-panic (as-max-len? (append results true) u50)))
      (unwrap-panic (as-max-len? (append results false) u50)))
    (unwrap-panic (as-max-len? (append results false) u50))))

(define-public (batch-update-expiry (token-ids (list 50 uint)) (new-expiries (list 50 uint)))
  (let ((verifier tx-sender))
    (asserts! (is-eq (len token-ids) (len new-expiries)) err-invalid-status)
    (ok (fold batch-update-expiry-fold token-ids { expiries: new-expiries, results: (list), index: u0 }))))

(define-private (batch-update-expiry-fold (token-id uint) (data { expiries: (list 50 uint), results: (list 50 bool), index: uint }))
  (match (map-get? credential-data token-id)
    credential (let ((new-expiry (unwrap-panic (element-at (get expiries data) (get index data)))))
      (if (is-eq tx-sender (get verifier credential))
        (begin
          (map-set credential-data token-id
            (merge credential { expiry: new-expiry }))
          {
            expiries: (get expiries data),
            results: (unwrap-panic (as-max-len? (append (get results data) true) u50)),
            index: (+ (get index data) u1)
          })
        {
          expiries: (get expiries data),
          results: (unwrap-panic (as-max-len? (append (get results data) false) u50)),
          index: (+ (get index data) u1)
        }))
    {
      expiries: (get expiries data),
      results: (unwrap-panic (as-max-len? (append (get results data) false) u50)),
      index: (+ (get index data) u1)
    }))

    (define-map credential-history
  { token-id: uint, event-id: uint }
  {
    action: (string-ascii 20),
    actor: principal,
    block-height: uint,
    old-value: (optional (string-ascii 50)),
    new-value: (optional (string-ascii 50))
  }
)

(define-map credential-event-count uint uint)

(define-private (log-credential-event (token-id uint) (action (string-ascii 20)) (actor principal) (old-value (optional (string-ascii 50))) (new-value (optional (string-ascii 50))))
  (let 
    (
      (current-count (default-to u0 (map-get? credential-event-count token-id)))
      (new-event-id (+ current-count u1))
    )
    (map-set credential-history 
      { token-id: token-id, event-id: new-event-id }
      {
        action: action,
        actor: actor,
        block-height: burn-block-height,
        old-value: old-value,
        new-value: new-value
      }
    )
    (map-set credential-event-count token-id new-event-id)
    true))

(define-public (mint-credential-with-audit (recipient principal) (level uint) (expiry uint))
  (let 
    (
      (token-id (var-get next-id))
      (verifier tx-sender)
    )
    (asserts! (default-to false (map-get? approved-verifiers verifier)) err-not-authorized)
    (try! (nft-mint? kyc-credential token-id recipient))
    (map-set credential-data token-id
      {
        owner: recipient,
        status: "active",
        expiry: expiry,
        verifier: verifier,
        level: level
      }
    )
    (log-credential-event token-id "minted" verifier none (some "active"))
    (var-set next-id (+ token-id u1))
    (ok token-id)))

(define-public (revoke-credential-with-audit (token-id uint))
  (let ((credential (unwrap! (map-get? credential-data token-id) err-not-found)))
    (asserts! (is-eq tx-sender (get verifier credential)) err-not-authorized)
    (map-set credential-data token-id
      (merge credential { status: "revoked" }))
    (log-credential-event token-id "revoked" tx-sender (some "active") (some "revoked"))
    (ok true)))

(define-public (transfer-with-audit (token-id uint) (sender principal) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender sender) err-not-authorized)
    (try! (nft-transfer? kyc-credential token-id sender recipient))
    (let ((credential (unwrap! (map-get? credential-data token-id) err-not-found)))
      (map-set credential-data token-id
        (merge credential { owner: recipient }))
      (log-credential-event token-id "transferred" sender none none)
      (ok true))))

(define-read-only (get-credential-history (token-id uint) (event-id uint))
  (map-get? credential-history { token-id: token-id, event-id: event-id }))

(define-read-only (get-credential-event-count (token-id uint))
  (default-to u0 (map-get? credential-event-count token-id)))

(define-read-only (get-all-credential-events (token-id uint))
  (let ((event-count (get-credential-event-count token-id)))
    (map get-single-event (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10))))

(define-private (get-single-event (event-id uint))
  (get-credential-history u1 event-id))

(define-read-only (verify-credential-authenticity (token-id uint))
  (let 
    (
      (credential (unwrap! (map-get? credential-data token-id) err-not-found))
      (mint-event (get-credential-history token-id u1))
    )
    (ok {
      is-valid: (is-some mint-event),
      current-status: (get status credential),
      original-verifier: (get verifier credential),
      mint-block: (get block-height (unwrap! mint-event err-not-found))
    })))

(define-map credential-verifications
  { token-id: uint, verifier: principal }
  { count: uint, last-verified: uint }
)

(define-map credential-scores uint uint)

(define-map credential-verifier-count uint uint)

(define-data-var score-decay-factor uint u95)

(define-public (verify-credential (token-id uint))
  (let 
    (
      (credential (unwrap! (map-get? credential-data token-id) err-not-found))
      (verifier tx-sender)
      (current-verification (default-to { count: u0, last-verified: u0 } 
        (map-get? credential-verifications { token-id: token-id, verifier: verifier })))
    )
    (asserts! (is-eq (get status credential) "active") err-invalid-status)
    (asserts! (> (get expiry credential) burn-block-height) err-expired)
    (asserts! (not (is-eq verifier (get verifier credential))) err-not-authorized)
    
    (map-set credential-verifications 
      { token-id: token-id, verifier: verifier }
      { 
        count: (+ (get count current-verification) u1), 
        last-verified: burn-block-height 
      }
    )
    
    (if (is-eq (get count current-verification) u0)
      (map-set credential-verifier-count token-id 
        (+ (default-to u0 (map-get? credential-verifier-count token-id)) u1))
      true)
    
    (let ((new-score (calculate-verification-score token-id)))
      (map-set credential-scores token-id new-score)
      (ok new-score))))

(define-private (calculate-verification-score (token-id uint))
  (let 
    (
      (credential (unwrap-panic (map-get? credential-data token-id)))
      (verifier-count (default-to u0 (map-get? credential-verifier-count token-id)))
      (age-in-blocks (- burn-block-height (get expiry credential)))
      (base-score (* verifier-count u100))
      (time-factor (if (> age-in-blocks u0) 
        (/ (* (var-get score-decay-factor) u100) u100) 
        u100))
    )
    (/ (* base-score time-factor) u100)))

(define-read-only (get-credential-score (token-id uint))
  (default-to u0 (map-get? credential-scores token-id)))

(define-read-only (get-verification-details (token-id uint) (verifier principal))
  (map-get? credential-verifications { token-id: token-id, verifier: verifier }))

(define-read-only (get-verifier-count (token-id uint))
  (default-to u0 (map-get? credential-verifier-count token-id)))

(define-public (set-score-decay-factor (new-factor uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (and (>= new-factor u50) (<= new-factor u100)) err-invalid-status)
    (var-set score-decay-factor new-factor)
    (ok true)))