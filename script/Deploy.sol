// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

import "forge-std/Script.sol";
import "contracts/AgreementArbitrator.sol";
import "contracts/ContractooorAgreement.sol";
import "forge-std/console2.sol";

contract Deployer is Script {
    function run() external {
        // load fee receiver + lock state from the bash environment
        address sablier = vm.envAddress("SABLIER_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        ContractooorAgreement agreementSingleton = new ContractooorAgreement();
        AgreementArbitrator arbitrator = new AgreementArbitrator(
            address(sablier),
            address(agreementSingleton)
        );
        vm.stopBroadcast();

        console2.log("agreementSingleton", address(agreementSingleton));
        console2.log("arbitrator", address(arbitrator));
    }

    // function deploy_test(
    //     address _deployer,
    //     address _feeReceiver,
    //     LockState _initialLockState,
    //     uint256 _feeBPS
    // ) public returns (BullaClaim, BullaFeeCalculator) {
    //     vm.startPrank(_deployer);
    //     _deploy(_feeReceiver, _initialLockState);
    //     feeCalculator = new BullaFeeCalculator(_feeBPS);

    //     vm.stopPrank();

    //     return (bullaClaim, feeCalculator);
    // }

    // function _deploy(address _feeReceiver, LockState _initialLockState)
    //     internal
    // {
    //     extensionRegistry = new BullaExtensionRegistry();
    //     bullaClaim = new BullaClaim(
    //         _feeReceiver,
    //         address(extensionRegistry),
    //         _initialLockState
    //     );
    // }
}
