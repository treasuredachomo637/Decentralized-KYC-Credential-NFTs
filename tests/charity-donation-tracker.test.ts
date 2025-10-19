import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;
const deployer = accounts.get("deployer")!;

describe("Charity Donation Tracker with Analytics", () => {
  it("ensures contract deployment was successful", () => {
    const deploymentResponse = simnet.getContractAST("charity-donation-tracker");
    expect(deploymentResponse).toBeTruthy();
  });

  it("allows owner to add approved verifiers", () => {
    const { result } = simnet.callPublicFn(
      "charity-donation-tracker", 
      "add-approved-verifier", 
      [Cl.principal(address1)], 
      deployer
    );
    expect(result).toBeOk();
  });

  it("allows approved verifier to mint credentials", () => {
    // First add verifier
    simnet.callPublicFn(
      "charity-donation-tracker", 
      "add-approved-verifier", 
      [Cl.principal(address1)], 
      deployer
    );

    // Then mint credential
    const { result } = simnet.callPublicFn(
      "charity-donation-tracker", 
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
      "charity-donation-tracker", 
      "add-approved-verifier", 
      [Cl.principal(address1)], 
      deployer
    );

    simnet.callPublicFn(
      "charity-donation-tracker", 
      "mint-credential", 
      [Cl.principal(address2), Cl.uint(3), Cl.uint(2000)], 
      address1
    );

    // Check system overview includes analytics
    const { result: overview } = simnet.callReadOnlyFn(
      "charity-donation-tracker",
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

  it("provides analytics health check information", () => {
    const { result: health } = simnet.callReadOnlyFn(
      "charity-donation-tracker",
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

  it("prevents unauthorized operations", () => {
    // Try to add verifier as non-owner
    const { result: unauthorized } = simnet.callPublicFn(
      "charity-donation-tracker", 
      "add-approved-verifier", 
      [Cl.principal(address2)], 
      address1  // Not the owner
    );
    expect(unauthorized).toBeErr(Cl.uint(100)); // err-owner-only

    // Try to mint without being approved verifier
    const { result: notApproved } = simnet.callPublicFn(
      "charity-donation-tracker", 
      "mint-credential", 
      [Cl.principal(address2), Cl.uint(2), Cl.uint(1000)], 
      address1  // Not approved verifier
    );
    expect(notApproved).toBeErr(Cl.uint(101)); // err-not-authorized
  });
});
