;; Carbon Credits Contract
;; Manages the creation, issuance, and lifecycle of carbon credits

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-CREDIT (err u101))
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))
(define-constant ERR-CREDIT-EXPIRED (err u103))
(define-constant ERR-CREDIT-RETIRED (err u104))
(define-constant ERR-INVALID-AMOUNT (err u105))

;; Data Variables
(define-data-var next-credit-id uint u1)
(define-data-var total-credits-issued uint u0)
(define-data-var total-credits-retired uint u0)

;; Data Maps
(define-map credits
  uint
  {
    project-id: uint,
    owner: principal,
    amount: uint,
    issue-date: uint,
    expiry-date: uint,
    methodology: (string-ascii 50),
    verification-body: (string-ascii 50),
    status: (string-ascii 20),
    vintage-year: uint
  }
)

(define-map credit-balances
  { owner: principal, credit-id: uint }
  uint
)

(define-map project-credits
  uint
  (list 1000 uint)
)

;; Read-only functions
(define-read-only (get-credit (credit-id uint))
  (map-get? credits credit-id)
)

(define-read-only (get-credit-balance (owner principal) (credit-id uint))
  (default-to u0 (map-get? credit-balances { owner: owner, credit-id: credit-id }))
)

(define-read-only (get-total-credits-issued)
  (var-get total-credits-issued)
)

(define-read-only (get-total-credits-retired)
  (var-get total-credits-retired)
)

(define-read-only (get-next-credit-id)
  (var-get next-credit-id)
)

(define-read-only (get-project-credits (project-id uint))
  (default-to (list) (map-get? project-credits project-id))
)

;; Private functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

(define-private (is-credit-valid (credit-id uint))
  (match (map-get? credits credit-id)
    credit (and
      (< block-height (get expiry-date credit))
      (is-eq (get status credit) "active")
    )
    false
  )
)

;; Public functions
(define-public (issue-credits
  (project-id uint)
  (amount uint)
  (recipient principal)
  (expiry-date uint)
  (methodology (string-ascii 50))
  (verification-body (string-ascii 50))
  (vintage-year uint)
)
  (let (
    (credit-id (var-get next-credit-id))
  )
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (> expiry-date block-height) ERR-INVALID-AMOUNT)

    ;; Create the credit
    (map-set credits credit-id {
      project-id: project-id,
      owner: recipient,
      amount: amount,
      issue-date: block-height,
      expiry-date: expiry-date,
      methodology: methodology,
      verification-body: verification-body,
      status: "active",
      vintage-year: vintage-year
    })

    ;; Set initial balance
    (map-set credit-balances
      { owner: recipient, credit-id: credit-id }
      amount
    )

    ;; Update project credits list
    (match (map-get? project-credits project-id)
      existing-credits
        (map-set project-credits project-id
          (unwrap! (as-max-len? (append existing-credits credit-id) u1000) ERR-INVALID-AMOUNT))
      (map-set project-credits project-id (list credit-id))
    )

    ;; Update counters
    (var-set next-credit-id (+ credit-id u1))
    (var-set total-credits-issued (+ (var-get total-credits-issued) amount))

    (ok credit-id)
  )
)

(define-public (transfer-credits
  (credit-id uint)
  (amount uint)
  (recipient principal)
)
  (let (
    (sender-balance (get-credit-balance tx-sender credit-id))
    (recipient-balance (get-credit-balance recipient credit-id))
  )
    (asserts! (is-credit-valid credit-id) ERR-INVALID-CREDIT)
    (asserts! (>= sender-balance amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)

    ;; Update balances
    (map-set credit-balances
      { owner: tx-sender, credit-id: credit-id }
      (- sender-balance amount)
    )

    (map-set credit-balances
      { owner: recipient, credit-id: credit-id }
      (+ recipient-balance amount)
    )

    ;; Update credit owner if full transfer
    (if (is-eq sender-balance amount)
      (map-set credits credit-id
        (merge (unwrap! (map-get? credits credit-id) ERR-INVALID-CREDIT)
               { owner: recipient }))
      true
    )

    (ok true)
  )
)

(define-public (retire-credits (credit-id uint) (amount uint))
  (let (
    (user-balance (get-credit-balance tx-sender credit-id))
  )
    (asserts! (is-credit-valid credit-id) ERR-INVALID-CREDIT)
    (asserts! (>= user-balance amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)

    ;; Reduce user balance
    (map-set credit-balances
      { owner: tx-sender, credit-id: credit-id }
      (- user-balance amount)
    )

    ;; Update retired credits counter
    (var-set total-credits-retired (+ (var-get total-credits-retired) amount))

    (ok true)
  )
)

(define-public (expire-credit (credit-id uint))
  (let (
    (credit (unwrap! (map-get? credits credit-id) ERR-INVALID-CREDIT))
  )
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (>= block-height (get expiry-date credit)) ERR-INVALID-CREDIT)

    (map-set credits credit-id
      (merge credit { status: "expired" })
    )

    (ok true)
  )
)
