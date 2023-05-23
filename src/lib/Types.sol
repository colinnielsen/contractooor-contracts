// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

enum TerminationReason
// Default Reasons
{
    MutualConsent,
    MaterialBreach,
    AtWill,
    // Rage Termination Options
    LegalCompulsion,
    CrimesOfMoralTurpitude,
    Bankruptcy,
    Dissolution,
    Insolvency,
    CounterPartyMalfeasance,
    LossControlOfPrivateKeys
}

struct Agreement {
    address provider;
    address client;
    uint16 atWillDays; // 0- many days
    uint16 cureTimeDays; // 0- many days
    // rage terminate clauses
    bool legalCompulsion;
    bool moralTurpitude;
    bool bankruptcyDissolutionInsolvency;
    bool counterpartyMalfeasance;
    bool lostControlOfPrivateKeys;
    string contractURI;
}

struct TerminationClauses {
    uint16 atWillDays; // 0- many days
    uint16 cureTimeDays; // 0- many days
    // rage terminate clauses
    bool legalCompulsion;
    bool moralTurpitude;
    bool bankruptcyDissolutionInsolvency;
    bool counterpartyMalfeasance;
    bool lostControlOfPrivateKeys;
}
