// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {StructuredFundBase} from "../Base.t.sol";
import {StructuredFundVault} from "../../src/StructuredFundVault.sol";
import {IStructuredFundCashflows} from "../../src/interfaces/IStructuredFundCashflows.sol";

contract StructuredFundCompositionTest is StructuredFundBase {
    function _batch()
        internal
        view
        returns (bytes32[] memory ids, IStructuredFundCashflows.Cashflow[] memory payments, uint256[] memory releases)
    {
        ids = new bytes32[](2);
        payments = new IStructuredFundCashflows.Cashflow[](2);
        releases = new uint256[](2);
        ids[0] = keccak256("alice distribution");
        ids[1] = keccak256("bob distribution");
        payments[0] = _payment(alice, 20 * UNIT, 5 * UNIT, UNIT);
        payments[1] = _payment(bob, 20 * UNIT, 5 * UNIT, UNIT);
        releases[0] = 25 * UNIT;
        releases[1] = 25 * UNIT;
    }

    function _fundBoth() internal {
        _deposit(alice, 100 * UNIT);
        _deposit(bob, 100 * UNIT);
        vault.deployCredit(200 * UNIT);
        vault.reportCreditNAV(210 * UNIT, 1, keccak256("recognized yield"));
    }

    function test_ShareToVaultDiscoveryIncludesERC165ShareInterface() public view {
        assertEq(vault.vault(address(asset)), address(vault));
        assertEq(vault.vault(address(0)), address(0));
        assertEq(vault.vault(outsider), address(0));
        assertTrue(vault.supportsInterface(0xf815c03d));
    }

    function test_ERC165DiscoveryFitsThirtyThousandGas() public view {
        bytes4[7] memory supported = [
            bytes4(0x01ffc9a7),
            bytes4(0xf815c03d),
            bytes4(0x2f0a18c5),
            bytes4(0xe3bc4e65),
            bytes4(0x620ee8e4),
            bytes4(0xe76cffc7),
            type(IStructuredFundCashflows).interfaceId
        ];
        for (uint256 i; i < supported.length; ++i) {
            (bool ok, bytes memory result) =
                address(vault).staticcall{gas: 30_000}(abi.encodeCall(vault.supportsInterface, (supported[i])));
            assertTrue(ok);
            assertTrue(abi.decode(result, (bool)));
        }
        assertFalse(vault.supportsInterface(0xffffffff));
    }

    function test_BatchBooksBothHoldersAndReservesAtomically() public {
        _fundBoth();
        (bytes32[] memory ids, IStructuredFundCashflows.Cashflow[] memory payments, uint256[] memory releases) =
            _batch();
        vault.recordCashflowBatch(ids, payments, releases);
        assertEq(vault.totalAssets(), 160 * UNIT);
        assertEq(vault.principalOf(alice), 80 * UNIT);
        assertEq(vault.principalOf(bob), 80 * UNIT);
        assertEq(vault.reservedCashflows(), 48 * UNIT);
        assertEq(asset.balanceOf(tax), 2 * UNIT);
        vm.prank(alice);
        assertEq(vault.claimCashflow(ids[0], alice), 24 * UNIT);
        vm.prank(bob);
        assertEq(vault.claimCashflow(ids[1], bob), 24 * UNIT);
        assertEq(vault.reservedCashflows(), 0);
    }

    function test_BatchLaterInvalidRecordRollsBackEarlierRecordAndTax() public {
        _fundBoth();
        (bytes32[] memory ids, IStructuredFundCashflows.Cashflow[] memory payments, uint256[] memory releases) =
            _batch();
        ids[1] = ids[0];
        uint256 senderBefore = asset.balanceOf(address(this));
        vm.expectRevert(StructuredFundVault.InvalidCashflow.selector);
        vault.recordCashflowBatch(ids, payments, releases);
        assertEq(vault.cashflow(ids[0]).beneficiary, address(0));
        assertEq(vault.totalAssets(), 210 * UNIT);
        assertEq(vault.totalOutstandingPrincipal(), 200 * UNIT);
        assertEq(vault.lastCashflowPeriodEnd(alice), 0);
        assertEq(vault.reservedCashflows(), 0);
        assertEq(asset.balanceOf(tax), 0);
        assertEq(asset.balanceOf(address(this)), senderBefore);
    }

    function test_BatchInsufficientFundingRevertsWholeDistribution() public {
        _fundBoth();
        (bytes32[] memory ids, IStructuredFundCashflows.Cashflow[] memory payments, uint256[] memory releases) =
            _batch();
        asset.transfer(outsider, asset.balanceOf(address(this)) - 25 * UNIT);
        vm.expectRevert();
        vault.recordCashflowBatch(ids, payments, releases);
        assertEq(vault.totalAssets(), 210 * UNIT);
        assertEq(vault.totalOutstandingPrincipal(), 200 * UNIT);
        assertEq(vault.reservedCashflows(), 0);
        assertEq(asset.balanceOf(tax), 0);
        assertEq(vault.cashflow(ids[0]).beneficiary, address(0));
        assertEq(asset.balanceOf(address(this)), 25 * UNIT);
    }

    function test_BatchRejectsEmptyOversizedAndMismatchedLists() public {
        bytes32[] memory ids = new bytes32[](0);
        IStructuredFundCashflows.Cashflow[] memory payments = new IStructuredFundCashflows.Cashflow[](0);
        uint256[] memory releases = new uint256[](0);
        vm.expectRevert(StructuredFundVault.InvalidCashflowBatch.selector);
        vault.recordCashflowBatch(ids, payments, releases);
        ids = new bytes32[](65);
        vm.expectRevert(StructuredFundVault.InvalidCashflowBatch.selector);
        vault.recordCashflowBatch(ids, payments, releases);
        ids = new bytes32[](1);
        vm.expectRevert(StructuredFundVault.InvalidCashflowBatch.selector);
        vault.recordCashflowBatch(ids, payments, releases);
        payments = new IStructuredFundCashflows.Cashflow[](1);
        vm.expectRevert(StructuredFundVault.InvalidCashflowBatch.selector);
        vault.recordCashflowBatch(ids, payments, releases);
    }

    function test_BatchRequiresSettlerAndUnpausedVault() public {
        (bytes32[] memory ids, IStructuredFundCashflows.Cashflow[] memory payments, uint256[] memory releases) =
            _batch();
        vm.prank(outsider);
        vm.expectRevert();
        vault.recordCashflowBatch(ids, payments, releases);
        vault.pause();
        vm.expectRevert();
        vault.recordCashflowBatch(ids, payments, releases);
    }

    function test_BatchCallbackCannotReenterPrivilegedValuation() public {
        _fundBoth();
        (bytes32[] memory ids, IStructuredFundCashflows.Cashflow[] memory payments, uint256[] memory releases) =
            _batch();
        vault.grantRole(vault.VALUER_ROLE(), address(asset));
        asset.setCallback(
            address(vault), abi.encodeCall(vault.reportCreditNAV, (999 * UNIT, 2, keccak256("callback"))), false
        );
        vault.recordCashflowBatch(ids, payments, releases);
        assertFalse(asset.callbackSucceeded());
        assertEq(vault.totalAssets(), 160 * UNIT);
        assertEq(vault.navNonce(), 1);
    }

    function test_MaximumBatchDoesNotRequireGlobalHolderEnumeration() public {
        uint256 count = vault.MAX_CASHFLOW_BATCH();
        bytes32[] memory ids = new bytes32[](count);
        IStructuredFundCashflows.Cashflow[] memory payments = new IStructuredFundCashflows.Cashflow[](count);
        uint256[] memory releases = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            ids[i] = bytes32(i + 1);
            payments[i] = _payment(alice, 0, UNIT, 0);
            payments[i].periodStart = uint64(block.timestamp - count + i);
            payments[i].periodEnd = payments[i].periodStart + 1;
        }
        vault.recordCashflowBatch(ids, payments, releases);
        assertEq(vault.reservedCashflows(), count * UNIT);
        assertEq(asset.balanceOf(address(vault)), count * UNIT);
        assertEq(vault.cashflow(ids[count - 1]).grossYield, UNIT);
    }

    function testFuzz_BatchConservesGrossNetPrincipalAndNAV(uint96 pSeed, uint96 ySeed, uint96 taxSeed) public {
        _deposit(alice, 100 * UNIT);
        _deposit(bob, 100 * UNIT);
        vault.deployCredit(200 * UNIT);
        uint256 p = bound(pSeed, 0, 100 * UNIT);
        uint256 y = bound(ySeed, 1, 50 * UNIT);
        uint256 w = bound(taxSeed, 0, y);
        vault.reportCreditNAV(200 * UNIT + 2 * y, 1, keccak256("batch yield"));
        (bytes32[] memory ids, IStructuredFundCashflows.Cashflow[] memory payments, uint256[] memory releases) =
            _batch();
        payments[0] = _payment(alice, p, y, w);
        payments[1] = _payment(bob, p, y, w);
        releases[0] = p + y;
        releases[1] = p + y;
        vault.recordCashflowBatch(ids, payments, releases);
        assertEq(vault.totalAssets(), 200 * UNIT - 2 * p);
        assertEq(vault.totalOutstandingPrincipal(), 200 * UNIT - 2 * p);
        assertEq(vault.reservedCashflows(), 2 * (p + y - w));
        assertEq(asset.balanceOf(tax), 2 * w);
        assertEq(asset.balanceOf(address(vault)) + asset.balanceOf(tax), 2 * (p + y));
    }
}
