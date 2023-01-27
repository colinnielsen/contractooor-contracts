// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/Contractooor.sol";
import {SablierMock} from "./mocks/SablierMock.sol";

contract ContractooorTest is Test {
    Contractooor public contractooor;

    function setUp() public {
        contractooor = new Contractooor();
    }

    function test_initiateAgreement() public {}

    function test_cannotInitiateStreamForCounterParty() public {}

    function test_cannotCancelStreamUnlessContractOrProvider() public {}
}
