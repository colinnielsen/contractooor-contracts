// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ISablier} from "@sablier/protocol/contracts/interfaces/ISablier.sol";
import {Initializable} from "@openzeppelin/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {TerminationClauses, Agreement} from "contracts/lib/Types.sol";
import {AgreementArbitrator} from "contracts/AgreementArbitrator.sol";

import {console2} from "forge-std/console2.sol";

/// @title ContractooorAgreement
/// @author @colinnielsen
/// @notice Arbitrates agremements between a service provider and a client
contract ContractooorAgreement is Initializable {
    using SafeERC20 for IERC20;

    error NOT_RECEIVER();
    error NOT_SENDER_OR_RECEIVER();
    error NOT_CLIENT();
    error NOT_SERVICE_PROVIDER();
    error NOT_AUTHORIZED();
    error INCOMPATIBLE_TOKEN();
    error INVALID_END_TIME();
    error INVALID_CURE_TIME();
    error STREAM_CANCELLATION_FAILED();

    AgreementArbitrator private arbitrator;
    ISablier private sablier;
    uint96 public streamId;
    Agreement public agreement;

    bytes32 public mutualConsentTerminationId;
    mapping(address => uint256) public atWillTerminationTimestamp;

    constructor() {
        _disableInitializers();
    }

    function onlyClient() internal view returns (address otherParty) {
        Agreement memory _agreement = agreement;
        if (msg.sender != _agreement.client) revert NOT_CLIENT();
        otherParty = msg.sender == _agreement.client
            ? _agreement.provider
            : _agreement.client;
    }

    function onlyServiceProvider() internal view returns (address otherParty) {
        Agreement memory _agreement = agreement;
        if (msg.sender != _agreement.provider) revert NOT_SERVICE_PROVIDER();
        otherParty = msg.sender == _agreement.client
            ? _agreement.provider
            : _agreement.client;
    }

    function onlyClientOrServiceProvider()
        internal
        view
        returns (address otherParty)
    {
        Agreement memory _agreement = agreement;
        if (
            msg.sender != _agreement.client && msg.sender != _agreement.provider
        ) revert NOT_SENDER_OR_RECEIVER();
        otherParty = msg.sender == _agreement.client
            ? _agreement.provider
            : _agreement.client;
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

    /// @notice allows a party to propose a termination by mutual consent
    /// @notice a party can pass a terminationInfo (an IPFS hash, a URL, an emoji) to provide context for the termination proposal.
    ///       the counter party must pass in the same terminationInfo as acknowledgement of the termination reason
    /// @notice SPEC:
    /// A valid call to this function will do either of the following:
    ///     I: Allows either the service provider or the client to initiate a termination
    ///     E: Allows either the service provider or the client to execute a termination if the other party has already initiated
    ///
    ///     I: Either party can initiate given:
    ///     I1. The msg.sender is either the client or the service provider -> otherwise, reverts
    ///     I2. The keccak256 hash of the `terminationProposalURI` and the other party's address has not previously been stored in `mutualConsentTerminationId`
    ///
    ///     RESI: given the above, this function will:
    ///     RESI-1. Store the keccak256 hash of the `terminationProposalURI` and the msg.sender's address in `mutualConsentTerminationId`
    ///     RESI-2. Emit a `TerminationProposed` event

    ///     E: Either party can execute given:
    ///     E1. The msg.sender is either the client or the service provider -> otherwise, reverts
    ///     E2. The keccak256 hash of the `terminationProposalURI` and the other party's address has previously been stored in `mutualConsentTerminationId`
    ///
    ///     RESI: given the above, this function will:
    ///     RESI-1. Call `_terminateAgreement`
    ///
    function terminateByMutualConsent(string memory terminationInfo) public {
        address otherParty = onlyClientOrServiceProvider();
        bytes32 mutualConsentCancellationHash = keccak256(
            abi.encode(terminationInfo, otherParty)
        );

        if (mutualConsentTerminationId == mutualConsentCancellationHash) {
            _terminateAgreement();
        } else {
            mutualConsentTerminationId = keccak256(
                abi.encode(terminationInfo, msg.sender)
            );
        }
    }

    ///
    /// AT WILL TERMINATION
    ///

    function issueNoticeOfTermination(string memory terminationInfo) public {
        onlyClientOrServiceProvider();
        atWillTerminationTimestamp[msg.sender] = block.timestamp;
        // TODO: emit event
    }

    function terminateAtWill() public {
        onlyClientOrServiceProvider();
        uint256 terminationProposalTimestamp = atWillTerminationTimestamp[
            msg.sender
        ];
        if (
            terminationProposalTimestamp == 0 ||
            block.timestamp <
            terminationProposalTimestamp + agreement.atWillDays
        ) {
            revert INVALID_CURE_TIME();
        }

        _terminateAgreement();
    }

    // cancel the stream and transfer unspent tokens back to the client
    //   (sablier handles the refund of the service provider, who is the recipient)
    function _terminateAgreement() internal {
        (, , , address streamToken, , , , ) = sablier.getStream(streamId);

        bool cancelled = sablier.cancelStream(streamId);
        if (!cancelled) revert STREAM_CANCELLATION_FAILED();

        IERC20(streamToken).safeTransfer(
            agreement.client,
            IERC20(streamToken).balanceOf(address(this))
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
