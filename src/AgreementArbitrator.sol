// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISablier} from "@sablier/protocol/contracts/interfaces/ISablier.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Clones} from "@openzeppelin/proxy/Clones.sol";
import {TerminationClauses, Agreement} from "contracts/lib/Types.sol";
import {ContractooorAgreement} from "contracts/ContractooorAgreement.sol";

/// @title AgreementArbitrator
/// @author @colinnielsen
/// @notice A light-weight agremement arbitrator for contractors and clients to create streaming contracts in exchange for services
contract AgreementArbitrator {
    using SafeERC20 for IERC20;
    using Clones for address;

    ISablier public sablier;
    ContractooorAgreement private agreementSingleton;
    mapping(bytes32 => bytes32) agreementSignature;

    error NOT_CLIENT();
    error NOT_SENDER_OR_CLIENT();
    error INCOMPATIBLE_TOKEN();
    error INVALID_TERM_LENGTH();

    event AgreementProposed(
        bytes32 indexed agreementHash,
        uint256 agreementNonce,
        address proposer,
        address indexed provider,
        address indexed client,
        string contractURI,
        uint32 targetEndTimestamp,
        address streamToken,
        uint256 totalStreamedTokens,
        TerminationClauses terminationClauses
    );

    event AgreementInitiated(
        uint256 agreementNonce,
        address indexed provider,
        address indexed client,
        address contractooorAgreement,
        uint256 streamId
    );

    constructor(address _sablier, address _agreementSingleton) {
        sablier = ISablier(_sablier);
        agreementSingleton = ContractooorAgreement(_agreementSingleton);
    }

    /// @notice a single function for parties to offer, counter-offer, and agree to a contract
    /// @dev takes the hash of all the parameters to make an `agreementHash`, which is counter-signed, then used as salt for the contract deployment
    /// @notice SPEC:
    /// A call to this function will prompt pull tokens from the service client, and create a stream of those tokens to the service provider given:
    ///     A1. Either the `provider` or `client` have called this function with the exact same arguments - otherwise :: marks the agreement as signed
    ///     A2. The `msg.sender` is the `provider` or `client` address
    ///     A3. The `termLength` is not 0
    ///     A4. The `streamToken` has > 4 decimals, making it sablier compatible
    ///     A5. If the agreement has already been counterparty signed, this contract must have `totalStreamedTokens` worth of operator approval from `client`
    ///
    /// RES-A. If `msg.sender` is the first signing party:
    ///     RES-A.1: Mark the user's signature of the `agreementHash` as true
    ///         an agreement hash is defined as: the keccak256 hash of all the abi.encoded calldata parameters
    ///     RES-A.2: emit an AgreementProposed event with the `agreementHash` and all the calldata parameters
    ///
    /// RES-B. If `msg.sender` is the second party to sign:
    ///     RES-B.1: delete the counterparty's leftover signature
    ///     RES-B.2: transfer `remainder` of tokens to the `provider` (this is to prevent rounding errors in the sablier stream)
    ///     RES-B.3: send `totalStreamedTokens` - `remainder` of tokens to the Contractooor contract
    ///     RES-B.4: create a new Contractooor agreement proxy clone
    ///     RES-B.5: call `initialize` on the new proxy clone
    ///     RES-B.6: emit an `AgreementInitiated` event with the `agreementHash` and the Contractooor addresss
    function agreeTo(
        uint256 agreementNonce,
        address provider,
        address client,
        string calldata contractURI,
        uint32 termLength,
        address streamToken,
        uint256 totalStreamedTokens,
        TerminationClauses calldata terminationClauses
    ) external {
        if (msg.sender != provider && msg.sender != client) revert NOT_SENDER_OR_CLIENT();
        if (termLength == 0) revert INVALID_TERM_LENGTH();

        bytes32 agreementId = keccak256(abi.encode(agreementNonce, provider, client));

        address counterParty = msg.sender == provider ? client : provider;

        // if the agreement has not been signed by the counter party, mark this party's approval and emit an event
        if (
            agreementSignature[agreementId]
                != getAgreementHash({
                    signingParty: counterParty,
                    agreementNonce: agreementNonce,
                    provider: provider,
                    client: client,
                    contractURI: contractURI,
                    termLength: termLength,
                    streamToken: streamToken,
                    totalStreamedTokens: totalStreamedTokens,
                    terminationClauses: terminationClauses
                })
        ) {
            bytes32 userAgreementHash = getAgreementHash({
                signingParty: msg.sender,
                agreementNonce: agreementNonce,
                provider: provider,
                client: client,
                contractURI: contractURI,
                termLength: termLength,
                streamToken: streamToken,
                totalStreamedTokens: totalStreamedTokens,
                terminationClauses: terminationClauses
            });

            agreementSignature[agreementId] = userAgreementHash;

            emit AgreementProposed(
                userAgreementHash,
                agreementNonce,
                msg.sender,
                provider,
                client,
                contractURI,
                termLength,
                streamToken,
                totalStreamedTokens,
                terminationClauses
            );
            return;
        }

        // if both parties agree:
        delete agreementSignature[agreementId];
        address contractooorAgreement = address(agreementSingleton).predictDeterministicAddress(agreementId);

        // pull tokens:
        // we want to transfer the tokens before deploying the contract because we want to avoid
        //  having malicious tokens from reentering or tampering with our uninitialized stream contract
        IERC20(streamToken).safeTransferFrom(client, provider, totalStreamedTokens % termLength);
        IERC20(streamToken).safeTransferFrom(
            client,
            contractooorAgreement,
            // this pattern is a nuance of sablier v1.
            //  The total stream length must fit evenly into the total tokens streamed
            totalStreamedTokens - (totalStreamedTokens % termLength)
        );

        uint256 streamId;

        // create a new contractooorAgreement contract
        {
            address(agreementSingleton).cloneDeterministic(agreementId);
            Agreement memory initData = Agreement({
                provider: provider,
                client: client,
                atWillDays: terminationClauses.atWillDays,
                cureTimeDays: terminationClauses.cureTimeDays,
                legalCompulsion: terminationClauses.legalCompulsion,
                moralTurpitude: terminationClauses.moralTurpitude,
                counterpartyMalfeasance: terminationClauses.counterpartyMalfeasance,
                bankruptcyDissolutionInsolvency: terminationClauses.bankruptcyDissolutionInsolvency,
                lostControlOfPrivateKeys: terminationClauses.lostControlOfPrivateKeys,
                contractURI: contractURI
            });

            uint256 tokensToStream = totalStreamedTokens - (totalStreamedTokens % termLength);
            // initialize the contractooorAgreement
            streamId = ContractooorAgreement(contractooorAgreement).initialize(
                sablier, streamToken, tokensToStream, termLength, initData
            );
        }

        // emit an contractooorAgreement initiated event
        emit AgreementInitiated(agreementNonce, provider, client, contractooorAgreement, streamId);
    }

    function getAgreementHash(
        address signingParty,
        uint256 agreementNonce,
        address provider,
        address client,
        string calldata contractURI,
        uint32 termLength,
        address streamToken,
        uint256 totalStreamedTokens,
        TerminationClauses calldata terminationClauses
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                signingParty,
                agreementNonce,
                provider,
                client,
                contractURI,
                termLength,
                streamToken,
                totalStreamedTokens,
                terminationClauses
            )
        );
    }
}
