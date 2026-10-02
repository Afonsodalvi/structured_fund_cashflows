// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {StructuredFundBase} from "../Base.t.sol";
import {StructuredFundVault} from "../../src/StructuredFundVault.sol";
import {IStructuredFundCashflows} from "../../src/interfaces/IStructuredFundCashflows.sol";
import {StructuredFundEligibility} from "../../src/StructuredFundEligibility.sol";
import {MockAsset} from "../mocks/MockAsset.sol";

contract StructuredFundVaultTest is StructuredFundBase {
    function test_EscrowAndZeroAddressCannotBeDepositReceivers() public view {
        assertEq(vault.maxDeposit(address(0)), 0);
        assertEq(vault.maxMint(address(0)), 0);
        assertEq(vault.maxDeposit(address(vault)), 0);
        assertEq(vault.maxMint(address(vault)), 0);
    }

    function test_CashflowReleasesPreviouslyAccruedYieldFromNAV() public {
        _deposit(alice, 100 * UNIT);
        vault.deployCredit(100 * UNIT);
        vault.reportCreditNAV(105 * UNIT, 1, keccak256("accrued yield"));
        vault.recordCashflow(keccak256("accrued payment"), _payment(alice, 20 * UNIT, 5 * UNIT, UNIT), 25 * UNIT);
        assertEq(vault.totalAssets(), 80 * UNIT);
        assertEq(vault.principalOf(alice), 80 * UNIT);
        assertEq(vault.reservedCashflows(), 24 * UNIT);
    }

    function test_CashflowCanReleasePartiallyRecognizedYield() public {
        _deposit(alice, 100 * UNIT);
        vault.deployCredit(100 * UNIT);
        vault.reportCreditNAV(102 * UNIT, 1, keccak256("partial accrued yield"));
        vault.recordCashflow(keccak256("partial payment"), _payment(alice, 20 * UNIT, 5 * UNIT, UNIT), 22 * UNIT);
        assertEq(vault.totalAssets(), 80 * UNIT);
        assertEq(vault.reservedCashflows(), 24 * UNIT);
    }

    function test_MetadataAndInterfaces() public view {
        assertEq(vault.decimals(), 18);
        assertEq(vault.asset(), address(asset));
        assertEq(vault.share(), address(vault));
        assertTrue(vault.supportsInterface(0x01ffc9a7));
        assertTrue(vault.supportsInterface(0xe3bc4e65));
        assertTrue(vault.supportsInterface(0x2f0a18c5));
        assertTrue(vault.supportsInterface(0x620ee8e4));
        assertTrue(vault.supportsInterface(0xe76cffc7));
        assertTrue(vault.supportsInterface(type(IStructuredFundCashflows).interfaceId));
        assertFalse(vault.supportsInterface(0xffffffff));
        assertFalse(vault.supportsInterface(0xce3bbe50));
    }

    function test_DepositExactNativeUnits() public {
        assertEq(_deposit(alice, 100 * UNIT), 100e18);
        assertEq(vault.totalAssets(), 100 * UNIT);
        assertEq(vault.principalOf(alice), 100 * UNIT);
    }

    function test_MintOneShareWeiWithSixDecimals() public {
        uint256 beforeBalance = asset.balanceOf(alice);
        vm.prank(alice);
        assertEq(vault.mint(1, alice), 1);
        assertEq(vault.balanceOf(alice), 1);
        assertEq(beforeBalance - asset.balanceOf(alice), 1);
        assertEq(vault.totalOutstandingPrincipal(), 1);
    }

    function test_MintUsesCeilingAfterNAVChange() public {
        _deposit(alice, 100 * UNIT);
        vault.deployCredit(100 * UNIT);
        vault.reportCreditNAV(137 * UNIT, 1, keccak256("NAV"));
        uint256 shares = 7e18 + 3;
        uint256 preview = vault.previewMint(shares);
        vm.prank(bob);
        uint256 paid = vault.mint(shares, bob);
        assertEq(paid, preview);
        assertEq(vault.balanceOf(bob), shares);
        assertEq(vault.principalOf(bob), paid);
    }

    function test_TransferMovesPrincipalProportionally() public {
        _deposit(alice, 100 * UNIT);
        vm.prank(alice);
        vault.transfer(bob, 40e18);
        assertEq(vault.principalOf(alice), 60 * UNIT);
        assertEq(vault.principalOf(bob), 40 * UNIT);
        vm.prank(alice);
        vault.transfer(bob, 60e18);
        assertEq(vault.principalOf(alice), 0);
        assertEq(vault.principalOf(bob), 100 * UNIT);
        assertEq(vault.totalOutstandingPrincipal(), 100 * UNIT);
    }

    function test_SelfAndZeroTransfersPreservePrincipal() public {
        _deposit(alice, 1);
        vm.startPrank(alice);
        vault.transfer(alice, 1e12);
        vault.transfer(bob, 0);
        vm.stopPrank();
        assertEq(vault.principalOf(alice), 1);
        assertEq(vault.principalOf(bob), 0);
    }

    function test_FullAsyncClaimRetiresSupplyAndPrincipal() public {
        _deposit(alice, 100 * UNIT);
        _request(alice, alice, 100e18);
        assertEq(vault.totalSupply(), 100e18);
        assertEq(vault.totalEscrowedShares(), 100e18);
        assertEq(vault.totalOutstandingPrincipal(), 100 * UNIT);
        assertEq(vault.totalLockedPrincipal(), 100 * UNIT);
        vault.fulfillRedeem(alice);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalOutstandingPrincipal(), 0);
        assertEq(vault.claimableRedeemRequest(0, alice), 100e18);
        assertEq(vault.maxWithdraw(alice), 100 * UNIT);
        vm.prank(alice);
        assertEq(vault.redeem(100e18, alice, alice), 100 * UNIT);
        assertEq(vault.reservedRedemptions(), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
    }

    function test_PartialRedeemAndWithdrawExhaustRights() public {
        _deposit(alice, 100 * UNIT);
        _request(alice, alice, 100e18);
        vault.fulfillRedeem(alice);
        vm.prank(alice);
        assertEq(vault.redeem(25e18, bob, alice), 25 * UNIT);
        vm.prank(alice);
        assertEq(vault.withdraw(25 * UNIT, bob, alice), 25e18);
        vm.prank(alice);
        assertEq(vault.redeem(50e18, bob, alice), 50 * UNIT);
        assertEq(vault.maxRedeem(alice), 0);
        assertEq(vault.maxWithdraw(alice), 0);
    }

    function test_RequestAggregatesAtIdZeroAndViewsAreCallerIndependent() public {
        _deposit(alice, 100 * UNIT);
        _request(alice, alice, 10e18);
        _request(alice, alice, 15e18);
        assertEq(vault.pendingRedeemRequest(0, alice), 25e18);
        assertEq(vault.pendingRedeemRequest(1, alice), 0);
        vault.fulfillRedeem(alice);
        vm.prank(outsider);
        assertEq(vault.claimableRedeemRequest(0, alice), 25e18);
        assertEq(vault.claimableRedeemRequest(99, alice), 0);
    }

    function test_SeveralSettlementsAggregateClaimableRates() public {
        _deposit(alice, 100 * UNIT);
        vault.deployCredit(50 * UNIT);
        _request(alice, alice, 20e18);
        vault.fulfillRedeem(alice);
        vault.reportCreditNAV(60 * UNIT, 1, keccak256("NAV"));
        _request(alice, alice, 20e18);
        vault.fulfillRedeem(alice);
        uint256 owed = vault.maxWithdraw(alice);
        vm.prank(alice);
        assertEq(vault.redeem(40e18, alice, alice), owed);
        assertEq(vault.reservedRedemptions(), 0);
    }

    function test_AllowanceAuthorizesRequestAndIsConsumed() public {
        _deposit(alice, 100 * UNIT);
        vm.prank(alice);
        vault.approve(bob, 25e18);
        vm.prank(bob);
        vault.requestRedeem(25e18, bob, alice);
        assertEq(vault.allowance(alice, bob), 0);
        assertEq(vault.pendingRedeemRequest(0, bob), 25e18);
    }

    function test_InfiniteAllowanceNotConsumed() public {
        _deposit(alice, 100 * UNIT);
        vm.prank(alice);
        vault.approve(bob, type(uint256).max);
        vm.prank(bob);
        vault.requestRedeem(25e18, alice, alice);
        assertEq(vault.allowance(alice, bob), type(uint256).max);
    }

    function test_OperatorNeedsNoAllowanceAndCanClaim() public {
        _deposit(alice, 100 * UNIT);
        vm.prank(alice);
        assertTrue(vault.setOperator(bob, true));
        vm.prank(bob);
        vault.requestRedeem(100e18, alice, alice);
        vault.fulfillRedeem(alice);
        vm.prank(bob);
        vault.redeem(100e18, alice, alice);
        assertEq(vault.allowance(alice, bob), 0);
    }

    function test_CancellationPullReturnsOriginalPrincipalDespiteOtherDeposits() public {
        _deposit(alice, 100 * UNIT);
        _request(alice, alice, 40e18);
        _deposit(bob, 17 * UNIT);
        _request(bob, bob, 17e18);
        vm.prank(alice);
        vault.cancelRedeemRequest(0, alice);
        assertTrue(vault.pendingCancelRedeemRequest(0, alice));
        vault.fulfillCancel(alice);
        assertEq(vault.balanceOf(alice), 60e18);
        assertEq(vault.claimableCancelRedeemRequest(0, alice), 40e18);
        vm.prank(alice);
        vault.claimCancelRedeemRequest(0, carol, alice);
        assertEq(vault.principalOf(carol), 40 * UNIT);
        assertEq(vault.totalOutstandingPrincipal(), 117 * UNIT);
        assertEq(vault.totalEscrowedShares(), 17e18);
        assertEq(vault.totalLockedPrincipal(), 17 * UNIT);
    }

    function test_CashflowPrincipalYieldTaxAndPullClaim() public {
        _deposit(alice, 100 * UNIT);
        vault.deployCredit(100 * UNIT);
        bytes32 id = keccak256("payment1");
        vault.recordCashflow(id, _payment(alice, 20 * UNIT, 5 * UNIT, UNIT), 20 * UNIT);
        assertEq(vault.principalOf(alice), 80 * UNIT);
        assertEq(vault.creditNAV(), 80 * UNIT);
        assertEq(vault.totalSupply(), 100e18);
        assertEq(vault.reservedCashflows(), 24 * UNIT);
        assertEq(asset.balanceOf(tax), UNIT);
        assertEq(vault.cashflow(id).beneficiary, alice);
        vm.prank(alice);
        assertEq(vault.claimCashflow(id, bob), 24 * UNIT);
        assertTrue(vault.cashflow(id).claimed);
        assertEq(vault.reservedCashflows(), 0);
    }

    function test_HistoricalCashflowDoesNotMoveWithShares() public {
        _deposit(alice, 100 * UNIT);
        vault.deployCredit(100 * UNIT);
        bytes32 id = keccak256("payment1");
        vault.recordCashflow(id, _payment(alice, 10 * UNIT, 2 * UNIT, 0), 10 * UNIT);
        vm.prank(alice);
        vault.transfer(bob, 100e18);
        assertEq(vault.principalOf(bob), 90 * UNIT);
        vm.prank(alice);
        vault.claimCashflow(id, alice);
        assertEq(vault.cashflow(id).beneficiary, alice);
    }

    function test_ZeroNetCashflowCanBeClaimedOnce() public {
        bytes32 id = keccak256("all tax");
        vault.recordCashflow(id, _payment(alice, 0, UNIT, UNIT), 0);
        vm.prank(alice);
        assertEq(vault.claimCashflow(id, alice), 0);
        assertTrue(vault.cashflow(id).claimed);
    }

    function test_CreditDeployRepayAndNAVNonce() public {
        _deposit(alice, 100 * UNIT);
        vault.deployCredit(80 * UNIT);
        assertEq(vault.totalAssets(), 100 * UNIT);
        assertEq(vault.managedCash(), 20 * UNIT);
        vault.repayCredit(30 * UNIT);
        assertEq(vault.managedCash(), 50 * UNIT);
        assertEq(vault.creditNAV(), 50 * UNIT);
        vault.reportCreditNAV(40 * UNIT, 1, keccak256("impairment"));
        assertEq(vault.totalAssets(), 90 * UNIT);
    }

    function test_DonationDoesNotManipulateConversionOrNAV() public {
        _deposit(alice, UNIT);
        uint256 expected = vault.previewDeposit(UNIT);
        asset.mint(address(vault), 1_000_000 * UNIT);
        assertEq(vault.totalAssets(), UNIT);
        assertEq(_deposit(bob, UNIT), expected);
        assertEq(vault.totalSupply(), 2e18);
    }

    function test_MaxFunctionsTrackCapPauseEligibilityAndClaimable() public {
        assertEq(vault.maxDeposit(outsider), 0);
        _deposit(alice, 1_000_000 * UNIT);
        assertEq(vault.maxDeposit(alice), 0);
        assertEq(vault.maxMint(alice), 0);
        _request(alice, alice, 1e18);
        vault.fulfillRedeem(alice);
        assertEq(vault.maxRedeem(alice), 1e18);
        vault.pause();
        assertEq(vault.maxRedeem(alice), 0);
        assertEq(vault.maxWithdraw(alice), 0);
        vault.unpause();
        policy.setEligibility(alice, true, true);
        assertEq(vault.maxWithdraw(alice), 0);
    }

    function test_MaxFunctionsRemainBoundedAtFullImpairment() public {
        _deposit(alice, 100 * UNIT);
        vault.deployCredit(100 * UNIT);
        vault.reportCreditNAV(0, 1, keccak256("loss"));
        assertLe(vault.maxDeposit(bob), vault.assetCap());
        assertLe(vault.maxMint(bob), vault.MAX_SHARES());
    }

    function test_AsyncPreviewAlwaysRevertsEvenForZero() public {
        vm.expectRevert(StructuredFundVault.AsyncPreview.selector);
        vault.previewRedeem(0);
        vm.expectRevert(StructuredFundVault.AsyncPreview.selector);
        vault.previewWithdraw(0);
    }

    function test_FullLossRedeemClearsZeroAssetRights() public {
        _deposit(alice, UNIT);
        vault.deployCredit(UNIT);
        vault.reportCreditNAV(0, 1, keccak256("loss"));
        _request(alice, alice, 1e18);
        vault.fulfillRedeem(alice);
        vm.prank(alice);
        assertEq(vault.redeem(1e18, alice, alice), 0);
        assertEq(vault.maxRedeem(alice), 0);
    }

    function test_DifferentAssetDecimalsZeroAndEighteen() public {
        for (uint8 d; d <= 18; d += 18) {
            MockAsset a = new MockAsset(d);
            StructuredFundVault v = new StructuredFundVault(
                a,
                policy,
                keccak256(abi.encode(d)),
                address(this),
                treasury,
                tax,
                type(uint96).max,
                "Structured Fund Cashflows Reference",
                "nxREF"
            );
            a.mint(alice, 10 ** d);
            vm.startPrank(alice);
            a.approve(address(v), type(uint256).max);
            assertEq(v.deposit(10 ** d, alice), 1e18);
            vm.stopPrank();
            assertEq(v.decimals(), 18);
            if (d == 18) break;
        }
    }

    function testFuzz_TransferPrincipalConservation(uint96 value, uint96 fraction) public {
        uint256 amount = bound(value, 1, 100_000 * UNIT);
        uint256 shares = _deposit(alice, amount);
        uint256 move = bound(fraction, 0, shares);
        vm.prank(alice);
        vault.transfer(bob, move);
        assertEq(vault.principalOf(alice) + vault.principalOf(bob), amount);
    }

    function testFuzz_PartialClaimConservesReserves(uint96 amountSeed, uint96 splitSeed) public {
        uint256 amount = bound(amountSeed, 1, 100_000 * UNIT);
        uint256 shares = _deposit(alice, amount);
        _request(alice, alice, shares);
        vault.fulfillRedeem(alice);
        uint256 split = bound(splitSeed, 1, shares);
        vm.prank(alice);
        uint256 first = vault.redeem(split, alice, alice);
        uint256 second;
        if (split < shares) {
            vm.prank(alice);
            second = vault.redeem(shares - split, alice, alice);
        }
        assertEq(first + second, amount);
        assertEq(vault.reservedRedemptions(), 0);
    }

    function testFuzz_ExactMintMatchesPreview(uint96 shareSeed) public {
        _deposit(alice, 100 * UNIT);
        uint256 shares = bound(shareSeed, 1, 1000e18);
        uint256 expected = vault.previewMint(shares);
        vm.prank(bob);
        assertEq(vault.mint(shares, bob), expected);
        assertEq(vault.balanceOf(bob), shares);
    }
}
