// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ISablier} from "@sablier/protocol/contracts/interfaces/ISablier.sol";
import {Initializable} from "@openzeppelin/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {TerminationClauses, Agreement, TerminationReason} from "contracts/lib/Types.sol";
import {AgreementArbitrator} from "contracts/AgreementArbitrator.sol";

import {console2} from "forge-std/console2.sol";

uint256 constant MAX_BREACH_ALLOWANCE = 3;

/// @title ContractooorAgreement
/// @author @colinnielsen
/// @notice Arbitrates agremements between a service provider and a client
contract ContractooorAgreement is Initializable {
    using SafeERC20 for IERC20;

    error NOT_RECEIVER();
    error NOT_CLIENT_OR_SERVICE_PROVIDER();
    error NOT_CLIENT();
    error NOT_SERVICE_PROVIDER();
    error NOT_AUTHORIZED();
    error NO_BREACH_NOTICE_ISSUED();
    error INCOMPATIBLE_TOKEN();
    error INVALID_END_TIME();
    error CURE_TIME_NOT_MET();
    error RAGE_TERMINATION_NOT_ALLOWED();
    error STREAM_CANCELLATION_FAILED();

    event TerminationProposed(address indexed proposer, string terminationInfo, TerminationReason indexed reason);
    event TerminationProposalDeleted(
        address indexed proposer, string information, TerminationReason indexed initialTerminationReason
    );
    event RageTermination(address indexed terminator, string terminationInfo, TerminationReason indexed reason);
    event AgreementTerminated(address indexed terminator, TerminationReason indexed reason);

    AgreementArbitrator private arbitrator;
    ISablier private sablier;
    uint96 public streamId;
    Agreement public agreement;

    bytes32 public mutualConsentTerminationId;
    mapping(address => uint256) public atWillTerminationTimestamp;
    mapping(address => uint256) public materialBreachTimestamp;
    uint256 public timesContractBreached;

    constructor() {
        _disableInitializers();
    }

    function onlyClient() internal view returns (address otherParty) {
        Agreement memory _agreement = agreement;
        if (msg.sender != _agreement.client) revert NOT_CLIENT();
        otherParty = msg.sender == _agreement.client ? _agreement.provider : _agreement.client;
    }

    function onlyServiceProvider() internal view returns (address otherParty) {
        Agreement memory _agreement = agreement;
        if (msg.sender != _agreement.provider) revert NOT_SERVICE_PROVIDER();
        otherParty = msg.sender == _agreement.client ? _agreement.provider : _agreement.client;
    }

    function onlyClientOrServiceProvider() internal view returns (address otherParty) {
        Agreement memory _agreement = agreement;
        if (msg.sender != _agreement.client && msg.sender != _agreement.provider) {
            revert NOT_CLIENT_OR_SERVICE_PROVIDER();
        }
        otherParty = msg.sender == _agreement.client ? _agreement.provider : _agreement.client;
    }

    /// @notice initializes this agreement and begins a stream with the current tokens of this contract
    /// @notice SPEC:
    /// This function will begin a new stream with the contract's balance of tokens to the recipient given:
    ///     I1. The `sablier` param is a compliant sablier implementation
    ///     I2. The `streamToken` param is a compliant ERC20 token
    ///     I3. This contract has at least `tokensToStream` amount of `streamToken`
    ///     SABLIER SPEC:
    ///     S1. `agreement.recipient` is none of the following: the 0 address, the `_sablier` contract, this address
    ///     S2. `tokensToStream` is not 0
    ///     S3. `termLength` is not equal to block.timestamp
    ///     S4. the tokens streamed per second cannot be less than 1 wei
    ///     S5. the `tokensToStream` is a multiple of `termLength`
    ///
    /// RESI: given the above, this function will:
    ///     RESI-1. Stores the msg.sender as the `arbitrator`
    ///     RESI-2. Stores the `_sablier` param
    ///     RESI-3. Stores the `_agreement` param
    ///     RESI-4. Approves `sablier` to spend `tokensToStream`
    ///     RESI-5. Initializes a sablier stream
    ///
    /// RETURNS: the sablier streamId
    function initialize(
        ISablier _sablier,
        address streamToken,
        uint256 tokensToStream,
        uint256 termLength,
        Agreement calldata _agreement
    ) public initializer returns (uint256 _streamId) {
        arbitrator = AgreementArbitrator(msg.sender);
        sablier = _sablier;
        agreement = _agreement;

        IERC20(streamToken).approve(address(_sablier), tokensToStream);

        _streamId = sablier.createStream({
            recipient: _agreement.provider,
            deposit: tokensToStream,
            tokenAddress: address(streamToken),
            startTime: block.timestamp,
            stopTime: block.timestamp + termLength
        });

        streamId = uint96(_streamId);
    }

    ///
    /// MUTUAL CONSENT TERMINATION
    ///

    /// @notice allows a party (a client or service provider) to propose a termination by mutual consent
    /// @notice a party can pass a terminationInfo (an IPFS hash, a URL, an emoji) to provide context for the termination proposal.
    ///       the counter party must pass in the same terminationInfo as acknowledgement of the termination reason
    /// @notice SPEC:
    /// A valid call to this function will do either of the following:
    ///     I: Allows either the service provider or the client to initiate a termination
    ///     E: Allows either the service provider or the client to execute a termination if the other party has already initiated
    ///
    ///     I: Either party can initiate given:
    ///     I1. The msg.sender is either the client or the service provider -> otherwise, reverts
    ///     I2. The keccak256 hash of the `terminationProposalURI` and the counter party's address has not previously been stored in `mutualConsentTerminationId`
    ///
    ///     RESI: given the above, this function will:
    ///     RESI-1. Store the keccak256 hash of the `terminationProposalURI` and the msg.sender's address in `mutualConsentTerminationId`
    ///     RESI-2. Emit a `TerminationProposed` event

    ///     E: Either party can execute given:
    ///     E1. The msg.sender is either the client or the service provider -> otherwise, reverts
    ///     E2. The keccak256 hash of the `terminationProposalURI` and the other party's address has previously been stored in `mutualConsentTerminationId`
    ///
    ///     RESE: given the above, this function will:
    ///     RESE-1. Call `_terminateAgreement`
    ///
    function terminateByMutualConsent(string memory terminationInfo) public {
        // SPEC.I1, SPEC.E1
        address otherParty = onlyClientOrServiceProvider();
        bytes32 mutualConsentCancellationHash = keccak256(abi.encode(terminationInfo, otherParty));

        if (mutualConsentTerminationId == mutualConsentCancellationHash) {
            // SPEC.E2
            // RESE-1
            _terminateAgreement(TerminationReason.MutualConsent);
        } else {
            // SPEC.I2
            // SPEC.RESI-1
            mutualConsentTerminationId = keccak256(abi.encode(terminationInfo, msg.sender));

            // SPEC.RESI-2
            emit TerminationProposed(msg.sender, terminationInfo, TerminationReason.MutualConsent);
        }
    }

    ///
    /// MATERIAL BREACH
    ///

    /// @notice allows a party (a client or service provider) to issue notice of material breach, thus initiating the termination process
    /// @notice a party can pass `breachInfo` specifying the nature of the breach. A party can submit as many notices as they deem necessary,
    ///     however, they should consider that submitting a notice resets the time they must wait to exit the agreement.
    /// @notice SPEC:
    /// A valid call to this function will set the initiate the material breach termination process given:
    ///     S1: the `msg.sender` is either the client or the service provider
    ///
    ///     RES1: sets the `materialBreachTimestamp` to the current timestamp
    ///     RES2: emits a `TerminationProposed` event
    ///
    function issueNoticeOfMaterialBreach(string memory breachInfo) public {
        // SPEC.S1
        onlyClientOrServiceProvider();
        // SPEC.RES1
        materialBreachTimestamp[msg.sender] = block.timestamp;

        // SPEC.RES2
        emit TerminationProposed(msg.sender, breachInfo, TerminationReason.MaterialBreach);
    }

    /// @notice allows a party to withdraw their breach notice
    /// @notice this may be done to provide assurance that a remedied agreement will not be terminated at any point
    /// @notice SPEC:
    /// A valid call to this function will set the delete the caller's `materialBreachTimestamp` given:
    ///     S1: the `msg.sender` is either the client or the service provider
    ///
    ///     RES1: clears `materialBreachTimestamp` to 0
    ///     RES2: emits a `TerminationProposalDeleted` event
    ///
    function withdrawNoticeOfMaterialBreach(string memory withdrawalReason) public {
        // SPEC.S1
        onlyClientOrServiceProvider();
        // SPEC.RES1
        delete materialBreachTimestamp[msg.sender];

        // SPEC.RES2
        emit TerminationProposalDeleted(msg.sender, withdrawalReason, TerminationReason.MaterialBreach);
    }

    /// @notice allows a party to submit a notice that they have remedied the counter party's accusation of material breach
    /// @notice the curing party should supply information describing the nature of their breach cure
    /// @notice SPEC:
    /// A valid call to this function will set the delete the counter party's `materialBreachTimestamp` given:
    ///     S1: the `msg.sender` is either the client or the service provider
    ///     S2: the counter party submitted a notice of material breach
    ///
    ///     RES1: clears the counter party's `materialBreachTimestamp` to 0
    ///     RES2: increments a `timesCountractBreached` timestamp - this is a protection mechanism for the counter party: see `terminateByMaterialBreach`
    ///     RES3: emits a `TerminationProposalDeleted` event
    ///
    function issueNoticeOfCure(string memory cureInfo) public {
        // SPEC.S1
        address counterParty = onlyClientOrServiceProvider();

        // SPEC.S2
        uint256 timestamp = materialBreachTimestamp[counterParty];
        if (timestamp == 0) revert NO_BREACH_NOTICE_ISSUED();

        // SPEC.RES1
        delete materialBreachTimestamp[counterParty];
        // SPEC.RES2
        timesContractBreached++;

        // SPEC.RES3
        emit TerminationProposalDeleted(msg.sender, cureInfo, TerminationReason.MaterialBreach);
    }

    /// @notice allows a party to terminate an agreement by nature of material breach
    /// @notice SPEC:
    /// A valid call to this function will terminate the agreement given:
    ///     S1: the `msg.sender` is either the client or the service provider
    ///     S2: `issueNoticeOfMaterialBreach` was called by the msg.sender
    ///     S3:
    ///         S3.1: it has been `cureTimeDays` since the material breach notice was issued
    ///         OR:
    ///         S3.2: the contract has been breached more than the max breach allowance has specified:
    ///             -> otherwise reverts
    ///
    ///     RES1: clears the msg.sender's `materialBreachTimestamp` to 0
    ///     RES2: terminates the agreement and distributes the remaining tokens the the correct parties
    ///
    function terminateByMaterialBreach() public {
        // SPEC.S1
        onlyClientOrServiceProvider();

        uint256 issueTimestamp = materialBreachTimestamp[msg.sender];
        bool curetimeReached = issueTimestamp != 0 // SPEC.S2
            // SPEC.S3.1
            && block.timestamp > (uint256(agreement.cureTimeDays) * 1 days) + issueTimestamp;

        if (
            // SPEC.S3.1
            !curetimeReached
            // SPEC.S3.2
            || timesContractBreached < MAX_BREACH_ALLOWANCE
        ) revert CURE_TIME_NOT_MET();

        // @dev done for a gas refund
        // SPEC.RES1
        delete materialBreachTimestamp[msg.sender];

        // SPEC.RES2
        _terminateAgreement(TerminationReason.MaterialBreach);
    }

    ///
    /// AT WILL TERMINATION
    ///

    /// @notice allows a party to begin to terminate an agreement at their own will
    /// @notice SPEC:
    /// A valid call to this function will mark a party's at will termination given:
    ///     S1: the `msg.sender` is either the client or the service provider
    ///
    ///     RES1: marks the `msg.sender`'s `atWillTerminationTimestamp` to the current timestamp
    ///     RES2: emits a `TerminationProposalDeleted` event
    ///
    function issueNoticeOfTermination(string memory terminationInfo) public {
        // SPEC.S1
        onlyClientOrServiceProvider();
        // SPEC.RES2
        atWillTerminationTimestamp[msg.sender] = block.timestamp;

        // SPEC.RES2
        emit TerminationProposed(msg.sender, terminationInfo, TerminationReason.AtWill);
    }

    /// @notice allows a party to begin to execute an at will termination
    /// @notice SPEC:
    /// A valid call to this function will terminate the agreement given:
    ///     S1: `issueNoticeOfTermination` was called by the msg.sender
    ///     S2: it has been `atWillDays` since the notice was issued -> otherwise: reverts
    ///
    ///     RES1: clears the `msg.sender`'s `atWillTerminationTimestamp` to 0
    ///     RES2: terminates the agreement and distributes the remaining tokens the the correct parties
    ///
    function terminateAtWill() public {
        uint256 terminationProposalTimestamp = atWillTerminationTimestamp[msg.sender];
        if (
            // SPEC.S1
            terminationProposalTimestamp == 0
            // SPEC.S2.1
            || block.timestamp < (uint256(agreement.atWillDays) * 1 days) + terminationProposalTimestamp
        ) revert CURE_TIME_NOT_MET();

        // @dev done for a gas refund
        // SPEC.RES1
        delete atWillTerminationTimestamp[msg.sender];

        // SPEC.RES2
        _terminateAgreement(TerminationReason.AtWill);
    }

    ///
    /// RAGE TERMINATION
    ///

    /// @notice allows a party to trigger an arbitrary termination 🔥
    /// @notice see u in court
    /// @notice SPEC:
    /// A valid call to this function will terminate the agreement given:
    ///     S1: the msg.sender is either the client or service provider -> otherwise: reverts
    ///     S2: the termination reason parameter is a rage terminationReason -> otherwise: reverts
    ///     S3: the termination reason parameter are allowed, as per the agreement -> otherwise: reverts
    ///
    ///     RES1: emits a `RageTermination` event
    ///     RES2: terminates the agreement and distributes the remaining tokens the the correct parties
    ///
    function rageTerminate(TerminationReason reason, string memory terminationInfo) public {
        // SPEC.S1
        onlyClientOrServiceProvider();
        Agreement memory _agreement = agreement;

        if (
            // SPEC.S2
            uint256(reason) < 3
            // SPEC.S3
            || (reason == TerminationReason.LegalCompulsion && !_agreement.legalCompulsion)
                || (reason == TerminationReason.CrimesOfMoralTurpitude && !_agreement.moralTurpitude)
                || (reason == TerminationReason.Bankruptcy && !_agreement.bankruptcyDissolutionInsolvency)
                || (reason == TerminationReason.Dissolution && !_agreement.bankruptcyDissolutionInsolvency)
                || (reason == TerminationReason.Insolvency && !_agreement.bankruptcyDissolutionInsolvency)
                || (reason == TerminationReason.CounterPartyMalfeasance && !_agreement.counterpartyMalfeasance)
                || (reason == TerminationReason.LossControlOfPrivateKeys && !_agreement.lostControlOfPrivateKeys)
        ) {
            revert RAGE_TERMINATION_NOT_ALLOWED();
        }

        // SPEC.RES1
        emit RageTermination(msg.sender, terminationInfo, reason);
        // SPEC.RES2
        _terminateAgreement(reason);
    }

    /// @notice allows remaining token balances to be transferred back to the client
    ///     in the case of an external cancellation from sablier
    /// @notice SPEC:
    /// A valid call to this function will transfer any of this contract's balance of `streamToken` to the client givem:
    ///     S1: streamToken does not revert a `transfer` call
    function emergencyRecoverTokens(address streamToken) public {
        // SPEC.S1
        IERC20(streamToken).safeTransfer(agreement.client, IERC20(streamToken).balanceOf(address(this)));
    }

    /// @notice allows a function to trigger a termination of this agreement
    /// @notice SPEC:
    /// A valid call to this function will terminate the agreement given:
    ///     S1: the `getStream` call does not fail. Will fail if:
    ///         1. The stream was cancelled by the recipient
    ///         2. The stream was depleted then tokens were withdrawn
    ///     S2: the `cancelStream` call does not fail. Will fail if:
    ///         1. The stream was cancelled by the recipient (checked above)
    ///         2. Any the token transfer fails
    ///     S3: `cancelStream` does not return false (should never happen)
    ///     S4: the `transfer` call on `streamToken` does not fail
    ///
    ///     RES1: The stream is cancelled and deleted in sablier -thus transferring paid tokens to the service provider
    ///     RES2: The remaining stream token is transferred back to the client
    ///     RES3: The `AgreementTerminated` event is emitted
    ///
    function _terminateAgreement(TerminationReason reason) internal {
        uint256 _streamId = streamId;
        // SPEC.S1 - 1,2
        (,,, address streamToken,,,,) = sablier.getStream(_streamId);

        // SPEC.S2 - 1,2, SPEC.RES1
        bool cancelled = sablier.cancelStream(_streamId);
        // SPEC.S3
        if (!cancelled) revert STREAM_CANCELLATION_FAILED();

        // SPEC.RES2
        IERC20(streamToken).safeTransfer(agreement.client, IERC20(streamToken).balanceOf(address(this)));

        // SPEC.RES3
        emit AgreementTerminated(msg.sender, reason);
    }
}
