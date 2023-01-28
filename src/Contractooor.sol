// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ISablier} from "@sablier/protocol/contracts/interfaces/ISablier.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {console2} from "forge-std/console2.sol";

// TODO: i need to use a factory pattern

/// @title Contractooor
/// @author @colinnielsen
/// @notice Arbitrates agremements between Service Providers and Service Receivers
contract Contractooor {
    using SafeTransferLib for ERC20;

    ISablier public sablier;

    error NOT_SENDER_OR_RECEIVER();
    error INCOMPATIBLE_TOKEN();
    error INVALID_END_TIME();

    event AgreementInitiated(
        bytes32 agreementUUID,
        uint256 agreementId,
        uint256 streamId,
        address provider,
        address receiver,
        string scopeOfWorkURI,
        uint32 agreementEndTimestamp,
        ERC20 streamToken,
        uint256 totalStreamedTokens,
        TerminationClauses terminationClauses
    );

    event AgreementProposed(
        uint256 agreementId,
        address provider,
        address receiver,
        string scopeOfWorkURI,
        uint32 targetEndTimestamp,
        ERC20 streamToken,
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

    struct Agreement {
        address provider;
        address receiver;
        string scopeOfWorkURI;
        TerminationClauses terminationClauses;
    }

    constructor(address _sablier) {
        sablier = ISablier(_sablier);
    }

    mapping(bytes32 => mapping(address => bool)) pendingAgreements;
    mapping(bytes32 => Agreement) liveAgreements;

    function proposeAgreement(
        uint256 agreementId,
        address provider,
        address receiver,
        string calldata scopeOfWorkURI,
        uint32 endTime,
        ERC20 streamToken,
        uint256 totalStreamedTokens,
        TerminationClauses calldata terminationClauses
    ) external {
        if (msg.sender != provider && msg.sender != receiver) {
            revert NOT_SENDER_OR_RECEIVER();
        }
        if(endTime < block.timestamp) revert INVALID_END_TIME();

        bool senderIsProvider = msg.sender == provider;

        bytes32 agreementVersionHash = keccak256(
            abi.encode(
                agreementId,
                provider,
                receiver,
                scopeOfWorkURI,
                endTime,
                streamToken,
                totalStreamedTokens,
                terminationClauses
            )
        );

        bool isSignedByCounterParty = pendingAgreements[agreementVersionHash][senderIsProvider ? receiver : provider];

        if (isSignedByCounterParty) {
            delete pendingAgreements[agreementVersionHash][
                senderIsProvider ? receiver : provider
            ];

            _initiateAgreement(
                agreementId,
                provider,
                receiver,
                scopeOfWorkURI,
                endTime,
                streamToken,
                totalStreamedTokens,
                terminationClauses
            );
        } else {
            pendingAgreements[agreementVersionHash][msg.sender] = true;

            if (streamToken.decimals() < 4) revert INCOMPATIBLE_TOKEN();

            emit AgreementProposed(
                agreementId,
                provider,
                receiver,
                scopeOfWorkURI,
                endTime,
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
        uint32 endTimestamp,
        ERC20 streamToken,
        uint256 totalStreamedTokens,
        TerminationClauses calldata terminationClauses
    ) internal {
        bytes32 agreementUUID = keccak256(abi.encode(agreementId, provider, receiver));
        
        uint256 remainingTokens = totalStreamedTokens % (endTimestamp - block.timestamp);
        console2.log("throw");

        liveAgreements[agreementUUID] = Agreement({
            provider: provider,
            receiver: receiver,
            scopeOfWorkURI: scopeOfWorkURI,
            terminationClauses: terminationClauses
        });

        streamToken.safeTransferFrom(receiver, address(this), totalStreamedTokens);
        streamToken.safeTransfer(provider, remainingTokens);
        streamToken.approve(address(sablier), totalStreamedTokens - remainingTokens);

        uint256 streamId = sablier.createStream({
            recipient: provider,
            deposit: totalStreamedTokens - remainingTokens,
            tokenAddress: address(streamToken),
            startTime: block.timestamp,
            stopTime: endTimestamp
        });

        emit AgreementInitiated(
            agreementUUID,
            agreementId,
            streamId,
            provider,
            receiver,
            scopeOfWorkURI,
            endTimestamp,
            streamToken,
            totalStreamedTokens,
            terminationClauses
            );
    }
}

/**
 * - DAO: legal entity name, type, and jurisdiction
 *     - SP: legal entity name, type, jurisdiction
 *     - SP's counterparty for agreement address
 *     - agreement scope of work
 *     - term length
 *     - stream token
 *     - total tokens streamed over term
 *     - [x] at will (n amount of days) (optional)
 *     - [x] mutual consent (always enabled)
 *     - [x] material breach (always enabled) (n amount of days to cure breach)
 *     - rage terminate (optional, select from choices below)
 * legal compulsion
 * counterparty malfeasance (indictment, fraud, sanctions, crimes of moral turpitude)
 * bankruptcy, dissolution, insolvency, loss of necessary license/certification
 * counterparty lost exclusive control over private keys
 */
