// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/// @title Contractooor
/// @author @colinnielsen
/// @notice Arbitrates agremements between Service Providers and Service Receivers
contract Contractooor {
    error NOT_SENDER_OR_RECEIVER();

    event AgreementProposed(
        uint256 agreementId,
        address provider,
        address receiver,
        string scopeOfWorkURI,
        uint32 agreementEndTimestamp,
        address streamToken,
        uint256 totalStreamedTokens,
        TerminationClauses terminationClauses
    );

    struct TerminationClauses {
        uint16 atWillDays; // 0- many days
        uint16 cureTimeDays; // 0- many days
        // rage terminate clauses
        bool legalCompulsion;
        bool counterpartyMalfeasance;
        bool bankruptcyDissolutionInsolvency;
        bool counterpartyLostControlOfPrivateKeys;
    }

    mapping(bytes32 => mapping(address => bool)) agreements;

    function proposeAgreement(
        uint256 agreementId,
        address provider,
        address receiver,
        string calldata scopeOfWorkURI,
        uint32 agreementEndTimestamp,
        address streamToken,
        uint256 totalStreamedTokens,
        TerminationClauses calldata terminationClauses
    ) external {
        if (msg.sender != provider || msg.sender != receiver)
            revert NOT_SENDER_OR_RECEIVER();

        bool senderIsProvider = msg.sender == provider;

        bytes32 agreementVersionHash = keccak256(
            abi.encode(
                agreementId,
                provider,
                receiver,
                scopeOfWorkURI,
                agreementEndTimestamp,
                streamToken,
                totalStreamedTokens,
                terminationClauses
            )
        );

        bool isSignedByCounterParty = agreements[agreementVersionHash][
            senderIsProvider ? receiver : provider
        ];

        if (isSignedByCounterParty)
            _initiateAgreement(
                agreementId,
                provider,
                receiver,
                scopeOfWorkURI,
                agreementEndTimestamp,
                streamToken,
                totalStreamedTokens,
                terminationClauses
            );
        else {
            agreements[agreementVersionHash][msg.sender] = true;

            emit AgreementProposed(
                agreementId,
                provider,
                receiver,
                scopeOfWorkURI,
                agreementEndTimestamp,
                streamToken,
                totalStreamedTokens,
                terminationClauses
            );
        }
    }

    function _initiateAgreement(
        uint256 agreementId,
        address provider,
        address receiver,
        string calldata scopeOfWorkURI,
        uint32 agreementEndTimestamp,
        address streamToken,
        uint256 totalStreamedTokens,
        TerminationClauses calldata terminationClauses
    ) internal {}
}

/**
    - DAO: legal entity name, type, and jurisdiction
    - SP: legal entity name, type, jurisdiction
    - SP's counterparty for agreement address
    - agreement scope of work
    - term length
    - stream token
    - total tokens streamed over term
    - [x] at will (n amount of days) (optional)
    - [x] mutual consent (always enabled)
    - [x] material breach (always enabled) (n amount of days to cure breach)
    - rage terminate (optional, select from choices below)
        * legal compulsion
        * counterparty malfeasance (indictment, fraud, sanctions, crimes of moral turpitude)
        * bankruptcy, dissolution, insolvency, loss of necessary license/certification
        * counterparty lost exclusive control over private keys
 */
