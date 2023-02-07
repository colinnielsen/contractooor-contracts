// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

struct Agreement {
    address provider;
    address receiver;
    uint16 atWillDays; // 0- many days
    uint16 cureTimeDays; // 0- many days
    // rage terminate clauses
    bool legalCompulsion;
    bool counterpartyMalfeasance;
    bool bankruptcyDissolutionInsolvency;
    bool counterpartyLostControlOfPrivateKeys;
    string scopeOfWorkURI;
}

struct TerminationClauses {
    uint16 atWillDays; // 0- many days
    uint16 cureTimeDays; // 0- many days
    // rage terminate clauses
    bool legalCompulsion;
    bool counterpartyMalfeasance;
    bool bankruptcyDissolutionInsolvency;
    bool counterpartyLostControlOfPrivateKeys;
}
