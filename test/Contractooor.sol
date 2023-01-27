// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ERC20, MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import "src/Contractooor.sol";
import {SablierMock} from "./mocks/SablierMock.sol";

contract ContractooorTest is Test {
    SablierMock sablier;
    MockERC20 token;
    Contractooor contractooor;

    address sp = address(0x1);
    address sr = address(0x2);

    function setUp() public {
        sablier = new SablierMock();
        token = new MockERC20("Test", "TST", 18);
        contractooor = new Contractooor(address(sablier));

        vm.label(sp, "SERVICE PROVIDER");
        vm.label(sr, "SERVICE RECEIVER");
    }

    function test_initiateAgreement() public {
        token.mint(sr, 10000 ether);

        vm.prank(sr);
        token.approve(address(contractooor), 10000 ether);

        vm.prank(sp);
        contractooor.proposeAgreement(
            1,
            sp,
            sr,
            "https://example.com",
            uint32(block.timestamp + 30 days),
            token,
            2999999999999998944000,
            Contractooor.TerminationClauses(0, 0, false, false, false, false)
        );

        vm.prank(sr);
        contractooor.proposeAgreement(
            1,
            sp,
            sr,
            "https://example.com",
            uint32(block.timestamp + 30 days),
            token,
            2999999999999998944000,
            Contractooor.TerminationClauses(0, 0, false, false, false, false)
        );
    }

    function test_cannotInitiateStreamForCounterParty() public {}

    function test_cannotCancelStreamUnlessContractOrProvider() public {}
}
