// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;
import {StructuredFundBase} from "../Base.t.sol";
import {StructuredFundVault} from "../../src/StructuredFundVault.sol";
import {IStructuredFundCashflows} from "../../src/interfaces/IStructuredFundCashflows.sol";
import {IStructuredFundEligibility} from "../../src/interfaces/IStructuredFundEligibility.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MockAsset} from "../mocks/MockAsset.sol";

contract BrokenEligibility is IStructuredFundEligibility {
    function isEligible(address) external pure returns (bool) {
        revert("unavailable");
    }
}

contract StructuredFundSecurityTest is StructuredFundBase {
    function test_SecuritySynchronousControllerOverloadsEnforceAuthorizationAndLimits() public {
        vm.prank(bob);
        vm.expectRevert(StructuredFundVault.UnauthorizedController.selector);
        vault.deposit(UNIT, bob, alice);
        vm.prank(bob);
        vm.expectRevert(StructuredFundVault.UnauthorizedController.selector);
        vault.mint(1e18, bob, alice);
        vm.startPrank(alice);
        vm.expectRevert(StructuredFundVault.ZeroAmount.selector);
        vault.deposit(0, alice, alice);
        vm.expectRevert(StructuredFundVault.ZeroAmount.selector);
        vault.mint(0, alice, alice);
        vm.expectRevert();
        vault.deposit(1_000_001 * UNIT, alice, alice);
        vm.expectRevert();
        vault.mint(1_000_001e18, alice, alice);
        vm.stopPrank();
    }

    function test_SecurityControllerOverloadRequiresUnderlyingAllowance() public {
        vm.prank(alice);
        vault.setOperator(bob, true);
        vm.prank(alice);
        asset.approve(address(vault), 0);
        vm.prank(bob);
        vm.expectRevert();
        vault.deposit(UNIT, carol, alice);
        assertEq(vault.balanceOf(carol), 0);
        assertEq(vault.totalAssets(), 0);
    }

    function test_SecurityNAVReleaseCannotSkipPrincipalOrExceedGrossPayment() public {
        _deposit(alice, 100 * UNIT);
        vault.deployCredit(100 * UNIT);
        IStructuredFundCashflows.Cashflow memory p = _payment(alice, 20 * UNIT, 5 * UNIT, UNIT);
        vm.expectRevert(StructuredFundVault.InvalidCashflow.selector);
        vault.recordCashflow(keccak256("under"), p, 19 * UNIT);
        vm.expectRevert(StructuredFundVault.InvalidCashflow.selector);
        vault.recordCashflow(keccak256("over"), p, 26 * UNIT);
        assertEq(vault.creditNAV(), 100 * UNIT);
        assertEq(vault.principalOf(alice), 100 * UNIT);
    }

    function test_SecurityUnauthorizedRoles() public {
        vm.startPrank(outsider);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, outsider, vault.PAUSER_ROLE()
            )
        );
        vault.pause();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, outsider, vault.TREASURY_ROLE()
            )
        );
        vault.deployCredit(1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, outsider, vault.VALUER_ROLE()
            )
        );
        vault.reportCreditNAV(1, 1, keccak256("bad"));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, outsider, vault.SETTLER_ROLE()
            )
        );
        vault.fulfillRedeem(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, outsider, vault.SETTLER_ROLE()
            )
        );
        vault.repayCredit(1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, outsider, vault.SETTLER_ROLE()
            )
        );
        vault.fulfillCancel(alice);
        vm.stopPrank();
    }

    function test_SecurityNoUnauthorizedRequestOrClaim() public {
        _deposit(alice, 100 * UNIT);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1e18));
        vault.requestRedeem(1e18, bob, alice);
        _request(alice, alice, 1e18);
        vault.fulfillRedeem(alice);
        vm.prank(bob);
        vm.expectRevert(StructuredFundVault.UnauthorizedController.selector);
        vault.redeem(1e18, bob, alice);
    }

    function test_SecurityRevokedOperatorCannotClaim() public {
        _deposit(alice, UNIT);
        _request(alice, alice, 1e18);
        vault.fulfillRedeem(alice);
        vm.prank(alice);
        vault.setOperator(bob, true);
        vm.prank(alice);
        vault.setOperator(bob, false);
        vm.prank(bob);
        vm.expectRevert(StructuredFundVault.UnauthorizedController.selector);
        vault.redeem(1e18, bob, alice);
    }

    function test_SecurityUnapprovedRecipientCannotReceiveShares() public {
        _deposit(alice, UNIT);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(StructuredFundVault.Ineligible.selector, outsider));
        vault.transfer(outsider, 1);
        vm.prank(alice);
        vault.approve(bob, 1);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(StructuredFundVault.Ineligible.selector, outsider));
        vault.transferFrom(alice, outsider, 1);
        assertEq(vault.allowance(alice, bob), 1);
    }

    function test_SecurityFrozenOwnerCannotTransferOrRequest() public {
        _deposit(alice, UNIT);
        policy.setEligibility(alice, true, true);
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(StructuredFundVault.Ineligible.selector, alice));
        vault.transfer(bob, 1);
        vm.expectRevert(abi.encodeWithSelector(StructuredFundVault.Ineligible.selector, alice));
        vault.requestRedeem(1, alice, alice);
        vm.stopPrank();
    }

    function test_SecurityDepositRequiresEligiblePayerAndReceiver() public {
        asset.mint(outsider, UNIT);
        vm.prank(outsider);
        asset.approve(address(vault), UNIT);
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(StructuredFundVault.Ineligible.selector, outsider));
        vault.deposit(UNIT, alice);
        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(UNIT, outsider);
    }

    function test_SecurityClaimCannotEscapeFreezeOrSendToBlockedRecipient() public {
        _deposit(alice, UNIT);
        _request(alice, alice, 1e18);
        vault.fulfillRedeem(alice);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(StructuredFundVault.Ineligible.selector, outsider));
        vault.redeem(1e18, outsider, alice);
        policy.setEligibility(alice, true, true);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(StructuredFundVault.Ineligible.selector, alice));
        vault.redeem(1e18, bob, alice);
        assertEq(vault.reservedRedemptions(), UNIT);
    }

    function test_SecurityNoDirectEscrowTransfers() public {
        _deposit(alice, UNIT);
        vm.prank(alice);
        vm.expectRevert(StructuredFundVault.DirectEscrowTransfer.selector);
        vault.transfer(address(vault), 1);
    }

    function test_SecurityNoDoubleRedeemOrSettlement() public {
        _deposit(alice, UNIT);
        _request(alice, alice, 1e18);
        vault.fulfillRedeem(alice);
        vm.expectRevert(StructuredFundVault.InvalidRequest.selector);
        vault.fulfillRedeem(alice);
        vm.prank(alice);
        vault.redeem(1e18, alice, alice);
        vm.prank(alice);
        vm.expectRevert(StructuredFundVault.InvalidRequest.selector);
        vault.redeem(1e18, alice, alice);
    }

    function test_SecurityNoPrematureClaimsOrOverRequest() public {
        _deposit(alice, UNIT);
        _request(alice, alice, 1e18);
        vm.prank(alice);
        vm.expectRevert(StructuredFundVault.InvalidRequest.selector);
        vault.redeem(1e18, alice, alice);
        vm.prank(alice);
        vm.expectRevert(StructuredFundVault.InvalidRequest.selector);
        vault.requestRedeem(1, alice, alice);
    }

    function test_SecurityNoMintOrDepositWhilePaused() public {
        vault.pause();
        vm.startPrank(alice);
        vm.expectRevert();
        vault.deposit(UNIT, alice);
        vm.expectRevert();
        vault.mint(1e18, alice);
        vm.stopPrank();
    }

    function test_SecurityCancelRemainsRecoverableDuringPause() public {
        _deposit(alice, UNIT);
        _request(alice, alice, 1e18);
        vault.pause();
        vm.prank(alice);
        vault.cancelRedeemRequest(0, alice);
        vault.fulfillCancel(alice);
        vm.prank(alice);
        vault.claimCancelRedeemRequest(0, alice, alice);
        assertEq(vault.balanceOf(alice), 1e18);
        assertEq(vault.principalOf(alice), UNIT);
    }

    function test_SecurityCancellationBlocksNewRequestsAndSettlement() public {
        _deposit(alice, 2 * UNIT);
        _request(alice, alice, 1e18);
        vm.prank(alice);
        vault.cancelRedeemRequest(0, alice);
        vm.prank(alice);
        vm.expectRevert(StructuredFundVault.InvalidRequest.selector);
        vault.requestRedeem(1e18, alice, alice);
        vm.expectRevert(StructuredFundVault.InvalidRequest.selector);
        vault.fulfillRedeem(alice);
        vault.fulfillCancel(alice);
        vm.prank(alice);
        vm.expectRevert(StructuredFundVault.InvalidRequest.selector);
        vault.requestRedeem(1e18, alice, alice);
        vm.prank(alice);
        vault.claimCancelRedeemRequest(0, alice, alice);
        vm.prank(alice);
        vault.requestRedeem(1e18, alice, alice);
    }

    function test_SecurityCancelledSharesCannotBeClaimedTwice() public {
        _deposit(alice, UNIT);
        _request(alice, alice, 1e18);
        vm.prank(alice);
        vault.cancelRedeemRequest(0, alice);
        vault.fulfillCancel(alice);
        vm.prank(alice);
        vault.claimCancelRedeemRequest(0, alice, alice);
        vm.prank(alice);
        vm.expectRevert(StructuredFundVault.InvalidRequest.selector);
        vault.claimCancelRedeemRequest(0, alice, alice);
    }

    function test_SecurityReservesCannotBeDeployed() public {
        _deposit(alice, 100 * UNIT);
        _request(alice, alice, 100e18);
        vault.fulfillRedeem(alice);
        vm.expectRevert(StructuredFundVault.InsufficientLiquidity.selector);
        vault.deployCredit(1);
        assertEq(asset.balanceOf(address(vault)), vault.reservedRedemptions());
    }

    function test_SecurityIlliquidRedeemDoesNotChangeAccounting() public {
        _deposit(alice, UNIT);
        vault.deployCredit(UNIT);
        _request(alice, alice, 1e18);
        vm.expectRevert(StructuredFundVault.InsufficientLiquidity.selector);
        vault.fulfillRedeem(alice);
        assertEq(vault.totalSupply(), 1e18);
        assertEq(vault.pendingRedeemRequest(0, alice), 1e18);
    }

    function test_SecurityFeeOnTransferDepositRejectedAtomically() public {
        asset.setFee(100);
        vm.prank(alice);
        vm.expectRevert(StructuredFundVault.NonExactAssetTransfer.selector);
        vault.deposit(100 * UNIT, alice);
        assertEq(vault.totalSupply(), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(vault.totalOutstandingPrincipal(), 0);
    }

    function test_SecurityFeeOnTransferClaimRejectedAtomically() public {
        _deposit(alice, 100 * UNIT);
        _request(alice, alice, 100e18);
        vault.fulfillRedeem(alice);
        asset.setFee(100);
        vm.prank(alice);
        vm.expectRevert(StructuredFundVault.NonExactAssetTransfer.selector);
        vault.redeem(100e18, alice, alice);
        assertEq(vault.claimableRedeemRequest(0, alice), 100e18);
        assertEq(vault.reservedRedemptions(), 100 * UNIT);
    }

    function test_SecurityReentrantDepositCallbackCannotEnterOrStealEscrow() public {
        policy.setEligibility(address(asset), true, false);
        asset.mint(address(asset), UNIT);
        asset.setCallback(
            address(vault), abi.encodeWithSignature("deposit(uint256,address)", UNIT, address(asset)), false
        );
        _deposit(alice, UNIT);
        assertFalse(asset.callbackSucceeded());
        assertEq(vault.totalSupply(), 1e18);
    }

    function test_SecurityReentrantClaimCannotDoublePay() public {
        _deposit(alice, UNIT);
        _request(alice, alice, 1e18);
        vault.fulfillRedeem(alice);
        vm.prank(alice);
        vault.setOperator(address(asset), true);
        asset.setCallback(address(vault), abi.encodeCall(vault.redeem, (1e18, bob, alice)), false);
        vm.prank(alice);
        vault.redeem(1e18, alice, alice);
        assertFalse(asset.callbackSucceeded());
        assertEq(vault.reservedRedemptions(), 0);
    }

    function test_SecurityValuationReentrancyBlockedEvenWithValuerRole() public {
        _deposit(alice, UNIT);
        vault.grantRole(vault.VALUER_ROLE(), address(asset));
        asset.setCallback(
            address(vault), abi.encodeCall(vault.reportCreditNAV, (UNIT, 1, keccak256("callback"))), false
        );
        vault.deployCredit(UNIT);
        assertFalse(asset.callbackSucceeded());
        assertEq(vault.navNonce(), 0);
    }

    function test_SecurityCashflowDuplicateDoubleClaimAndReplay() public {
        _deposit(alice, 100 * UNIT);
        vault.deployCredit(100 * UNIT);
        bytes32 id = keccak256("payment");
        IStructuredFundCashflows.Cashflow memory p = _payment(alice, UNIT, UNIT, 0);
        vault.recordCashflow(id, p, p.principal);
        vm.expectRevert(StructuredFundVault.InvalidCashflow.selector);
        vault.recordCashflow(id, p, p.principal);
        vm.prank(alice);
        vault.claimCashflow(id, alice);
        vm.prank(alice);
        vm.expectRevert(StructuredFundVault.InvalidCashflow.selector);
        vault.claimCashflow(id, alice);
        vm.expectRevert(StructuredFundVault.InvalidCashflow.selector);
        vault.recordCashflow(keccak256("new id same period"), p, p.principal);
    }

    function test_SecurityCashflowBoundsAndEvidence() public {
        _deposit(alice, 100 * UNIT);
        vault.deployCredit(100 * UNIT);
        IStructuredFundCashflows.Cashflow memory p = _payment(alice, 101 * UNIT, UNIT, 0);
        vm.expectRevert(StructuredFundVault.InvalidCashflow.selector);
        vault.recordCashflow(keccak256("p"), p, p.principal);
        p.principal = 0;
        p.withheld = 2 * UNIT;
        vm.expectRevert(StructuredFundVault.InvalidCashflow.selector);
        vault.recordCashflow(keccak256("p"), p, p.principal);
        p.withheld = 0;
        p.evidenceHash = bytes32(0);
        vm.expectRevert(StructuredFundVault.InvalidCashflow.selector);
        vault.recordCashflow(keccak256("p"), p, p.principal);
        p.evidenceHash = keccak256("e");
        p.periodEnd = uint64(block.timestamp + 1);
        vm.expectRevert(StructuredFundVault.InvalidCashflow.selector);
        vault.recordCashflow(keccak256("p"), p, p.principal);
    }

    function test_SecurityCashflowInsufficientFundingRollsBackPrincipal() public {
        _deposit(alice, 100 * UNIT);
        vault.deployCredit(100 * UNIT);
        asset.approve(address(vault), 0);
        bytes32 id = keccak256("p");
        vm.expectRevert();
        vault.recordCashflow(id, _payment(alice, UNIT, UNIT, 0), UNIT);
        assertEq(vault.principalOf(alice), 100 * UNIT);
        assertEq(vault.creditNAV(), 100 * UNIT);
        assertEq(vault.cashflow(id).beneficiary, address(0));
        assertEq(vault.reservedCashflows(), 0);
    }

    function test_SecurityLockedPrincipalCannotReceiveExplicitAmortization() public {
        _deposit(alice, 100 * UNIT);
        vault.deployCredit(100 * UNIT);
        _request(alice, alice, 100e18);
        vm.expectRevert(StructuredFundVault.InvalidCashflow.selector);
        vault.recordCashflow(keccak256("p"), _payment(alice, UNIT, UNIT, 0), UNIT);
    }

    function test_SecurityCashflowReentrantClaimBlocked() public {
        bytes32 id = keccak256("p");
        vault.recordCashflow(id, _payment(alice, 0, UNIT, 0), 0);
        vm.prank(alice);
        vault.setOperator(address(asset), true);
        asset.setCallback(address(vault), abi.encodeCall(vault.claimCashflow, (id, alice)), false);
        vm.prank(alice);
        vault.claimCashflow(id, alice);
        assertFalse(asset.callbackSucceeded());
        assertTrue(vault.cashflow(id).claimed);
    }

    function test_SecurityCashflowCannotBeStolen() public {
        bytes32 id = keccak256("p");
        vault.recordCashflow(id, _payment(alice, 0, UNIT, 0), 0);
        vm.prank(bob);
        vm.expectRevert(StructuredFundVault.UnauthorizedController.selector);
        vault.claimCashflow(id, bob);
    }

    function test_SecurityCashflowIsRecoverableDuringPause() public {
        bytes32 id = keccak256("p");
        vault.recordCashflow(id, _payment(alice, 0, UNIT, 0), 0);
        vault.pause();
        vm.prank(alice);
        vault.claimCashflow(id, alice);
        assertTrue(vault.cashflow(id).claimed);
    }

    function test_SecurityNAVCannotReplayOverflowCapOrCreateEmptyCredit() public {
        vm.expectRevert(StructuredFundVault.InvalidRequest.selector);
        vault.reportCreditNAV(1, 1, keccak256("fake"));
        _deposit(alice, UNIT);
        vault.deployCredit(UNIT);
        vault.reportCreditNAV(UNIT, 1, keccak256("good"));
        vm.expectRevert(StructuredFundVault.InvalidRequest.selector);
        vault.reportCreditNAV(UNIT, 1, keccak256("replay"));
        uint256 excess = vault.assetCap() + 1;
        vm.expectRevert(StructuredFundVault.InvalidRequest.selector);
        vault.reportCreditNAV(excess, 2, keccak256("cap"));
    }

    function test_SecuritySlippageGuardRollsBackDeposit() public {
        vm.prank(alice);
        vm.expectRevert(StructuredFundVault.Slippage.selector);
        vault.depositWithMinShares(UNIT, alice, 1e18 + 1);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
    }

    function test_SecurityLimitsFailClosedWithBrokenEligibilityService() public {
        BrokenEligibility broken = new BrokenEligibility();
        StructuredFundVault v = new StructuredFundVault(
            asset,
            broken,
            keccak256("broken"),
            address(this),
            treasury,
            tax,
            UNIT,
            "Structured Fund Cashflows rUSD",
            "sfcUSD"
        );
        assertEq(v.maxDeposit(alice), 0);
        assertEq(v.maxMint(alice), 0);
        assertEq(v.maxRedeem(alice), 0);
    }

    function test_SecurityRejectsUnsupportedDecimals() public {
        MockAsset a = new MockAsset(19);
        vm.expectRevert(StructuredFundVault.InvalidConfiguration.selector);
        new StructuredFundVault(
            a, policy, keccak256("scope"), address(this), treasury, tax, UNIT, "Structured Fund Cashflows", "sfcUSD"
        );
    }

    function test_SecurityZeroDepositAndRequestRejected() public {
        vm.prank(alice);
        vm.expectRevert(StructuredFundVault.ZeroAmount.selector);
        vault.deposit(0, alice);
        vm.prank(alice);
        vm.expectRevert(StructuredFundVault.ZeroAmount.selector);
        vault.requestRedeem(0, alice, alice);
    }

    function test_SecurityAdminTransferRequiresDelayAndAcceptance() public {
        vault.beginDefaultAdminTransfer(bob);
        vm.prank(bob);
        vm.expectRevert();
        vault.acceptDefaultAdminTransfer();
        vm.warp(block.timestamp + 2 days + 1);
        vm.prank(bob);
        vault.acceptDefaultAdminTransfer();
        assertEq(vault.defaultAdmin(), bob);
        assertFalse(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), address(this)));
    }

    function test_SecurityInvalidOperatorCannotBeApproved() public {
        vm.startPrank(alice);
        vm.expectRevert(StructuredFundVault.InvalidRequest.selector);
        vault.setOperator(address(0), true);
        vm.expectRevert(StructuredFundVault.InvalidRequest.selector);
        vault.setOperator(alice, true);
        vm.expectRevert(StructuredFundVault.ZeroAmount.selector);
        vault.mint(0, alice);
        vm.stopPrank();
    }

    function test_SecurityInvalidCancelIdAndPrematureClaimRejected() public {
        _deposit(alice, UNIT);
        _request(alice, alice, 1e18);
        vm.prank(alice);
        vm.expectRevert(StructuredFundVault.InvalidRequest.selector);
        vault.cancelRedeemRequest(1, alice);
        vm.prank(alice);
        vm.expectRevert(StructuredFundVault.InvalidRequest.selector);
        vault.claimCancelRedeemRequest(0, alice, alice);
        vm.expectRevert(StructuredFundVault.InvalidRequest.selector);
        vault.fulfillCancel(alice);
        vm.prank(bob);
        vm.expectRevert(StructuredFundVault.UnauthorizedController.selector);
        vault.cancelRedeemRequest(0, alice);
    }

    function test_SecurityWithdrawZeroAndExcessRejected() public {
        _deposit(alice, UNIT);
        _request(alice, alice, 1e18);
        vault.fulfillRedeem(alice);
        vm.startPrank(alice);
        vm.expectRevert(StructuredFundVault.InvalidRequest.selector);
        vault.withdraw(0, alice, alice);
        vm.expectRevert(StructuredFundVault.InvalidRequest.selector);
        vault.withdraw(UNIT + 1, alice, alice);
        vm.stopPrank();
    }

    function test_SecurityPartialWithdrawCannotStrandAssetsWithoutShares() public {
        MockAsset a = new MockAsset(18);
        StructuredFundVault v = new StructuredFundVault(
            a,
            policy,
            keccak256("tiny shares"),
            address(this),
            treasury,
            tax,
            1000,
            "Structured Fund Cashflows rUSD",
            "sfcUSD"
        );
        a.mint(alice, 1);
        a.mint(address(this), 100);
        a.approve(address(v), type(uint256).max);
        vm.startPrank(alice);
        a.approve(address(v), 1);
        v.mint(1, alice);
        vm.stopPrank();
        v.deployCredit(1);
        v.reportCreditNAV(100, 1, keccak256("gain"));
        v.repayCredit(100);
        vm.prank(alice);
        v.requestRedeem(1, alice, alice);
        v.fulfillRedeem(alice);
        assertEq(v.maxWithdraw(alice), 50);
        vm.prank(alice);
        vm.expectRevert(StructuredFundVault.InvalidRequest.selector);
        v.withdraw(1, alice, alice);
        vm.prank(alice);
        assertEq(v.redeem(1, alice, alice), 50);
    }

    function test_SecurityDepositThatRoundsToZeroSharesRejected() public {
        MockAsset a = new MockAsset(18);
        StructuredFundVault v = new StructuredFundVault(
            a,
            policy,
            keccak256("zero output"),
            address(this),
            treasury,
            tax,
            1000,
            "Structured Fund Cashflows rUSD",
            "sfcUSD"
        );
        a.mint(alice, 2);
        vm.startPrank(alice);
        a.approve(address(v), 2);
        v.deposit(1, alice);
        vm.stopPrank();
        v.deployCredit(1);
        v.reportCreditNAV(100, 1, keccak256("gain"));
        assertEq(v.previewDeposit(1), 0);
        vm.prank(alice);
        vm.expectRevert(StructuredFundVault.ZeroAmount.selector);
        v.deposit(1, alice);
    }

    function test_SecurityEmptyAndExcessRepaymentRejected() public {
        vm.expectRevert(StructuredFundVault.InvalidRequest.selector);
        vault.repayCredit(1);
        _deposit(alice, UNIT);
        vault.deployCredit(UNIT);
        vm.expectRevert(StructuredFundVault.InvalidRequest.selector);
        vault.repayCredit(UNIT + 1);
        vm.expectRevert(StructuredFundVault.InvalidRequest.selector);
        vault.repayCredit(0);
    }

    function test_SecurityPrincipalLedgerIsNotGuaranteedRecovery() public {
        _deposit(alice, 100 * UNIT);
        vault.deployCredit(100 * UNIT);
        vault.reportCreditNAV(70 * UNIT, 1, keccak256("loss"));
        vault.repayCredit(70 * UNIT);
        _request(alice, alice, 100e18);
        vault.fulfillRedeem(alice);
        uint256 recovery = vault.maxWithdraw(alice);
        assertLt(recovery, 100 * UNIT);
        assertEq(vault.totalOutstandingPrincipal(), 0);
        vm.prank(alice);
        assertEq(vault.redeem(100e18, alice, alice), recovery);
    }

    function test_SecurityOversizedCashflowAndFutureOrEmptyPeriodRejected() public {
        IStructuredFundCashflows.Cashflow memory p = _payment(alice, 0, type(uint96).max + uint256(1), 0);
        vm.expectRevert(StructuredFundVault.InvalidCashflow.selector);
        vault.recordCashflow(keccak256("large"), p, p.principal);
        p.grossYield = UNIT;
        p.periodStart = p.periodEnd;
        vm.expectRevert(StructuredFundVault.InvalidCashflow.selector);
        vault.recordCashflow(keccak256("empty"), p, p.principal);
        p = _payment(alice, 0, UNIT, 0);
        p.claimed = true;
        vm.expectRevert(StructuredFundVault.InvalidCashflow.selector);
        vault.recordCashflow(keccak256("consumed"), p, p.principal);
    }

    function test_SecuritySharesDoNotTransferDuringPause() public {
        _deposit(alice, UNIT);
        vault.pause();
        vm.prank(alice);
        vm.expectRevert();
        vault.transfer(bob, 1e18);
        assertEq(vault.principalOf(alice), UNIT);
    }
}
