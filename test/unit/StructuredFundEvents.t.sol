// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {StructuredFundBase} from "../Base.t.sol";
import {IStructuredFundCashflows} from "../../src/interfaces/IStructuredFundCashflows.sol";
import {StructuredFundVault} from "../../src/StructuredFundVault.sol";

contract StructuredFundEventsTest is StructuredFundBase {
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    function test_ControllerDepositOverloadUsesControllerFundingAndEvent() public {
        vm.prank(alice);
        vault.setOperator(bob, true);
        uint256 beforeBalance = asset.balanceOf(alice);
        vm.expectEmit(true, true, false, true, address(vault));
        emit Deposit(alice, carol, UNIT, 1e18);
        vm.prank(bob);
        assertEq(vault.deposit(UNIT, carol, alice), 1e18);
        assertEq(asset.balanceOf(alice), beforeBalance - UNIT);
        assertEq(vault.principalOf(carol), UNIT);
    }

    function test_ControllerMintOverloadIsExactAndSynchronous() public {
        vm.prank(alice);
        vault.setOperator(bob, true);
        vm.prank(bob);
        assertEq(vault.mint(1, carol, alice), 1);
        assertEq(vault.balanceOf(carol), 1);
        assertEq(vault.principalOf(carol), 1);
    }
    event RedeemRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address sender, uint256 shares
    );
    event OperatorSet(address indexed controller, address indexed operator, bool approved);
    event CashflowRecorded(
        bytes32 indexed id,
        bytes32 indexed scopeId,
        address indexed beneficiary,
        uint256 principal,
        uint256 grossYield,
        uint256 withheld,
        uint64 periodStart,
        uint64 periodEnd,
        bytes32 evidenceHash
    );
    event CashflowClaimed(bytes32 indexed id, address indexed beneficiary, address indexed receiver, uint256 netAssets);
    event PrincipalRetired(address indexed controller, uint256 principal, uint256 shares);

    function test_OperatorAndRequestEventFields() public {
        _deposit(alice, UNIT);
        vm.expectEmit(true, true, false, true, address(vault));
        emit OperatorSet(alice, bob, true);
        vm.prank(alice);
        vault.setOperator(bob, true);
        vm.expectEmit(true, true, true, true, address(vault));
        emit RedeemRequest(alice, alice, 0, bob, 1e18);
        vm.prank(bob);
        vault.requestRedeem(1e18, alice, alice);
        assertEq(vault.lockedPrincipalOf(alice), UNIT);
    }

    function test_CashflowEventsUseNativeUnitsAndImmutableScope() public {
        _deposit(alice, 100 * UNIT);
        vault.deployCredit(100 * UNIT);
        IStructuredFundCashflows.Cashflow memory p = _payment(alice, 20 * UNIT, 5 * UNIT, UNIT);
        bytes32 id = keccak256("cashflow");
        bytes32 scope = vault.scopeId();
        vm.expectEmit(true, true, true, true, address(vault));
        emit CashflowRecorded(
            id, scope, alice, p.principal, p.grossYield, p.withheld, p.periodStart, p.periodEnd, p.evidenceHash
        );
        vault.recordCashflow(id, p, p.principal);
        vm.expectEmit(true, true, true, true, address(vault));
        emit CashflowClaimed(id, alice, bob, 24 * UNIT);
        vm.prank(alice);
        vault.claimCashflow(id, bob);
    }

    function test_PrincipalRetirementIsExplicitAtSettlement() public {
        _deposit(alice, UNIT);
        _request(alice, alice, 1e18);
        vm.expectEmit(true, false, false, true, address(vault));
        emit PrincipalRetired(alice, UNIT, 1e18);
        vault.fulfillRedeem(alice);
        assertEq(vault.lockedPrincipalOf(alice), 0);
    }

    function test_ClassAndSeriesPricesRemainIndependent() public {
        StructuredFundVault mezz = new StructuredFundVault(
            asset,
            policy,
            keccak256("FIDC:SERIES-A:MEZZ"),
            address(this),
            treasury,
            tax,
            1_000_000 * UNIT,
            "Structured Fund Cashflows Reference USD Mezz",
            "sfcUSD-M"
        );
        _deposit(alice, 100 * UNIT);
        vault.deployCredit(100 * UNIT);
        vm.startPrank(alice);
        asset.approve(address(mezz), type(uint256).max);
        mezz.deposit(100 * UNIT, alice);
        vm.stopPrank();
        vault.reportCreditNAV(120 * UNIT, 1, keccak256("senior valuation"));
        uint256 expectedSenior = vault.previewDeposit(10 * UNIT);
        uint256 expectedMezz = mezz.previewDeposit(10 * UNIT);
        assertLt(expectedSenior, expectedMezz);
        vm.startPrank(bob);
        asset.approve(address(mezz), type(uint256).max);
        assertEq(vault.deposit(10 * UNIT, bob), expectedSenior);
        assertEq(mezz.deposit(10 * UNIT, bob), expectedMezz);
        vm.stopPrank();
    }
}
