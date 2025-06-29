# 🆔 Decentralized KYC Credential NFTs

A decentralized solution for managing KYC (Know Your Customer) credentials using NFTs on the Stacks blockchain.

## 🎯 Overview

This smart contract enables trusted verifiers to issue KYC credential NFTs to users, creating a portable and privacy-preserving way to prove identity verification across different platforms.

## ✨ Features

- 🔐 NFT-based KYC credentials
- 👥 Multi-verifier support
- ⏰ Expiration management
- 🔄 Credential revocation
- 📈 Upgradeable verification levels
- 🔍 Status verification

## 📋 Contract Functions

### Administrative Functions
- `set-verifier`: Set the primary verifier address
- `add-approved-verifier`: Add a new approved verifier
- `remove-approved-verifier`: Remove an approved verifier

### Credential Management
- `mint-credential`: Issue new KYC credential
- `revoke-credential`: Revoke an existing credential
- `update-expiry`: Update credential expiration
- `upgrade-level`: Upgrade verification level
- `transfer`: Transfer credential to new owner

### Read Functions
- `get-credential-data`: Get credential details
- `is-active`: Check if credential is valid
- `is-approved-verifier`: Verify if address is approved verifier
- `get-last-token-id`: Get latest token ID

## 🚀 Usage

1. Deploy the contract
2. Add approved verifiers
3. Verifiers can mint credentials for verified users
4. Users can present their NFT credentials across platforms
5. Verifiers can manage credential lifecycle (revocation, expiry, upgrades)

## 🔒 Security

- Only contract owner can add/remove verifiers
- Only approved verifiers can mint credentials
- Only the original verifier can modify their issued credentials
- Credentials automatically expire based on block height

## 📝 License

MIT
```
