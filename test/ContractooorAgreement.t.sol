// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {ERC20Mock} from "@openzeppelin/mocks/ERC20Mock.sol";
import {TerminationClauses, Agreement, TerminationReason} from "contracts/lib/Types.sol";
import {AgreementArbitrator} from "src/AgreementArbitrator.sol";
import {ContractooorAgreement, MAX_CURE_ALLOWANCE} from "src/ContractooorAgreement.sol";

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
        vm.label(client, "CLIENT");
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
        vm.label(sender, "AGREEMENT");

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

    function test_cannotDoubleInitialize() public {
        ContractooorAgreement agreement = ContractooorAgreement(_initiateAgreement());
        vm.expectRevert("Initializable: contract is already initialized");
        agreement.initialize(
            sablier,
            address(0),
            1 ether,
            10 days,
            Agreement({
                provider: serviceProvider,
                client: client,
                atWillDays: 0,
                cureTimeDays: 0,
                legalCompulsion: false,
                moralTurpitude: false,
                bankruptcyDissolutionInsolvency: false,
                counterpartyMalfeasance: false,
                lostControlOfPrivateKeys: false,
                contractURI: ""
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

    function test_bothPartiesCanTerminateByMutualConsent(address rando, bool clientInitiates) public {
        vm.assume(rando != serviceProvider && rando != client);

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

        // a non-party cannot terminate
        vm.prank(rando);
        vm.expectRevert(ContractooorAgreement.NOT_CLIENT_OR_SERVICE_PROVIDER.selector);
        agreement.terminateByMutualConsent("heh");

        address initiator = clientInitiates ? client : serviceProvider;
        address counterParty = clientInitiates ? serviceProvider : client;

        uint256 preCancellation = vm.snapshot();

        vm.prank(initiator);
        agreement.terminateByMutualConsent("SP broke the rules");

        // a non-party can still not trigger termination
        vm.prank(rando);
        vm.expectRevert(ContractooorAgreement.NOT_CLIENT_OR_SERVICE_PROVIDER.selector);
        agreement.terminateByMutualConsent("heh");

        // an alternate termination reason will still not cancel the agreement
        vm.prank(counterParty);
        agreement.terminateByMutualConsent("Actually client broke the rules");
        sablier.getStream(100000);

        vm.prank(initiator);
        agreement.terminateByMutualConsent("SP broke the rules dude");
        sablier.getStream(100000);

        // the agreement is now terminated
        vm.prank(counterParty);
        agreement.terminateByMutualConsent("SP broke the rules dude");
        vm.expectRevert();
        sablier.getStream(100000);

        vm.revertTo(preCancellation);

        // either party cannot spam their own reason twice and cancel
        vm.startPrank(initiator);
        agreement.terminateByMutualConsent("SP broke the rules");
        agreement.terminateByMutualConsent("SP broke the rules");
        vm.stopPrank();
        sablier.getStream(100000);

        vm.startPrank(counterParty);
        agreement.terminateByMutualConsent("Client broke the rules");
        agreement.terminateByMutualConsent("Client broke the rules");
        vm.stopPrank();
        sablier.getStream(100000);
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

    function test_oppositePartyCannotTerminateAtWill() public {
        uint8 daysToWait = 3;
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

        uint256 snapshot = vm.snapshot();

        // sp-based flow
        vm.prank(serviceProvider);
        agreement.issueNoticeOfTermination("goodbye");

        // neither the client or SP can terminate at this point
        vm.expectRevert();
        vm.prank(serviceProvider);
        agreement.terminateAtWill();

        vm.expectRevert();
        vm.prank(client);
        agreement.terminateAtWill();

        vm.warp(block.timestamp + (daysToWait * 1 days));

        // client cannot terminate
        vm.expectRevert();
        vm.prank(client);
        agreement.terminateAtWill();

        // the serviceProvider can now terminate
        vm.prank(serviceProvider);
        agreement.terminateAtWill();

        // have both parties initiate
        vm.revertTo(snapshot);

        vm.prank(serviceProvider);
        agreement.issueNoticeOfTermination("goodbye");
        vm.prank(client);
        agreement.issueNoticeOfTermination("me too");

        // neither the client or SP can terminate at this point
        vm.expectRevert();
        vm.prank(serviceProvider);
        agreement.terminateAtWill();

        vm.expectRevert();
        vm.prank(client);
        agreement.terminateAtWill();

        vm.warp(block.timestamp + (daysToWait * 1 days));

        uint256 preRevertSnapshot = vm.snapshot();

        vm.prank(client);
        agreement.terminateAtWill();

        // now try from the client
        vm.revertTo(preRevertSnapshot);
        vm.prank(client);
        agreement.terminateAtWill();

        // cannot cancel an already cancelled agreement
        vm.prank(serviceProvider);
        vm.expectRevert();
        agreement.terminateAtWill();
    }

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

        vm.prank(party);
        vm.expectRevert(ContractooorAgreement.CURE_TIME_NOT_MET.selector);
        agreement.terminateAtWill();
    }

    function test_materialBreach(address rando, bool clientInitiates) public {
        vm.assume(rando != serviceProvider && rando != client);

        uint8 cureTimeDays = 1;
        ContractooorAgreement agreement = ContractooorAgreement(
            _initiateAgreement(
                1 ether,
                TerminationClauses({
                    atWillDays: 0,
                    cureTimeDays: cureTimeDays,
                    legalCompulsion: false,
                    moralTurpitude: false,
                    bankruptcyDissolutionInsolvency: false,
                    counterpartyMalfeasance: false,
                    lostControlOfPrivateKeys: false
                })
            )
        );

        // non-party cannot terminate
        vm.prank(rando);
        vm.expectRevert(ContractooorAgreement.NOT_CLIENT_OR_SERVICE_PROVIDER.selector);
        agreement.issueNoticeOfMaterialBreach("heh");

        address initiator = clientInitiates ? client : serviceProvider;
        address counterParty = clientInitiates ? serviceProvider : client;

        uint256 startSnapshot = vm.snapshot();

        vm.prank(initiator);
        agreement.issueNoticeOfMaterialBreach("u stink");

        assertTrue(agreement.materialBreachTimestamp(initiator) > 0, "timestamp not set");

        uint256 preWithdrawalId = vm.snapshot();
        vm.prank(initiator);
        agreement.withdrawNoticeOfMaterialBreach("u good");
        assertTrue(agreement.materialBreachTimestamp(initiator) == 0, "timestamp not deleted");

        vm.revertTo(preWithdrawalId);

        // a rando cannot remove the initiator's material breach ts
        vm.prank(rando);
        vm.expectRevert(ContractooorAgreement.NOT_CLIENT_OR_SERVICE_PROVIDER.selector);
        agreement.withdrawNoticeOfMaterialBreach("u good");
        assertTrue(agreement.materialBreachTimestamp(initiator) > 0, "timestamp deleted!");

        uint256 preCureSnapshot = vm.snapshot();

        vm.prank(counterParty);
        agreement.issueNoticeOfCure("cured it");
        assertTrue(agreement.materialBreachTimestamp(initiator) == 0, "not cured");
        assertTrue(agreement.timesContractCured() == 1, "breach protection not incremented");
        // cannot cure if not breached
        vm.prank(counterParty);
        vm.expectRevert(ContractooorAgreement.NO_BREACH_NOTICE_ISSUED.selector);
        agreement.issueNoticeOfCure("cured it");

        vm.revertTo(preCureSnapshot);

        // cannot termninate early
        vm.prank(initiator);
        vm.expectRevert(ContractooorAgreement.CURE_TIME_NOT_MET.selector);
        agreement.terminateByMaterialBreach();

        // can terminate after cure time
        vm.warp(block.timestamp + (cureTimeDays * 1 days) + 1);

        vm.prank(initiator);
        agreement.terminateByMaterialBreach();
        vm.expectRevert();
        sablier.getStream(100000);

        vm.revertTo(startSnapshot);

        // cannot have the counterparty cure endlessly
        for (uint256 i; i < MAX_CURE_ALLOWANCE; i++) {
            vm.prank(initiator);
            agreement.issueNoticeOfMaterialBreach("u stink");

            vm.prank(counterParty);
            agreement.issueNoticeOfCure("cured it");
        }
        assertEq(agreement.timesContractCured(), MAX_CURE_ALLOWANCE, "breach protection not incremented");

        vm.prank(initiator);
        agreement.issueNoticeOfMaterialBreach("u stink fr");
        uint256 materialBreachTimestamp = agreement.materialBreachTimestamp(initiator);

        // validate that the current time is in fact below the required cure time, and the initiator can bail out anyways
        assertTrue(block.timestamp < materialBreachTimestamp + (cureTimeDays * 1 days));

        vm.prank(counterParty);
        agreement.terminateByMaterialBreach();
        vm.expectRevert();
        sablier.getStream(100000);
    }

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

    function test_usersGetFundsBackIfStreamCancelled() public {
        ContractooorAgreement agreement = ContractooorAgreement(
            _initiateAgreement(
                1 ether,
                TerminationClauses({
                    atWillDays: 0,
                    cureTimeDays: 0,
                    legalCompulsion: true,
                    moralTurpitude: false,
                    bankruptcyDissolutionInsolvency: false,
                    counterpartyMalfeasance: false,
                    lostControlOfPrivateKeys: false
                })
            )
        );
        uint256 streamAmount = 999999999997920000;

        vm.prank(serviceProvider);
        sablier.cancelStream(100_000);

        assertEq(streamAmount, token.balanceOf(address(agreement)));

        agreement.emergencyRecoverTokens(address(token));
        assertEq(streamAmount, token.balanceOf(address(client)));
    }
}
