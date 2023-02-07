// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ISablier} from "@sablier/protocol/contracts/interfaces/ISablier.sol";
import {Initializable} from "@openzeppelin/proxy/utils/Initializable.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {TerminationClauses, Agreement} from "contracts/lib/Types.sol";

import {console2} from "forge-std/console2.sol";

/// @title ContractooorAgreement
/// @author @colinnielsen
/// @notice Arbitrates agremements between Service Providers and Service Receivers
contract ContractooorAgreement is Initializable {
    using SafeTransferLib for ERC20;

    error NOT_RECEIVER();
    error NOT_SENDER_OR_RECEIVER();
    error INCOMPATIBLE_TOKEN();
    error INVALID_END_TIME();

    Agreement public agreement;

    constructor() {
        _disableInitializers();
    }

    function initialize(Agreement calldata agreement) public initializer returns (uint256 streamId) {
        // sablier = ISablier(_sablier);
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
