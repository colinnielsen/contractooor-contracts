// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {ERC20Mock} from "@openzeppelin/mocks/ERC20Mock.sol";
import {TerminationClauses, Agreement} from "contracts/lib/Types.sol";
import {AgreementArbitrator} from "src/AgreementArbitrator.sol";
import {ContractooorAgreement} from "src/ContractooorAgreement.sol";

import {SablierMock} from "./mocks/SablierMock.sol";

contract Tests is Test {
    SablierMock sablier;
    ERC20Mock token;
    AgreementArbitrator arbitrator;

    address serviceProvider = address(0x1);
    address client = address(0x2);

    function setUp() public {
        sablier = new SablierMock();
        token = new ERC20Mock("Test", "TST", address(this), 10000 ether);

        ContractooorAgreement agreementSingleton = new ContractooorAgreement();
        arbitrator = new AgreementArbitrator(
            address(sablier),
            address(agreementSingleton)
        );

        vm.label(serviceProvider, "SERVICE PROVIDER");
        vm.label(client, "SERVICE RECEIVER");
    }

    function test_initiateAgreement(uint256 agreementAmount) public {
        uint32 TERM_LENGTH = 30 days;
        vm.assume(agreementAmount > TERM_LENGTH && agreementAmount < type(uint128).max);

        uint256 timestamp = 1674941221;
        vm.warp(timestamp);

        token.mint(client, agreementAmount);

        vm.prank(client);
        token.approve(address(arbitrator), agreementAmount);

        vm.prank(serviceProvider);
        arbitrator.agreeTo(
            1,
            serviceProvider,
            client,
            "https://example.com",
            TERM_LENGTH,
            address(token),
            agreementAmount,
            TerminationClauses(0, 0, false, false, false, false, false)
        );

        vm.prank(client);
        arbitrator.agreeTo(
            1,
            serviceProvider,
            client,
            "https://example.com",
            TERM_LENGTH,
            address(token),
            agreementAmount,
            TerminationClauses(0, 0, false, false, false, false, false)
        );

        uint256 leftOvertokens = agreementAmount % TERM_LENGTH;

        (
            address sender,
            address recipient,
            uint256 deposit,
            address tokenAddress,
            uint256 startTime,
            uint256 stopTime,
            ,
        ) = sablier.getStream(100000);

        // assertEq(sender, address(arbitrator), "sender");
        assertEq(recipient, serviceProvider, "recipient");
        assertEq(deposit, agreementAmount - leftOvertokens, "agreementAmount");
        assertEq(startTime, block.timestamp, "startTime");
        assertEq(stopTime, block.timestamp + TERM_LENGTH, "stopTime");
        assertEq(tokenAddress, address(token));
        assertEq(token.balanceOf(address(serviceProvider)), leftOvertokens, "initial deposit");

        vm.warp(block.timestamp + TERM_LENGTH);
        vm.prank(serviceProvider);
        sablier.withdrawFromStream(100000, agreementAmount - leftOvertokens);
        assertEq(token.balanceOf(address(serviceProvider)), agreementAmount, "final deposit");
    }

    function test_cannotInitiateStreamForCounterParty() public {}

    function test_cannotCancelStreamUnlessContractOrProvider() public {}
}
