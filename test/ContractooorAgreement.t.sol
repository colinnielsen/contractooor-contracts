// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {ERC20Mock} from "@openzeppelin/mocks/ERC20Mock.sol";
import {TerminationClauses, Agreement, TerminationReason} from "contracts/lib/Types.sol";
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

    function _initiateAgreement(uint256 agreementAmount, TerminationClauses memory terminationClauses)
        internal
        returns (address agreement)
    {
        uint32 TERM_LENGTH = 30 days;
        assert(agreementAmount > TERM_LENGTH && agreementAmount < type(uint128).max);

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
            terminationClauses
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
            terminationClauses
        );
        (address sender,,,,,,,) = sablier.getStream(100000);
        return sender;
    }

    function _initiateAgreement() internal returns (address) {
        return _initiateAgreement(
            1 ether,
            TerminationClauses({
                atWillDays: 0,
                cureTimeDays: 0,
                legalCompulsion: false,
                moralTurpitude: false,
                bankruptcyDissolutionInsolvency: false,
                counterpartyMalfeasance: false,
                lostControlOfPrivateKeys: false
            })
        );
    }

    function test_terminateByMutualConsent() public {
        ContractooorAgreement agreement = ContractooorAgreement(_initiateAgreement());

        vm.prank(serviceProvider);
        agreement.terminateByMutualConsent("l8r");

        vm.prank(client);
        agreement.terminateByMutualConsent("l8r");

        // stream does not exist
        vm.expectRevert();
        sablier.getStream(100000);
    }

    function test_nonPartiesCannotTerminateMutualConsent(address party) public {
        vm.assume(party != serviceProvider && party != client);

        ContractooorAgreement agreement = ContractooorAgreement(_initiateAgreement());

        vm.prank(party);

        vm.expectRevert(ContractooorAgreement.NOT_CLIENT_OR_SERVICE_PROVIDER.selector);
        agreement.terminateByMutualConsent("l8r");

        vm.expectRevert(ContractooorAgreement.NOT_CLIENT_OR_SERVICE_PROVIDER.selector);
        agreement.issueNoticeOfTermination("l8r");
    }

    function test_atWillTerminate(uint8 daysToWait, bool useClient) public {
        address party = useClient ? client : serviceProvider;
        uint256 timestamp = 1674941221;
        vm.warp(timestamp);

        ContractooorAgreement agreement = ContractooorAgreement(
            _initiateAgreement(
                1 ether,
                TerminationClauses({
                    atWillDays: daysToWait,
                    cureTimeDays: 0,
                    legalCompulsion: false,
                    moralTurpitude: false,
                    bankruptcyDissolutionInsolvency: false,
                    counterpartyMalfeasance: false,
                    lostControlOfPrivateKeys: false
                })
            )
        );

        vm.prank(party);
        agreement.issueNoticeOfTermination("l8r");

        vm.warp(timestamp + ((uint256(daysToWait) + 1) * 1 days));

        vm.prank(party);
        agreement.terminateAtWill();

        // stream does not exist
        vm.expectRevert();
        sablier.getStream(100000);
    }

    function test_bothPartiesCanTerminateAtWill() public {}

    function test_nonPartiesCannotTerminateAtWill(address party) public {
        vm.assume(party != serviceProvider && party != client);

        ContractooorAgreement agreement = ContractooorAgreement(
            _initiateAgreement(
                1 ether,
                TerminationClauses({
                    atWillDays: 1,
                    cureTimeDays: 0,
                    legalCompulsion: false,
                    moralTurpitude: false,
                    bankruptcyDissolutionInsolvency: false,
                    counterpartyMalfeasance: false,
                    lostControlOfPrivateKeys: false
                })
            )
        );

        vm.prank(party);
        vm.expectRevert(ContractooorAgreement.NOT_CLIENT_OR_SERVICE_PROVIDER.selector);
        agreement.issueNoticeOfTermination("l8r");

        vm.prank(client);
        agreement.issueNoticeOfTermination("l8r");
        vm.warp(10 days);

        vm.expectRevert(ContractooorAgreement.CURE_TIME_NOT_MET.selector);
        vm.prank(party);
        agreement.terminateAtWill();
    }

    function test_bothPartiesCanTerminateByMutualConsent() public {}

    function test_materialBreach() public {}

    function test_noPartiesCannotTerminateByMaterialBreach() public {}

    function test_bothPartiesCanTerminateByMaterialBreach() public {}

    function test_rageTerminate(uint8 _reason, bool useClient) public {
        address party = useClient ? client : serviceProvider;
        TerminationReason reason = TerminationReason(_reason % 10);

        ContractooorAgreement agreement = ContractooorAgreement(
            _initiateAgreement(
                1 ether,
                TerminationClauses({
                    atWillDays: 0,
                    cureTimeDays: 0,
                    legalCompulsion: true,
                    moralTurpitude: true,
                    bankruptcyDissolutionInsolvency: true,
                    counterpartyMalfeasance: true,
                    lostControlOfPrivateKeys: true
                })
            )
        );

        vm.prank(party);
        if (uint256(reason) < 3) {
            vm.expectRevert(ContractooorAgreement.RAGE_TERMINATION_NOT_ALLOWED.selector);
        }
        agreement.rageTerminate(reason, "bye");
    }

    function test_cannotRageTerminateAsOtherParty(uint8 _reason, address party) public {
        vm.assume(party != serviceProvider && party != client);
        TerminationReason reason = TerminationReason(_reason % 7);

        ContractooorAgreement agreement = ContractooorAgreement(
            _initiateAgreement(
                1 ether,
                TerminationClauses({
                    atWillDays: 0,
                    cureTimeDays: 0,
                    legalCompulsion: true,
                    moralTurpitude: true,
                    bankruptcyDissolutionInsolvency: true,
                    counterpartyMalfeasance: true,
                    lostControlOfPrivateKeys: true
                })
            )
        );

        vm.prank(party);
        vm.expectRevert(ContractooorAgreement.NOT_CLIENT_OR_SERVICE_PROVIDER.selector);
        agreement.rageTerminate(reason, "bye");
    }

    function test_cannotRageTerminateDisallowedValues(
        bool legalCompulsion,
        bool moralTurpitude,
        bool bankruptcyDissolutionInsolvency,
        bool counterpartyMalfeasance,
        bool lostControlOfPrivateKeys
    ) public {
        ContractooorAgreement agreement = ContractooorAgreement(
            _initiateAgreement(
                1 ether,
                TerminationClauses({
                    atWillDays: 0,
                    cureTimeDays: 0,
                    legalCompulsion: legalCompulsion,
                    moralTurpitude: moralTurpitude,
                    bankruptcyDissolutionInsolvency: bankruptcyDissolutionInsolvency,
                    counterpartyMalfeasance: counterpartyMalfeasance,
                    lostControlOfPrivateKeys: lostControlOfPrivateKeys
                })
            )
        );

        bytes4 revertMsg = ContractooorAgreement.RAGE_TERMINATION_NOT_ALLOWED.selector;

        vm.startPrank(client);

        if (!legalCompulsion) {
            vm.expectRevert(revertMsg);
            agreement.rageTerminate(TerminationReason.LegalCompulsion, "bye");
        } else {
            agreement.rageTerminate(TerminationReason.LegalCompulsion, "bye");
            return;
        }

        if (!moralTurpitude) {
            vm.expectRevert(revertMsg);
            agreement.rageTerminate(TerminationReason.CrimesOfMoralTurpitude, "bye");
        } else {
            agreement.rageTerminate(TerminationReason.CrimesOfMoralTurpitude, "bye");
            return;
        }
        if (!bankruptcyDissolutionInsolvency) {
            vm.expectRevert(revertMsg);
            agreement.rageTerminate(TerminationReason.Bankruptcy, "bye");
        } else {
            agreement.rageTerminate(TerminationReason.Bankruptcy, "bye");
            return;
        }
        if (!bankruptcyDissolutionInsolvency) {
            vm.expectRevert(revertMsg);
            agreement.rageTerminate(TerminationReason.Dissolution, "bye");
        } else {
            agreement.rageTerminate(TerminationReason.Dissolution, "bye");
            return;
        }
        if (!bankruptcyDissolutionInsolvency) {
            vm.expectRevert(revertMsg);
            agreement.rageTerminate(TerminationReason.Insolvency, "bye");
        } else {
            agreement.rageTerminate(TerminationReason.Insolvency, "bye");
            return;
        }
        if (!counterpartyMalfeasance) {
            vm.expectRevert(revertMsg);
            agreement.rageTerminate(TerminationReason.CounterPartyMalfeasance, "bye");
        } else {
            agreement.rageTerminate(TerminationReason.CounterPartyMalfeasance, "bye");
            return;
        }
        if (!lostControlOfPrivateKeys) {
            vm.expectRevert(revertMsg);
            agreement.rageTerminate(TerminationReason.LossControlOfPrivateKeys, "bye");
        } else {
            agreement.rageTerminate(TerminationReason.LossControlOfPrivateKeys, "bye");
            return;
        }
    }

    function test_usersGetFundsBackIfStreamCancelled() public {}
}
