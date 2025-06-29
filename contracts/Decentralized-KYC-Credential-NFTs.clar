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
