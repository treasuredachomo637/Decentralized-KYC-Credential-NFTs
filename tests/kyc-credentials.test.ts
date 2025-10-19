import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;
const deployer = accounts.get("deployer")!;

/*
  The test below is an example. To learn more, read the testing documentation here:
  https://docs.hiro.so/clarinet/feature-guides/test-contract-with-clarinet-sdk
*/

describe("KYC Credentials with Analytics", () => {
  it("ensures contract deployment was successful", () => {
    const deploymentResponse = simnet.getContractAST("kyc-credentials");
    expect(deploymentResponse).toBeTruthy();
  });

  it("allows owner to add approved verifiers", () => {
    const { result } = simnet.callPublicFn(
      "kyc-credentials", 
      "add-approved-verifier", 
      [Cl.principal(address1)], 
      deployer
    );
    expect(result).toBeOk();
  });

  it("allows approved verifier to mint credentials", () => {
    // First add verifier
    simnet.callPublicFn(
      "kyc-credentials", 
      "add-approved-verifier", 
      [Cl.principal(address1)], 
      deployer
    );

    // Then mint credential
    const { result } = simnet.callPublicFn(
      "kyc-credentials", 
      "mint-credential", 
      [Cl.principal(address2), Cl.uint(2), Cl.uint(1000)], 
      address1
    );
    expect(result).toBeOk();
    expect(result).toBeUint(1);
  });

  it("updates analytics when minting credentials", () => {
    // Add verifier and mint credential
    simnet.callPublicFn(
      "kyc-credentials", 
      "add-approved-verifier", 
      [Cl.principal(address1)], 
      deployer
    );

    simnet.callPublicFn(
      "kyc-credentials", 
      "mint-credential", 
      [Cl.principal(address2), Cl.uint(3), Cl.uint(2000)], 
      address1
    );

    // Check system overview includes analytics
    const { result: overview } = simnet.callReadOnlyFn(
      "kyc-credentials",
      "get-system-overview",
      [],
      deployer
    );
    
    expect(overview).toBeTuple({
      "total-credentials": Cl.uint(1),
      "active-verifiers": Cl.uint(3),
      "avg-credential-level": Cl.uint(2),
      "system-health-score": Cl.uint(40),
      "analytics-enabled": Cl.bool(true)
    });
  });

  it("tracks verifier performance analytics", () => {
    // Setup verifier and mint multiple credentials
    simnet.callPublicFn(
      "kyc-credentials", 
      "add-approved-verifier", 
      [Cl.principal(address1)], 
      deployer
    );

    simnet.callPublicFn(
      "kyc-credentials", 
      "mint-credential", 
      [Cl.principal(address2), Cl.uint(4), Cl.uint(3000)], 
      address1
    );

    // Check verifier performance summary
    const { result: performance } = simnet.callReadOnlyFn(
      "kyc-credentials",
      "get-verifier-performance-summary",
      [Cl.principal(address1)],
      deployer
    );

    expect(performance).toBeTuple({
      "credentials-issued": Cl.uint(1),
      "average-rating": Cl.uint(0),
      "efficiency-score": Cl.uint(10),
      "consistency-rating": Cl.uint(50),
      "specialization-level": Cl.uint(1),
      "last-activity": Cl.uint(simnet.burnBlockHeight)
    });
  });

  it("provides credential trends analytics", () => {
    // Setup and create some activity
    simnet.callPublicFn(
      "kyc-credentials", 
      "add-approved-verifier", 
      [Cl.principal(address1)], 
      deployer
    );

    simnet.callPublicFn(
      "kyc-credentials", 
      "mint-credential", 
      [Cl.principal(address2), Cl.uint(2), Cl.uint(1500)], 
      address1
    );

    // Check trends for last 100 blocks
    const { result: trends } = simnet.callReadOnlyFn(
      "kyc-credentials",
      "get-credential-trends",
      [Cl.uint(100)],
      deployer
    );

    expect(trends).toBeOk();
  });

  it("allows admin to toggle analytics", () => {
    const { result } = simnet.callPublicFn(
      "kyc-credentials", 
      "toggle-analytics", 
      [Cl.bool(false)], 
      deployer
    );
    expect(result).toBeOk();

    // Verify analytics is disabled in system overview
    const { result: overview } = simnet.callReadOnlyFn(
      "kyc-credentials",
      "get-system-overview",
      [],
      deployer
    );
    
    const overviewData = overview as any;
    expect(overviewData.data["analytics-enabled"]).toBeBool(false);
  });

  it("provides analytics health check information", () => {
    const { result: health } = simnet.callReadOnlyFn(
      "kyc-credentials",
      "get-analytics-health-check",
      [],
      deployer
    );

    expect(health).toBeTuple({
      "cache-hit-rate": Cl.uint(92),
      "data-freshness": Cl.uint(simnet.burnBlockHeight - 5),
      "calculation-accuracy": Cl.uint(98),
      "system-load": Cl.uint(35),
      "analytics-enabled": Cl.bool(true),
      "recommendations": Cl.stringAscii("System operating optimally")
    });
  });

  it("tracks credential level analytics", () => {
    // Setup verifier
    simnet.callPublicFn(
      "kyc-credentials", 
      "add-approved-verifier", 
      [Cl.principal(address1)], 
      deployer
    );

    // Mint credential with level 3
    simnet.callPublicFn(
      "kyc-credentials", 
      "mint-credential", 
      [Cl.principal(address2), Cl.uint(3), Cl.uint(2500)], 
      address1
    );

    // Check level 3 analytics
    const { result: levelAnalytics } = simnet.callReadOnlyFn(
      "kyc-credentials",
      "get-credential-level-analytics",
      [Cl.uint(3)],
      deployer
    );

    expect(levelAnalytics).toBeSome();
  });

  it("allows credential revocation with analytics tracking", () => {
    // Setup and mint credential
    simnet.callPublicFn(
      "kyc-credentials", 
      "add-approved-verifier", 
      [Cl.principal(address1)], 
      deployer
    );

    const { result: tokenId } = simnet.callPublicFn(
      "kyc-credentials", 
      "mint-credential", 
      [Cl.principal(address2), Cl.uint(2), Cl.uint(1800)], 
      address1
    );

    // Revoke the credential
    const { result: revoked } = simnet.callPublicFn(
      "kyc-credentials", 
      "revoke-credential", 
      [Cl.uint(1)], 
      address1
    );

    expect(revoked).toBeOk();

    // Check credential status
    const { result: credData } = simnet.callReadOnlyFn(
      "kyc-credentials",
      "get-credential-data",
      [Cl.uint(1)],
      deployer
    );

    const credentialData = credData as any;
    expect(credentialData.data.status).toBeStringAscii("revoked");
  });

  it("provides user interaction analytics", () => {
    // Setup verifier and mint credential
    simnet.callPublicFn(
      "kyc-credentials", 
      "add-approved-verifier", 
      [Cl.principal(address1)], 
      deployer
    );

    simnet.callPublicFn(
      "kyc-credentials", 
      "mint-credential", 
      [Cl.principal(address2), Cl.uint(4), Cl.uint(3500)], 
      address1
    );

    // Check user analytics
    const { result: userAnalytics } = simnet.callReadOnlyFn(
      "kyc-credentials",
      "get-user-analytics",
      [Cl.principal(address2)],
      deployer
    );

    expect(userAnalytics).toBeSome();
  });

  it("prevents unauthorized operations", () => {
    // Try to add verifier as non-owner
    const { result: unauthorized } = simnet.callPublicFn(
      "kyc-credentials", 
      "add-approved-verifier", 
      [Cl.principal(address2)], 
      address1  // Not the owner
    );
    expect(unauthorized).toBeErr(Cl.uint(100)); // err-owner-only

    // Try to mint without being approved verifier
    const { result: notApproved } = simnet.callPublicFn(
      "kyc-credentials", 
      "mint-credential", 
      [Cl.principal(address2), Cl.uint(2), Cl.uint(1000)], 
      address1  // Not approved verifier
    );
    expect(notApproved).toBeErr(Cl.uint(101)); // err-not-authorized
  });
});
