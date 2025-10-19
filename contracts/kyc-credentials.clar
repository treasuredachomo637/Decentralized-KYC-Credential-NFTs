;; =====================================
;; KYC Credential NFTs with Reputation System
;; =====================================
;; A comprehensive decentralized KYC solution with verifier reputation tracking

(define-non-fungible-token kyc-credential uint)

;; Error constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-invalid-status (err u102))
(define-constant err-expired (err u103))
(define-constant err-already-verified (err u104))
(define-constant err-not-found (err u105))
(define-constant err-insufficient-payment (err u106))
(define-constant err-request-not-found (err u107))
(define-constant err-request-expired (err u108))
(define-constant err-already-fulfilled (err u109))
(define-constant err-invalid-listing (err u110))
(define-constant err-invalid-rating (err u111))
(define-constant err-self-rating (err u112))
(define-constant err-no-interaction (err u113))
(define-constant err-already-rated (err u114))
(define-constant err-reputation-locked (err u115))

;; Data variables
(define-data-var next-id uint u1)
(define-data-var verifier-address principal contract-owner)
(define-data-var next-request-id uint u1)
(define-data-var score-decay-factor uint u95)
(define-data-var min-ratings-for-badge uint u10)
(define-data-var excellence-threshold uint u90) ;; 4.5 out of 5 stars (90/100)
(define-data-var veteran-threshold uint u100) ;; 100 credentials issued

;; Core data structures
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

(define-map verification-requests
  uint
  {
    requester: principal,
    credential-level: uint,
    payment-amount: uint,
    expiry-block: uint,
    status: (string-ascii 20),
    selected-credential: (optional uint)
  }
)

(define-map credential-listings
  { token-id: uint, request-id: uint }
  {
    price: uint,
    available: bool
  }
)

(define-map marketplace-earnings principal uint)

;; =====================================
;; VERIFIER REPUTATION & RATING SYSTEM
;; =====================================

;; Data structures for reputation system
(define-map verifier-ratings
  { verifier: principal, rater: principal }
  {
    rating: uint,
    comment: (string-ascii 100),
    block-height: uint,
    credential-id: (optional uint)
  }
)

(define-map verifier-reputation-stats
  principal
  {
    total-ratings: uint,
    rating-sum: uint,
    average-rating: uint,
    last-updated: uint,
    credentials-issued: uint,
    successful-verifications: uint
  }
)

(define-map user-verifier-interactions
  { user: principal, verifier: principal }
  {
    has-credential: bool,
    last-interaction: uint,
    interaction-count: uint
  }
)

(define-map reputation-badges
  principal
  {
    trusted-verifier: bool,
    veteran-verifier: bool,
    excellence-badge: bool,
    community-choice: bool
  }
)

;; =====================================
;; CORE CONTRACT FUNCTIONS
;; =====================================

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
    
    ;; Record verifier interaction for reputation system
    (unwrap-panic (record-verifier-interaction recipient verifier true))
    
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
    (try! (nft-transfer? kyc-credential token-id sender recipient))
    (let ((credential (unwrap! (map-get? credential-data token-id) err-not-found)))
      (map-set credential-data token-id
        (merge credential { owner: recipient })))
    (ok true)))

;; =====================================
;; MARKETPLACE FUNCTIONS
;; =====================================

(define-public (create-verification-request (credential-level uint) (payment-amount uint) (duration-blocks uint))
  (let 
    (
      (request-id (var-get next-request-id))
      (expiry-block (+ burn-block-height duration-blocks))
    )
    (try! (stx-transfer? payment-amount tx-sender (as-contract tx-sender)))
    (map-set verification-requests request-id
      {
        requester: tx-sender,
        credential-level: credential-level,
        payment-amount: payment-amount,
        expiry-block: expiry-block,
        status: "active",
        selected-credential: none
      }
    )
    (var-set next-request-id (+ request-id u1))
    (ok request-id)))

(define-public (list-credential-for-request (token-id uint) (request-id uint) (price uint))
  (let 
    (
      (credential (unwrap! (map-get? credential-data token-id) err-not-found))
      (request (unwrap! (map-get? verification-requests request-id) err-request-not-found))
      (token-owner (unwrap! (nft-get-owner? kyc-credential token-id) err-not-found))
    )
    (asserts! (is-eq tx-sender token-owner) err-not-authorized)
    (asserts! (is-eq (get status credential) "active") err-invalid-status)
    (asserts! (>= (get level credential) (get credential-level request)) err-invalid-listing)
    (asserts! (is-eq (get status request) "active") err-invalid-status)
    (asserts! (> (get expiry-block request) burn-block-height) err-request-expired)
    (asserts! (<= price (get payment-amount request)) err-insufficient-payment)
    
    (map-set credential-listings { token-id: token-id, request-id: request-id }
      {
        price: price,
        available: true
      }
    )
    (ok true)))

;; =====================================
;; REPUTATION SYSTEM FUNCTIONS
;; =====================================

(define-public (rate-verifier (verifier principal) (rating uint) (comment (string-ascii 100)) (credential-id (optional uint)))
  (let 
    (
      (rater tx-sender)
      (interaction (map-get? user-verifier-interactions { user: rater, verifier: verifier }))
      (existing-rating (map-get? verifier-ratings { verifier: verifier, rater: rater }))
    )
    ;; Validation checks
    (asserts! (and (>= rating u1) (<= rating u5)) err-invalid-rating)
    (asserts! (not (is-eq rater verifier)) err-self-rating)
    (asserts! (is-some interaction) err-no-interaction)
    (asserts! (is-none existing-rating) err-already-rated)
    
    ;; Store the rating
    (map-set verifier-ratings 
      { verifier: verifier, rater: rater }
      {
        rating: (* rating u20), ;; Convert to 100-point scale
        comment: comment,
        block-height: burn-block-height,
        credential-id: credential-id
      }
    )
    
    ;; Update verifier reputation stats
    (update-verifier-reputation verifier)
    
    ;; Check and award badges
    (unwrap-panic (update-verifier-badges verifier))
    
    (ok true)))

(define-public (update-rating (verifier principal) (new-rating uint) (new-comment (string-ascii 100)))
  (let 
    (
      (rater tx-sender)
      (existing-rating (unwrap! (map-get? verifier-ratings { verifier: verifier, rater: rater }) err-not-found))
    )
    (asserts! (and (>= new-rating u1) (<= new-rating u5)) err-invalid-rating)
    
    (map-set verifier-ratings 
      { verifier: verifier, rater: rater }
      (merge existing-rating 
        {
          rating: (* new-rating u20),
          comment: new-comment,
          block-height: burn-block-height
        }
      )
    )
    
    (update-verifier-reputation verifier)
    (unwrap-panic (update-verifier-badges verifier))
    (ok true)))

(define-public (record-verifier-interaction (user principal) (verifier principal) (has-credential bool))
  (let ((current-interaction (default-to 
    { has-credential: false, last-interaction: u0, interaction-count: u0 }
    (map-get? user-verifier-interactions { user: user, verifier: verifier }))))
    
    (map-set user-verifier-interactions
      { user: user, verifier: verifier }
      {
        has-credential: (or (get has-credential current-interaction) has-credential),
        last-interaction: burn-block-height,
        interaction-count: (+ (get interaction-count current-interaction) u1)
      }
    )
    
    ;; Update verifier stats if issuing credential
    (if has-credential
      (let ((stats (get-verifier-stats verifier)))
        (map-set verifier-reputation-stats verifier
          (merge stats 
            { 
              credentials-issued: (+ (get credentials-issued stats) u1),
              last-updated: burn-block-height 
            }
          )
        )
        true)
      true)
    (ok true)))

;; =====================================
;; PRIVATE HELPER FUNCTIONS
;; =====================================

(define-private (update-verifier-reputation (verifier principal))
  (let 
    (
      (current-stats (get-verifier-stats verifier))
      (new-ratings-data (calculate-verifier-ratings verifier))
    )
    (map-set verifier-reputation-stats verifier
      (merge current-stats 
        {
          total-ratings: (get total new-ratings-data),
          rating-sum: (get sum new-ratings-data),
          average-rating: (get average new-ratings-data),
          last-updated: burn-block-height
        }
      )
    )))

(define-private (calculate-verifier-ratings (verifier principal))
  ;; Simplified calculation - in production would iterate through all ratings
  (let ((stats (get-verifier-stats verifier)))
    {
      total: (+ (get total-ratings stats) u1),
      sum: (+ (get rating-sum stats) u80), ;; Default 4-star rating for demo
      average: (/ (+ (get rating-sum stats) u80) (+ (get total-ratings stats) u1))
    }))

(define-private (get-verifier-stats (verifier principal))
  (default-to 
    {
      total-ratings: u0,
      rating-sum: u0,
      average-rating: u0,
      last-updated: u0,
      credentials-issued: u0,
      successful-verifications: u0
    }
    (map-get? verifier-reputation-stats verifier)))

(define-private (update-verifier-badges (verifier principal))
  (let 
    (
      (stats (get-verifier-stats verifier))
      (current-badges (default-to 
        { trusted-verifier: false, veteran-verifier: false, excellence-badge: false, community-choice: false }
        (map-get? reputation-badges verifier)))
    )
    ;; Award badges based on criteria
    (map-set reputation-badges verifier
      {
        trusted-verifier: (>= (get total-ratings stats) (var-get min-ratings-for-badge)),
        veteran-verifier: (>= (get credentials-issued stats) (var-get veteran-threshold)),
        excellence-badge: (and 
          (>= (get total-ratings stats) (var-get min-ratings-for-badge))
          (>= (get average-rating stats) (var-get excellence-threshold))),
        community-choice: (>= (get total-ratings stats) u50) ;; High engagement
      }
    )
    (ok true)))

;; =====================================
;; READ-ONLY FUNCTIONS
;; =====================================

;; Core read functions
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

;; Reputation system read functions
(define-read-only (get-verifier-rating (verifier principal) (rater principal))
  (map-get? verifier-ratings { verifier: verifier, rater: rater }))

(define-read-only (get-verifier-reputation (verifier principal))
  (map-get? verifier-reputation-stats verifier))

(define-read-only (get-verifier-badges (verifier principal))
  (map-get? reputation-badges verifier))

(define-read-only (get-user-interaction (user principal) (verifier principal))
  (map-get? user-verifier-interactions { user: user, verifier: verifier }))

(define-read-only (can-rate-verifier (user principal) (verifier principal))
  (let 
    (
      (interaction (map-get? user-verifier-interactions { user: user, verifier: verifier }))
      (existing-rating (map-get? verifier-ratings { verifier: verifier, rater: user }))
    )
    (and 
      (not (is-eq user verifier))
      (is-some interaction)
      (get has-credential (unwrap! interaction false))
      (is-none existing-rating))))

(define-read-only (get-verifier-rating-summary (verifier principal))
  (let ((stats (get-verifier-stats verifier)))
    {
      average-rating: (get average-rating stats),
      total-ratings: (get total-ratings stats),
      credentials-issued: (get credentials-issued stats),
      rating-out-of-5: (/ (get average-rating stats) u20)
    }))

(define-read-only (is-trusted-verifier (verifier principal))
  (let 
    (
      (badges (map-get? reputation-badges verifier))
      (stats (get-verifier-stats verifier))
    )
    (and 
      (is-some badges)
      (get trusted-verifier (unwrap! badges false))
      (>= (get average-rating stats) u60)))) ;; At least 3 stars

;; Marketplace read functions
(define-read-only (get-verification-request (request-id uint))
  (map-get? verification-requests request-id))

(define-read-only (get-credential-listing (token-id uint) (request-id uint))
  (map-get? credential-listings { token-id: token-id, request-id: request-id }))

(define-read-only (get-marketplace-earnings (user principal))
  (default-to u0 (map-get? marketplace-earnings user)))

;; =====================================
;; ADMIN FUNCTIONS
;; =====================================

(define-public (set-reputation-thresholds (min-ratings uint) (excellence uint) (veteran uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (and (> min-ratings u0) (<= min-ratings u100)) err-invalid-rating)
    (asserts! (and (>= excellence u60) (<= excellence u100)) err-invalid-rating)
    (asserts! (and (>= veteran u10) (<= veteran u1000)) err-invalid-rating)
    
    (var-set min-ratings-for-badge min-ratings)
    (var-set excellence-threshold excellence)
    (var-set veteran-threshold veteran)
    (ok true)))

(define-public (reset-verifier-reputation (verifier principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-delete verifier-reputation-stats verifier)
    (map-delete reputation-badges verifier)
    (ok true)))
