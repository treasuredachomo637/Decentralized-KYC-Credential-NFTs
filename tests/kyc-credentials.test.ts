import { describe, expect, it, beforeEach } from "vitest";
import { Cl, ClarityType } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployerAccount = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;
const wallet3 = accounts.get("wallet_3")!;

/*
  The test below is an example. Learn more in the clarinet-sdk readme:
  https://github.com/hirosystems/clarinet/blob/develop/components/clarinet-sdk/README.md
*/

describe("KYC Credentials with Reputation System", () => {
  beforeEach(() => {
    // Setup approved verifiers
    simnet.callPublicFn("kyc-credentials", "add-approved-verifier", [
      Cl.principal(wallet1),
    ], deployerAccount);
    
    simnet.callPublicFn("kyc-credentials", "add-approved-verifier", [
      Cl.principal(wallet2),
    ], deployerAccount);
  });

  describe("Core KYC Functionality", () => {
    it("should mint a KYC credential successfully", () => {
      const { result } = simnet.callPublicFn(
        "kyc-credentials",
        "mint-credential",
        [
          Cl.principal(wallet3),
          Cl.uint(3), // Level 3 verification
          Cl.uint(1000), // Expires at block 1000
        ],
        wallet1 // Approved verifier
      );

      expect(result).toBeOk(Cl.uint(1));
    });

    it("should prevent unauthorized minting", () => {
      const { result } = simnet.callPublicFn(
        "kyc-credentials",
        "mint-credential",
        [
          Cl.principal(wallet3),
          Cl.uint(3),
          Cl.uint(1000),
        ],
        wallet3 // Not an approved verifier
      );

      expect(result).toBeErr(Cl.uint(101)); // err-not-authorized
    });

    it("should record verifier interaction when minting", () => {
      // Mint credential
      simnet.callPublicFn(
        "kyc-credentials",
        "mint-credential",
        [Cl.principal(wallet3), Cl.uint(2), Cl.uint(500)],
        wallet1
      );

      // Check interaction was recorded
      const { result: interaction } = simnet.callReadOnlyFn(
        "kyc-credentials",
        "get-user-interaction",
        [Cl.principal(wallet3), Cl.principal(wallet1)],
        deployerAccount
      );

      expect(interaction).toBeSome();
      const interactionData = interaction.value;
      expect(interactionData).toStrictEqual(
        Cl.tuple({
          "has-credential": Cl.bool(true),
          "last-interaction": Cl.uint(simnet.blockHeight),
          "interaction-count": Cl.uint(1),
        })
      );
    });
  });

  describe("Reputation System", () => {
    beforeEach(() => {
      // Mint a credential to establish interaction
      simnet.callPublicFn(
        "kyc-credentials",
        "mint-credential",
        [Cl.principal(wallet3), Cl.uint(3), Cl.uint(1000)],
        wallet1
      );
    });

    it("should allow rating a verifier after interaction", () => {
      const { result } = simnet.callPublicFn(
        "kyc-credentials",
        "rate-verifier",
        [
          Cl.principal(wallet1), // Verifier to rate
          Cl.uint(5), // 5-star rating
          Cl.stringAscii("Excellent service, quick verification!"),
          Cl.some(Cl.uint(1)), // Credential ID
        ],
        wallet3 // User who received credential
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should prevent self-rating", () => {
      const { result } = simnet.callPublicFn(
        "kyc-credentials",
        "rate-verifier",
        [
          Cl.principal(wallet1),
          Cl.uint(4),
          Cl.stringAscii("I'm great!"),
          Cl.none(),
        ],
        wallet1 // Same as verifier
      );

      expect(result).toBeErr(Cl.uint(112)); // err-self-rating
    });

    it("should prevent rating without interaction", () => {
      const { result } = simnet.callPublicFn(
        "kyc-credentials",
        "rate-verifier",
        [
          Cl.principal(wallet2), // Different verifier, no interaction
          Cl.uint(4),
          Cl.stringAscii("No interaction"),
          Cl.none(),
        ],
        wallet3
      );

      expect(result).toBeErr(Cl.uint(113)); // err-no-interaction
    });

    it("should prevent invalid ratings", () => {
      const { result } = simnet.callPublicFn(
        "kyc-credentials",
        "rate-verifier",
        [
          Cl.principal(wallet1),
          Cl.uint(6), // Invalid rating > 5
          Cl.stringAscii("Invalid rating"),
          Cl.none(),
        ],
        wallet3
      );

      expect(result).toBeErr(Cl.uint(111)); // err-invalid-rating
    });

    it("should update verifier reputation stats after rating", () => {
      // Rate the verifier
      simnet.callPublicFn(
        "kyc-credentials",
        "rate-verifier",
        [
          Cl.principal(wallet1),
          Cl.uint(5),
          Cl.stringAscii("Perfect!"),
          Cl.some(Cl.uint(1)),
        ],
        wallet3
      );

      // Check reputation stats
      const { result: reputation } = simnet.callReadOnlyFn(
        "kyc-credentials",
        "get-verifier-reputation",
        [Cl.principal(wallet1)],
        deployerAccount
      );

      expect(reputation).toBeSome();
      const reputationData = reputation.value;
      expect(reputationData).toContainEntries([
        ["total-ratings", Cl.uint(1)],
        ["credentials-issued", Cl.uint(1)],
      ]);
    });

    it("should provide rating summary", () => {
      // Rate the verifier
      simnet.callPublicFn(
        "kyc-credentials",
        "rate-verifier",
        [
          Cl.principal(wallet1),
          Cl.uint(4),
          Cl.stringAscii("Very good"),
          Cl.none(),
        ],
        wallet3
      );

      // Get rating summary
      const { result: summary } = simnet.callReadOnlyFn(
        "kyc-credentials",
        "get-verifier-rating-summary",
        [Cl.principal(wallet1)],
        deployerAccount
      );

      expect(summary).toStrictEqual(
        Cl.tuple({
          "average-rating": Cl.uint(80), // 4 * 20
          "total-ratings": Cl.uint(1),
          "credentials-issued": Cl.uint(1),
          "rating-out-of-5": Cl.uint(4), // 80 / 20
        })
      );
    });

    it("should check if user can rate verifier", () => {
      // User with credential should be able to rate
      const { result: canRate } = simnet.callReadOnlyFn(
        "kyc-credentials",
        "can-rate-verifier",
        [Cl.principal(wallet3), Cl.principal(wallet1)],
        deployerAccount
      );

      expect(canRate).toBe(Cl.bool(true));

      // User without credential should not be able to rate
      const { result: cannotRate } = simnet.callReadOnlyFn(
        "kyc-credentials",
        "can-rate-verifier",
        [Cl.principal(wallet2), Cl.principal(wallet1)],
        deployerAccount
      );

      expect(cannotRate).toBe(Cl.bool(false));
    });

    it("should prevent duplicate ratings", () => {
      // First rating
      simnet.callPublicFn(
        "kyc-credentials",
        "rate-verifier",
        [
          Cl.principal(wallet1),
          Cl.uint(5),
          Cl.stringAscii("First rating"),
          Cl.none(),
        ],
        wallet3
      );

      // Second rating should fail
      const { result } = simnet.callPublicFn(
        "kyc-credentials",
        "rate-verifier",
        [
          Cl.principal(wallet1),
          Cl.uint(3),
          Cl.stringAscii("Second rating attempt"),
          Cl.none(),
        ],
        wallet3
      );

      expect(result).toBeErr(Cl.uint(114)); // err-already-rated
    });

    it("should allow updating existing ratings", () => {
      // First rating
      simnet.callPublicFn(
        "kyc-credentials",
        "rate-verifier",
        [
          Cl.principal(wallet1),
          Cl.uint(3),
          Cl.stringAscii("Initial rating"),
          Cl.none(),
        ],
        wallet3
      );

      // Update rating
      const { result } = simnet.callPublicFn(
        "kyc-credentials",
        "update-rating",
        [
          Cl.principal(wallet1),
          Cl.uint(5),
          Cl.stringAscii("Updated to 5 stars!"),
        ],
        wallet3
      );

      expect(result).toBeOk(Cl.bool(true));

      // Verify rating was updated
      const { result: rating } = simnet.callReadOnlyFn(
        "kyc-credentials",
        "get-verifier-rating",
        [Cl.principal(wallet1), Cl.principal(wallet3)],
        deployerAccount
      );

      expect(rating).toBeSome();
      const ratingData = rating.value;
      expect(ratingData).toContainEntry(
        "rating",
        Cl.uint(100) // 5 * 20
      );
      expect(ratingData).toContainEntry(
        "comment",
        Cl.stringAscii("Updated to 5 stars!")
      );
    });
  });

  describe("Badge System", () => {
    it("should award trusted verifier badge with sufficient ratings", () => {
      // Set low threshold for testing
      simnet.callPublicFn(
        "kyc-credentials",
        "set-reputation-thresholds",
        [Cl.uint(1), Cl.uint(80), Cl.uint(10)],
        deployerAccount
      );

      // Mint credential and rate
      simnet.callPublicFn(
        "kyc-credentials",
        "mint-credential",
        [Cl.principal(wallet3), Cl.uint(3), Cl.uint(1000)],
        wallet1
      );

      simnet.callPublicFn(
        "kyc-credentials",
        "rate-verifier",
        [
          Cl.principal(wallet1),
          Cl.uint(5),
          Cl.stringAscii("Excellent!"),
          Cl.none(),
        ],
        wallet3
      );

      // Check badges
      const { result: badges } = simnet.callReadOnlyFn(
        "kyc-credentials",
        "get-verifier-badges",
        [Cl.principal(wallet1)],
        deployerAccount
      );

      expect(badges).toBeSome();
      const badgeData = badges.value;
      expect(badgeData).toContainEntry("trusted-verifier", Cl.bool(true));
    });

    it("should identify trusted verifiers correctly", () => {
      // Setup verifier with good reputation
      simnet.callPublicFn(
        "kyc-credentials",
        "set-reputation-thresholds",
        [Cl.uint(1), Cl.uint(60), Cl.uint(10)],
        deployerAccount
      );

      simnet.callPublicFn(
        "kyc-credentials",
        "mint-credential",
        [Cl.principal(wallet3), Cl.uint(3), Cl.uint(1000)],
        wallet1
      );

      simnet.callPublicFn(
        "kyc-credentials",
        "rate-verifier",
        [
          Cl.principal(wallet1),
          Cl.uint(4), // 4 stars = 80 points
          Cl.stringAscii("Good verifier"),
          Cl.none(),
        ],
        wallet3
      );

      const { result: isTrusted } = simnet.callReadOnlyFn(
        "kyc-credentials",
        "is-trusted-verifier",
        [Cl.principal(wallet1)],
        deployerAccount
      );

      expect(isTrusted).toBe(Cl.bool(true));
    });
  });

  describe("Administrative Functions", () => {
    it("should allow owner to set reputation thresholds", () => {
      const { result } = simnet.callPublicFn(
        "kyc-credentials",
        "set-reputation-thresholds",
        [Cl.uint(5), Cl.uint(85), Cl.uint(50)],
        deployerAccount
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should prevent non-owner from setting thresholds", () => {
      const { result } = simnet.callPublicFn(
        "kyc-credentials",
        "set-reputation-thresholds",
        [Cl.uint(5), Cl.uint(85), Cl.uint(50)],
        wallet1 // Not the owner
      );

      expect(result).toBeErr(Cl.uint(100)); // err-owner-only
    });

    it("should allow owner to reset verifier reputation", () => {
      // First establish reputation
      simnet.callPublicFn(
        "kyc-credentials",
        "mint-credential",
        [Cl.principal(wallet3), Cl.uint(3), Cl.uint(1000)],
        wallet1
      );

      simnet.callPublicFn(
        "kyc-credentials",
        "rate-verifier",
        [Cl.principal(wallet1), Cl.uint(5), Cl.stringAscii("Great!"), Cl.none()],
        wallet3
      );

      // Reset reputation
      const { result } = simnet.callPublicFn(
        "kyc-credentials",
        "reset-verifier-reputation",
        [Cl.principal(wallet1)],
        deployerAccount
      );

      expect(result).toBeOk(Cl.bool(true));

      // Verify reputation was reset
      const { result: reputation } = simnet.callReadOnlyFn(
        "kyc-credentials",
        "get-verifier-reputation",
        [Cl.principal(wallet1)],
        deployerAccount
      );

      expect(reputation).toBeNone();
    });
  });

  describe("Edge Cases and Security", () => {
    it("should handle multiple ratings correctly", () => {
      // Setup multiple users with credentials
      simnet.callPublicFn(
        "kyc-credentials",
        "mint-credential",
        [Cl.principal(wallet2), Cl.uint(2), Cl.uint(800)],
        wallet1
      );

      simnet.callPublicFn(
        "kyc-credentials",
        "mint-credential",
        [Cl.principal(wallet3), Cl.uint(3), Cl.uint(900)],
        wallet1
      );

      // Both users rate the verifier
      simnet.callPublicFn(
        "kyc-credentials",
        "rate-verifier",
        [Cl.principal(wallet1), Cl.uint(4), Cl.stringAscii("Good"), Cl.none()],
        wallet2
      );

      simnet.callPublicFn(
        "kyc-credentials",
        "rate-verifier",
        [Cl.principal(wallet1), Cl.uint(5), Cl.stringAscii("Excellent"), Cl.none()],
        wallet3
      );

      // Check aggregated reputation
      const { result: summary } = simnet.callReadOnlyFn(
        "kyc-credentials",
        "get-verifier-rating-summary",
        [Cl.principal(wallet1)],
        deployerAccount
      );

      const summaryData = summary;
      expect(summaryData).toContainEntry("total-ratings", Cl.uint(2));
      expect(summaryData).toContainEntry("credentials-issued", Cl.uint(2));
    });

    it("should validate rating bounds", () => {
      simnet.callPublicFn(
        "kyc-credentials",
        "mint-credential",
        [Cl.principal(wallet3), Cl.uint(3), Cl.uint(1000)],
        wallet1
      );

      // Test upper bound
      const { result: upperBound } = simnet.callPublicFn(
        "kyc-credentials",
        "rate-verifier",
        [Cl.principal(wallet1), Cl.uint(6), Cl.stringAscii("Invalid"), Cl.none()],
        wallet3
      );

      expect(upperBound).toBeErr(Cl.uint(111));

      // Test lower bound
      const { result: lowerBound } = simnet.callPublicFn(
        "kyc-credentials",
        "rate-verifier",
        [Cl.principal(wallet1), Cl.uint(0), Cl.stringAscii("Invalid"), Cl.none()],
        wallet3
      );

      expect(lowerBound).toBeErr(Cl.uint(111));
    });
  });
});
