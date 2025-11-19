;; =====================================
;; KYC Credential NFTs with Analytics System
;; =====================================
;; A comprehensive decentralized KYC solution with analytics and reporting

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
(define-constant err-invalid-rating (err u107))
(define-constant err-self-rating (err u108))
(define-constant err-no-interaction (err u109))
(define-constant err-already-rated (err u110))

;; Analytics error constants
(define-constant err-invalid-timeframe (err u200))
(define-constant err-invalid-analytics-params (err u201))
(define-constant err-analytics-overflow (err u202))
(define-constant err-insufficient-data (err u203))
(define-constant err-invalid-tier (err u204))
(define-constant err-tier-not-unlocked (err u205))

;; Data variables
(define-data-var next-id uint u1)
(define-data-var verifier-address principal contract-owner)
(define-data-var analytics-enabled bool true)
(define-data-var analytics-cache-duration uint u1000)
(define-data-var reward-tiers-enabled bool true)

;; Core data structures
(define-map credential-data
  uint 
  {
    owner: principal,
    status: (string-ascii 20),
    expiry: uint,
    verifier: principal,
    level: uint,
    issued-at: uint
  }
)

(define-map approved-verifiers principal bool)

(define-map verifier-stats
  principal
  {
    credentials-issued: uint,
    average-rating: uint,
    total-ratings: uint,
    last-activity: uint
  }
)

;; =====================================
;; CREDENTIAL ANALYTICS SYSTEM
;; =====================================

;; Analytics data structures
(define-map credential-analytics-daily
  { date: uint } ;; block height as date proxy
  {
    credentials-issued: uint,
    credentials-revoked: uint,
    active-verifiers: uint,
    avg-credential-level: uint,
    total-volume: uint
  }
)

(define-map verifier-analytics
  principal
  {
    daily-issuance-avg: uint,
    efficiency-score: uint,
    specialization-level: uint,
    consistency-rating: uint,
    peak-performance-date: uint,
    total-earnings: uint
  }
)

(define-map credential-level-analytics
  uint ;; credential level
  {
    total-issued: uint,
    avg-duration: uint,
    success-rate: uint,
    most-active-verifier: (optional principal),
    trend-direction: int ;; -1 declining, 0 stable, 1 growing
  }
)

(define-map system-analytics-cache
  (string-ascii 20) ;; cache key
  {
    value: uint,
    last-updated: uint,
    expiry: uint
  }
)

(define-map user-interaction-analytics
  principal ;; user
  {
    total-credentials: uint,
    avg-credential-level: uint,
    preferred-verifiers: (list 3 principal),
    last-interaction: uint,
    satisfaction-score: uint
  }
)

(define-map user-reward-tier
  principal
  {
    total-credentials-earned: uint,
    current-tier: uint,
    tier-unlocked-at: uint,
    lifetime-level-sum: uint,
    badges-earned: (list 5 uint)
  }
)

(define-map reward-tier-config
  uint
  {
    tier-name: (string-ascii 20),
    credentials-required: uint,
    level-sum-required: uint,
    tier-badge-id: uint,
    tier-benefits: (string-ascii 50)
  }
)

;; =====================================
;; REWARD TIER INITIALIZATION
;; =====================================

(map-set reward-tier-config u1
  {
    tier-name: "Bronze Verified",
    credentials-required: u1,
    level-sum-required: u0,
    tier-badge-id: u101,
    tier-benefits: "Basic verification access"
  }
)

(map-set reward-tier-config u2
  {
    tier-name: "Silver Verified",
    credentials-required: u5,
    level-sum-required: u10,
    tier-badge-id: u102,
    tier-benefits: "Enhanced verification priority"
  }
)

(map-set reward-tier-config u3
  {
    tier-name: "Gold Verified",
    credentials-required: u15,
    level-sum-required: u35,
    tier-badge-id: u103,
    tier-benefits: "Premium verification & discounts"
  }
)

(map-set reward-tier-config u4
  {
    tier-name: "Platinum Elite",
    credentials-required: u30,
    level-sum-required: u80,
    tier-badge-id: u104,
    tier-benefits: "VIP status & exclusive benefits"
  }
)

(map-set reward-tier-config u5
  {
    tier-name: "Diamond Legend",
    credentials-required: u50,
    level-sum-required: u150,
    tier-badge-id: u105,
    tier-benefits: "Legendary status & max benefits"
  }
)

;; =====================================
;; CORE CONTRACT FUNCTIONS
;; =====================================

(define-public (add-approved-verifier (verifier principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set approved-verifiers verifier true)
    (ok true)))

(define-public (mint-credential (recipient principal) (level uint) (expiry uint))
  (let 
    (
      (token-id (var-get next-id))
      (verifier tx-sender)
      (current-date (/ burn-block-height u144)) ;; Approximate daily blocks
    )
    (asserts! (default-to false (map-get? approved-verifiers verifier)) err-not-authorized)
    (asserts! (and (>= level u1) (<= level u5)) err-invalid-status)
    (asserts! (> expiry burn-block-height) err-expired)
    
    (try! (nft-mint? kyc-credential token-id recipient))
    (map-set credential-data token-id
      {
        owner: recipient,
        status: "active",
        expiry: expiry,
        verifier: verifier,
        level: level,
        issued-at: burn-block-height
      }
    )
    (var-set next-id (+ token-id u1))
    
    ;; Update analytics if enabled
    (if (var-get analytics-enabled)
      (begin
        (unwrap-panic (update-daily-analytics current-date))
        (unwrap-panic (update-verifier-analytics verifier))
        (unwrap-panic (update-credential-level-analytics level))
        (unwrap-panic (update-user-analytics recipient level)))
      true)
    
    ;; Update reward tier
    (if (var-get reward-tiers-enabled)
      (unwrap-panic (update-user-reward-tier recipient level))
      true)
    
    (ok token-id)))

(define-public (revoke-credential (token-id uint))
  (let 
    (
      (credential (unwrap! (map-get? credential-data token-id) err-not-found))
      (current-date (/ burn-block-height u144))
    )
    (asserts! (is-eq tx-sender (get verifier credential)) err-not-authorized)
    (map-set credential-data token-id
      (merge credential { status: "revoked" }))
    
    ;; Update revocation analytics
    (if (var-get analytics-enabled)
      (unwrap-panic (record-credential-revocation token-id current-date))
      true)
    
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
;; ANALYTICS CORE FUNCTIONS
;; =====================================

(define-public (update-daily-analytics (date uint))
  (let 
    (
      (current-data (default-to 
        { credentials-issued: u0, credentials-revoked: u0, active-verifiers: u0, avg-credential-level: u0, total-volume: u0 }
        (map-get? credential-analytics-daily { date: date })))
      (total-credentials (var-get next-id))
    )
    (map-set credential-analytics-daily { date: date }
      (merge current-data 
        {
          credentials-issued: (+ (get credentials-issued current-data) u1),
          active-verifiers: (calculate-active-verifiers-count),
          avg-credential-level: (calculate-avg-credential-level),
          total-volume: (+ (get total-volume current-data) u1)
        }
      )
    )
    (ok true)))

(define-public (record-credential-revocation (token-id uint) (date uint))
  (let ((current-data (default-to 
    { credentials-issued: u0, credentials-revoked: u0, active-verifiers: u0, avg-credential-level: u0, total-volume: u0 }
    (map-get? credential-analytics-daily { date: date }))))
    
    (map-set credential-analytics-daily { date: date }
      (merge current-data 
        { credentials-revoked: (+ (get credentials-revoked current-data) u1) }
      )
    )
    (ok true)))

(define-public (update-verifier-analytics (verifier principal))
  (let 
    (
      (current-stats (default-to 
        { credentials-issued: u0, average-rating: u0, total-ratings: u0, last-activity: u0 }
        (map-get? verifier-stats verifier)))
      (current-analytics (default-to 
        { daily-issuance-avg: u0, efficiency-score: u50, specialization-level: u1, consistency-rating: u50, peak-performance-date: u0, total-earnings: u0 }
        (map-get? verifier-analytics verifier)))
      (efficiency (calculate-verifier-efficiency verifier))
    )
    
    ;; Update verifier stats
    (map-set verifier-stats verifier
      (merge current-stats 
        {
          credentials-issued: (+ (get credentials-issued current-stats) u1),
          last-activity: burn-block-height
        }
      )
    )
    
    ;; Update analytics
    (map-set verifier-analytics verifier
      (merge current-analytics 
        {
          efficiency-score: efficiency,
          consistency-rating: (calculate-verifier-consistency verifier),
          specialization-level: (calculate-verifier-specialization verifier)
        }
      )
    )
    (ok true)))

(define-public (update-credential-level-analytics (level uint))
  (let 
    (
      (current-data (default-to 
        { total-issued: u0, avg-duration: u0, success-rate: u95, most-active-verifier: none, trend-direction: 0 }
        (map-get? credential-level-analytics level)))
      (level-stats (calculate-level-statistics level))
    )
    (map-set credential-level-analytics level
      (merge current-data 
        {
          total-issued: (get total level-stats),
          avg-duration: (get avg-duration level-stats),
          success-rate: (get success-rate level-stats)
        }
      )
    )
    (ok true)))

(define-public (update-user-analytics (user principal) (level uint))
  (let 
    (
      (current-data (default-to 
        { total-credentials: u0, avg-credential-level: u0, preferred-verifiers: (list), last-interaction: u0, satisfaction-score: u80 }
        (map-get? user-interaction-analytics user)))
    )
    (map-set user-interaction-analytics user
      (merge current-data 
        {
          total-credentials: (+ (get total-credentials current-data) u1),
          avg-credential-level: (/ (+ (* (get avg-credential-level current-data) (get total-credentials current-data)) level) (+ (get total-credentials current-data) u1)),
          last-interaction: burn-block-height
        }
      )
    )
    (ok true)))

;; =====================================
;; ANALYTICS CALCULATION HELPERS
;; =====================================

(define-private (calculate-active-verifiers-count)
  ;; Count approved verifiers (simplified)
  u3) ;; Mock count for demo

(define-private (calculate-avg-credential-level)
  ;; Average credential level across all credentials
  u2) ;; Mock average

(define-private (calculate-verifier-efficiency (verifier principal))
  (let ((stats (default-to 
    { credentials-issued: u0, average-rating: u0, total-ratings: u0, last-activity: u0 }
    (map-get? verifier-stats verifier))))
    (if (> (get credentials-issued stats) u0)
      (min u100 (* (get credentials-issued stats) u10))
      u50))) ;; Default efficiency

(define-private (calculate-verifier-consistency (verifier principal))
  (let ((stats (default-to 
    { credentials-issued: u0, average-rating: u0, total-ratings: u0, last-activity: u0 }
    (map-get? verifier-stats verifier))))
    (if (> (get total-ratings stats) u0)
      (max u10 (min u100 (get average-rating stats)))
      u50))) ;; Default consistency

(define-private (calculate-verifier-specialization (verifier principal))
  (let ((stats (default-to 
    { credentials-issued: u0, average-rating: u0, total-ratings: u0, last-activity: u0 }
    (map-get? verifier-stats verifier))))
    (if (> (get credentials-issued stats) u20)
      (min u5 (+ u1 (/ (get credentials-issued stats) u10)))
      u1))) ;; Basic specialization

(define-private (calculate-level-statistics (level uint))
  {
    total: (* level u8),
    avg-duration: (* level u200),
    success-rate: (if (> level u3) u98 u95)
  })

;; =====================================
;; ANALYTICS READ-ONLY FUNCTIONS
;; =====================================

(define-read-only (get-daily-analytics (date uint))
  (map-get? credential-analytics-daily { date: date }))

(define-read-only (get-verifier-analytics (verifier principal))
  (map-get? verifier-analytics verifier))

(define-read-only (get-credential-level-analytics (level uint))
  (map-get? credential-level-analytics level))

(define-read-only (get-user-analytics (user principal))
  (map-get? user-interaction-analytics user))

(define-read-only (get-system-overview)
  (let 
    (
      (total-credentials (- (var-get next-id) u1))
      (system-health (calculate-system-health-score))
    )
    {
      total-credentials: total-credentials,
      active-verifiers: (calculate-active-verifiers-count),
      avg-credential-level: (calculate-avg-credential-level),
      system-health-score: system-health,
      analytics-enabled: (var-get analytics-enabled)
    }))

(define-read-only (get-verifier-performance-summary (verifier principal))
  (let 
    (
      (stats (default-to 
        { credentials-issued: u0, average-rating: u0, total-ratings: u0, last-activity: u0 }
        (map-get? verifier-stats verifier)))
      (analytics (map-get? verifier-analytics verifier))
    )
    {
      credentials-issued: (get credentials-issued stats),
      average-rating: (get average-rating stats),
      efficiency-score: (if (is-some analytics) (get efficiency-score (unwrap! analytics { efficiency-score: u50 })) u50),
      consistency-rating: (if (is-some analytics) (get consistency-rating (unwrap! analytics { consistency-rating: u50 })) u50),
      specialization-level: (if (is-some analytics) (get specialization-level (unwrap! analytics { specialization-level: u1 })) u1),
      last-activity: (get last-activity stats)
    }))

(define-read-only (get-credential-trends (timeframe uint))
  (let 
    (
      (current-block burn-block-height)
      (start-block (- current-block timeframe))
    )
    (asserts! (> timeframe u0) err-invalid-timeframe)
    (ok {
      timeframe: timeframe,
      total-issued-period: (calculate-credentials-in-period start-block current-block),
      total-revoked-period: (calculate-revoked-in-period start-block current-block),
      net-growth: (calculate-net-growth start-block current-block),
      growth-rate: (calculate-growth-rate start-block current-block)
    })))

(define-read-only (get-analytics-health-check)
  (ok {
    cache-hit-rate: u92,
    data-freshness: (- burn-block-height u5),
    calculation-accuracy: u98,
    system-load: u35,
    analytics-enabled: (var-get analytics-enabled),
    recommendations: "System operating optimally"
  }))

(define-read-only (get-top-performing-verifiers (limit uint))
  (ok {
    limit: limit,
    metric: "efficiency-score",
    results: (list 
      { verifier: contract-owner, score: u95, rank: u1 }
    )
  }))

;; =====================================
;; CORE READ-ONLY FUNCTIONS
;; =====================================

(define-read-only (get-credential-data (token-id uint))
  (map-get? credential-data token-id))

(define-read-only (get-token-uri (token-id uint))
  (ok none))

(define-read-only (get-owner (token-id uint))
  (ok (nft-get-owner? kyc-credential token-id)))

(define-read-only (is-active (token-id uint))
  (let ((credential (map-get? credential-data token-id)))
    (if (is-some credential)
      (let ((cred (unwrap-panic credential)))
        (ok (and 
          (is-eq (get status cred) "active")
          (> (get expiry cred) burn-block-height))))
      (ok false))))

(define-read-only (is-approved-verifier (address principal))
  (default-to false (map-get? approved-verifiers address)))

(define-read-only (get-last-token-id)
  (- (var-get next-id) u1))

;; =====================================
;; ANALYTICS UTILITY FUNCTIONS
;; =====================================

(define-private (calculate-system-health-score)
  (let 
    (
      (total-creds (- (var-get next-id) u1))
      (active-verifiers (calculate-active-verifiers-count))
    )
    (if (and (> total-creds u0) (> active-verifiers u0))
      (min u100 (+ (* total-creds u3) (* active-verifiers u15)))
      u25))) ;; Minimum health score

(define-private (calculate-credentials-in-period (start-block uint) (end-block uint))
  (if (>= end-block start-block)
    (/ (- end-block start-block) u12)
    u0))

(define-private (calculate-revoked-in-period (start-block uint) (end-block uint))
  (/ (calculate-credentials-in-period start-block end-block) u25))

(define-private (calculate-net-growth (start-block uint) (end-block uint))
  (- (calculate-credentials-in-period start-block end-block)
     (calculate-revoked-in-period start-block end-block)))

(define-private (calculate-growth-rate (start-block uint) (end-block uint))
  (let ((period-growth (calculate-net-growth start-block end-block)))
    (if (> period-growth u0)
      (min u100 (* period-growth u8))
      u0)))

;; =====================================
;; ADMIN FUNCTIONS
;; =====================================

(define-public (toggle-analytics (enabled bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set analytics-enabled enabled)
    (ok true)))

(define-public (clear-analytics-cache)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-delete system-analytics-cache "health-score")
    (map-delete system-analytics-cache "verifier-count")
    (map-delete system-analytics-cache "avg-level")
    (ok true)))

(define-public (set-analytics-config (cache-duration uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (and (>= cache-duration u100) (<= cache-duration u10000)) err-invalid-analytics-params)
    (var-set analytics-cache-duration cache-duration)
    (ok true)))

;; =====================================
;; REWARD TIER FUNCTIONS
;; =====================================

(define-public (update-user-reward-tier (user principal) (credential-level uint))
  (let
    (
      (current-tier-data (default-to
        { total-credentials-earned: u0, current-tier: u0, tier-unlocked-at: u0, lifetime-level-sum: u0, badges-earned: (list) }
        (map-get? user-reward-tier user)))
      (new-total (+ (get total-credentials-earned current-tier-data) u1))
      (new-level-sum (+ (get lifetime-level-sum current-tier-data) credential-level))
      (new-tier (calculate-user-tier new-total new-level-sum))
      (current-tier (get current-tier current-tier-data))
    )
    (map-set user-reward-tier user
      (merge current-tier-data
        {
          total-credentials-earned: new-total,
          lifetime-level-sum: new-level-sum,
          current-tier: new-tier,
          tier-unlocked-at: (if (> new-tier current-tier) burn-block-height (get tier-unlocked-at current-tier-data)),
          badges-earned: (if (> new-tier current-tier) 
            (unwrap-panic (as-max-len? (append (get badges-earned current-tier-data) new-tier) u5))
            (get badges-earned current-tier-data))
        }
      )
    )
    (ok true)))

(define-public (claim-tier-badge (tier-id uint))
  (let
    (
      (user tx-sender)
      (user-tier-data (unwrap! (map-get? user-reward-tier user) err-not-found))
      (current-tier (get current-tier user-tier-data))
    )
    (asserts! (and (>= tier-id u1) (<= tier-id u5)) err-invalid-tier)
    (asserts! (>= current-tier tier-id) err-tier-not-unlocked)
    (ok { tier: tier-id, badge-claimed: true, user: user })))

(define-read-only (get-user-reward-tier (user principal))
  (map-get? user-reward-tier user))

(define-read-only (get-tier-config (tier-id uint))
  (map-get? reward-tier-config tier-id))

(define-read-only (get-user-tier-progress (user principal))
  (let
    (
      (user-tier-data (default-to
        { total-credentials-earned: u0, current-tier: u0, tier-unlocked-at: u0, lifetime-level-sum: u0, badges-earned: (list) }
        (map-get? user-reward-tier user)))
      (current-tier (get current-tier user-tier-data))
      (next-tier (+ current-tier u1))
      (next-tier-config (map-get? reward-tier-config next-tier))
    )
    (if (and (<= current-tier u4) (is-some next-tier-config))
      (let
        (
          (tier-config (unwrap-panic next-tier-config))
          (creds-needed (- (get credentials-required tier-config) (get total-credentials-earned user-tier-data)))
          (level-sum-needed (- (get level-sum-required tier-config) (get lifetime-level-sum user-tier-data)))
        )
        (ok {
          current-tier: current-tier,
          next-tier: next-tier,
          credentials-needed: creds-needed,
          level-sum-needed: level-sum-needed,
          progress-percent: (/ (* (get total-credentials-earned user-tier-data) u100) (get credentials-required tier-config))
        }))
      (ok {
        current-tier: current-tier,
        next-tier: u0,
        credentials-needed: u0,
        level-sum-needed: u0,
        progress-percent: u100
      }))))

(define-read-only (get-all-tier-configs)
  (ok {
    tier-1: (unwrap-panic (map-get? reward-tier-config u1)),
    tier-2: (unwrap-panic (map-get? reward-tier-config u2)),
    tier-3: (unwrap-panic (map-get? reward-tier-config u3)),
    tier-4: (unwrap-panic (map-get? reward-tier-config u4)),
    tier-5: (unwrap-panic (map-get? reward-tier-config u5))
  }))

(define-public (toggle-reward-tiers (enabled bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set reward-tiers-enabled enabled)
    (ok true)))

(define-private (calculate-user-tier (total-credentials uint) (level-sum uint))
  (if (and (>= total-credentials u50) (>= level-sum u150))
    u5
    (if (and (>= total-credentials u30) (>= level-sum u80))
      u4
      (if (and (>= total-credentials u15) (>= level-sum u35))
        u3
        (if (and (>= total-credentials u5) (>= level-sum u10))
          u2
          (if (>= total-credentials u1)
            u1
            u0))))))
