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

    function test_initiateAgreement(uint256 streamAmount) public {
        vm.assume(streamAmount > 30 days && streamAmount < type(uint128).max);
        uint256 timestamp = 1674941221;
        vm.warp(timestamp);
        uint32 endTime = uint32(block.timestamp + 30 days);

        token.mint(sr, streamAmount);

        vm.prank(sr);
        token.approve(address(contractooor), streamAmount);

        vm.prank(sp);
        contractooor.proposeAgreement(
            1,
            sp,
            sr,
            "https://example.com",
            endTime,
            token,
            streamAmount,
            Contractooor.TerminationClauses(0, 0, false, false, false, false)
        );

        vm.prank(sr);
        contractooor.proposeAgreement(
            1,
            sp,
            sr,
            "https://example.com",
            endTime,
            token,
            streamAmount,
            Contractooor.TerminationClauses(0, 0, false, false, false, false)
        );

        uint256 leftOvertokens = streamAmount % (endTime - block.timestamp);

        (
            address sender,
            address recipient,
            uint256 deposit,
            address tokenAddress,
            uint256 startTime,
            uint256 stopTime,
            ,
        ) = sablier.getStream(100000);

        assertEq(sender, address(contractooor), "sender");
        assertEq(recipient, sp, "recipient");
        assertEq(deposit, streamAmount - leftOvertokens, "streamAmount");
        assertEq(startTime, block.timestamp, "startTime");
        assertEq(stopTime, endTime, "stopTime");
        assertEq(tokenAddress, address(token));
        assertEq(token.balanceOf(address(sp)), leftOvertokens, "initial deposit");

        vm.warp(endTime);
        vm.prank(sp);
        sablier.withdrawFromStream(100000, streamAmount - leftOvertokens);
        assertEq(token.balanceOf(address(sp)), streamAmount, "final deposit");
    }

    function test_cannotInitiateStreamForCounterParty() public {}

    function test_cannotCancelStreamUnlessContractOrProvider() public {}
}
