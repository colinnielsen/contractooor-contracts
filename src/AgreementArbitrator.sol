// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ISablier} from "@sablier/protocol/contracts/interfaces/ISablier.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {TerminationClauses, Agreement} from "contracts/lib/Types.sol";
import {ContractooorAgreement} from "contracts/ContractooorAgreement.sol";
import {Clones} from "@openzeppelin/proxy/Clones.sol";

import {console2} from "forge-std/console2.sol";

/// @title AgreementArbitrator
/// @author @colinnielsen
/// @notice A light-weight agremement arbitrator for contractors and clients to create streaming contracts in exchange for services
contract AgreementArbitrator {
    using SafeTransferLib for ERC20;
    using Clones for address;

    ISablier public sablier;
    ContractooorAgreement private agreementSingleton;
    mapping(bytes32 => mapping(address => bool)) isAgreementSigned;

    error NOT_RECEIVER();
    error NOT_SENDER_OR_RECEIVER();
    error INCOMPATIBLE_TOKEN();
    error INVALID_TERM_LENGTH();

    event AgreementProposed(
        bytes32 indexed agreementGUID,
        uint256 agreementId,
        address indexed provider,
        address indexed receiver,
        string scopeOfWorkURI,
        uint32 targetEndTimestamp,
        ERC20 streamToken,
        uint256 totalStreamedTokens,
        TerminationClauses terminationClauses
    );

    event AgreementInitiated(
        bytes32 agreementGUID,
        address contractooorAgreement
    );

    constructor(address _sablier, address _agreementSingleton) {
        sablier = ISablier(_sablier);
        agreementSingleton = ContractooorAgreement(_agreementSingleton);
    }

    /// @notice a single function for parties to offer, counter-offer, and agree to a contract
    /// @dev takes the hash of all the parameters to make a agreementGUID, which is counter-signed, then used as salt for the contract deployment
    /// @notice SPEC:
    /// A call to this function will prompt pull tokens from the service receiver, and create a stream of those tokens to the service provider given:
    ///     A1. Either the `provider` or `receiver` have called this function with the exact same arguments - otherwise :: marks the agreement as signed
    ///     A2. The `msg.sender` is the `provider` or `receiver` address
    ///     A3. The `termLength` is not 0
    ///     A4. The `streamToken` has > 4 decimals, making it sablier compatible
    ///     A5. If the agreement has already been counterparty signed, this contract must have `totalStreamedTokens` worth of operator approval from `receiver`
    ///
    /// RES-A. If `msg.sender` is the first signing party:
    ///     RES-A.1: Mark the user's signature of the `agreementGUID` as true
    ///         an agreement GUID is defined as: the keccak256 hash of all the abi.encoded calldata parameters
    ///     RES-A.2: emit an AgreementProposed event with the `aggreementGUID` and all the calldata parameters
    ///
    /// RES-B. If `msg.sender` is the second party to sign:
    ///     RES-B.1: delete the counterparty's leftover signature
    ///     RES-B.2: transfer `remainder` of tokens to the `provider` (this is to prevent rounding errors in the sablier stream)
    ///     RES-B.3: send `totalStreamedTokens` - `remainder` of tokens to the stream contract
    ///     RES-B.4: create a new Contractooor agreement proxy clone
    ///     RES-B.5: call `initialize` on the new proxy clone
    ///     RES-B.6: emit an `AgreementInitiated` event with the `agreementGUID` and the Contractooor addresss
    function agreeTo(
        uint256 agreementId,
        address provider,
        address receiver,
        string calldata scopeOfWorkURI,
        uint32 termLength,
        ERC20 streamToken,
        uint256 totalStreamedTokens,
        TerminationClauses calldata terminationClauses
    ) external {
        // TODO: What if they reeagree on the same agreement id after an agreement has been created?
        if (msg.sender != provider && msg.sender != receiver) {
            revert NOT_SENDER_OR_RECEIVER();
        }
        if (streamToken.decimals() < 4) revert INCOMPATIBLE_TOKEN();
        if (termLength == 0) revert INVALID_TERM_LENGTH();

        bytes32 agreementGUID = keccak256(
            abi.encode(
                agreementId,
                provider,
                receiver,
                scopeOfWorkURI,
                termLength,
                streamToken,
                totalStreamedTokens,
                terminationClauses
            )
        );
        address counterParty = msg.sender == provider ? receiver : provider;

        // if the agreement has not been signed by the counter party, mark this party's approval and emit an event
        if (!isAgreementSigned[agreementGUID][counterParty]) {
            isAgreementSigned[agreementGUID][msg.sender] = true;

            emit AgreementProposed(
                agreementGUID,
                agreementId,
                provider,
                receiver,
                scopeOfWorkURI,
                termLength,
                streamToken,
                totalStreamedTokens,
                terminationClauses
            );
            return;
        }

        // if both parties agree:
        // cleanup their old agreement signature
        delete isAgreementSigned[agreementGUID][counterParty];

        // pull tokens
        // create a new agreement contract
        address agreement = address(agreementSingleton).cloneDeterministic(
            agreementGUID
        );

        // initialize the agreement
        ContractooorAgreement(agreement).initialize(
            Agreement({
                provider: provider,
                receiver: receiver,
                atWillDays: terminationClauses.atWillDays,
                cureTimeDays: terminationClauses.cureTimeDays,
                legalCompulsion: terminationClauses.legalCompulsion,
                counterpartyMalfeasance: terminationClauses
                    .counterpartyMalfeasance,
                bankruptcyDissolutionInsolvency: terminationClauses
                    .bankruptcyDissolutionInsolvency,
                counterpartyLostControlOfPrivateKeys: terminationClauses
                    .counterpartyLostControlOfPrivateKeys,
                scopeOfWorkURI: scopeOfWorkURI
            })
        );

        // emit an agreement initiated event
        emit AgreementInitiated(agreementGUID, agreement);
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
    ) internal {}
}

// bytes32 agreementUUID = keccak256(
//     abi.encode(agreementId, provider, receiver)
// );

// uint256 remainingTokens = totalStreamedTokens %
//     (endTimestamp - block.timestamp);

// streamToken.safeTransferFrom(
//     receiver,
//     address(this),
//     totalStreamedTokens
// );
// streamToken.safeTransfer(provider, remainingTokens);
// streamToken.approve(
//     address(sablier),
//     totalStreamedTokens - remainingTokens
// );
// uint256 streamId = sablier.createStream({
//     recipient: provider,
//     deposit: totalStreamedTokens - remainingTokens,
//     tokenAddress: address(streamToken),
//     startTime: block.timestamp,
//     stopTime: endTimestamp
// });

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
