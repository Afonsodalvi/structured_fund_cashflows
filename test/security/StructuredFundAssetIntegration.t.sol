// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {StructuredFundBase} from "../Base.t.sol";
import {MockAsset} from "../mocks/MockAsset.sol";
import {StructuredFundVault} from "../../src/StructuredFundVault.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ReturnBehaviorAsset is MockAsset {
    uint8 public mode;
    error AssetRejected();
    constructor() MockAsset(6) {}

    function setMode(uint8 value) external {
        mode = value;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        super.transfer(to, amount);
        return _respond();
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        super.transferFrom(from, to, amount);
        return _respond();
    }

    function _respond() private view returns (bool) {
        if (mode == 1) return false;
        if (mode == 2) {
            assembly ("memory-safe") { return(0, 0) }
        }
        if (mode == 3) {
            assembly ("memory-safe") {
                mstore(0, 1)
                return(31, 1)
            }
        }
        if (mode == 4) revert AssetRejected();
        return true;
    }
}

contract StructuredFundAssetIntegrationTest is StructuredFundBase {
    ReturnBehaviorAsset internal unusual;

    function setUp() public override {
        super.setUp();
        unusual = new ReturnBehaviorAsset();
        asset = unusual;
        vault = new StructuredFundVault(
            asset, policy, keccak256("return behavior"), address(this), treasury, tax, 1000 * UNIT, "Returns", "RET"
        );
        unusual.mint(alice, 100 * UNIT);
        unusual.mint(address(this), 100 * UNIT);
        vm.prank(alice);
        unusual.approve(address(vault), type(uint256).max);
        unusual.approve(address(vault), type(uint256).max);
    }

    function test_NoReturnTokenPreservesExactFundingAndCashflowClaims() public {
        unusual.setMode(2);
        _deposit(alice, 100 * UNIT);
        vault.deployCredit(100 * UNIT);
        bytes32 id = keccak256("distribution");
        vault.recordCashflow(id, _payment(alice, 20 * UNIT, 5 * UNIT, UNIT), 20 * UNIT);
        assertEq(unusual.balanceOf(tax), UNIT);
        assertEq(vault.principalOf(alice), 80 * UNIT);
        vm.prank(alice);
        assertEq(vault.claimCashflow(id, alice), 24 * UNIT);
        assertEq(unusual.balanceOf(alice), 24 * UNIT);
        assertEq(vault.reservedCashflows(), 0);
        vault.repayCredit(75 * UNIT);
        assertEq(vault.managedCash(), 75 * UNIT);
        assertEq(vault.totalAssets(), 80 * UNIT);
    }

    function _rejectDeposit(uint8 mode) private {
        unusual.setMode(mode);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(unusual)));
        vault.deposit(UNIT, alice);
        assertEq(unusual.balanceOf(alice), 100 * UNIT);
        assertEq(unusual.balanceOf(address(vault)), 0);
        assertEq(vault.totalOutstandingPrincipal(), 0);
        assertEq(vault.totalSupply(), 0);
        unusual.setMode(0);
        _deposit(alice, UNIT);
        assertEq(vault.principalOf(alice), UNIT);
    }

    function test_FalseReturnAfterTransferRevertsEntireDepositAndUnlocks() public {
        _rejectDeposit(1);
    }

    function test_MalformedReturnAfterTransferRevertsEntireDepositAndUnlocks() public {
        _rejectDeposit(3);
    }

    function test_FalseReturnPayoutPreservesClaimAndReservesUntilRetry() public {
        bytes32 id = keccak256("claim");
        vault.recordCashflow(id, _payment(alice, 0, UNIT, 0), 0);
        unusual.setMode(1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(unusual)));
        vault.claimCashflow(id, alice);
        assertFalse(vault.cashflow(id).claimed);
        assertEq(vault.reservedCashflows(), UNIT);
        assertEq(unusual.balanceOf(address(vault)), UNIT);
        unusual.setMode(0);
        vm.prank(alice);
        assertEq(vault.claimCashflow(id, alice), UNIT);
        assertTrue(vault.cashflow(id).claimed);
    }

    function test_AssetRevertIsPropagatedAndNextDepositWorks() public {
        unusual.setMode(4);
        vm.prank(alice);
        vm.expectRevert(ReturnBehaviorAsset.AssetRejected.selector);
        vault.deposit(UNIT, alice);
        assertEq(vault.totalAssets(), 0);
        unusual.setMode(0);
        _deposit(alice, UNIT);
        assertEq(vault.totalAssets(), UNIT);
    }
}
