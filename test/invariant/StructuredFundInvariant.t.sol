// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;
import {StructuredFundBase} from "../Base.t.sol";
import {Test} from "forge-std/Test.sol";
import {StructuredFundVault} from "../../src/StructuredFundVault.sol";
import {StructuredFundEligibility} from "../../src/StructuredFundEligibility.sol";
import {IStructuredFundCashflows} from "../../src/interfaces/IStructuredFundCashflows.sol";
import {MockAsset} from "../mocks/MockAsset.sol";

/// @dev Stateful actions select valid operations. fail_on_revert makes unexpected failures visible.
contract StructuredFundHandler is Test {
    StructuredFundVault public immutable vault;
    StructuredFundEligibility public immutable policy;
    MockAsset public immutable asset;
    address[3] public actors;
    bytes32[] public ids;
    mapping(bytes32 => bytes32) public originalTerms;
    mapping(bytes32 => bool) public consumed;
    uint256 public donatedAssets;
    uint256 public depositedPrincipal;
    uint256 public retiredByRedeem;
    uint256 public amortizedPrincipal;
    uint256 public cashflowNetRecorded;
    uint256 public cashflowNetClaimed;
    uint256 public redeemedAssets;
    uint256 public fulfilledAssets;
    uint256 public nonce;
    int256 public expectedNAV;

    constructor(StructuredFundVault v, StructuredFundEligibility p, MockAsset a, address[3] memory users) {
        vault = v;
        policy = p;
        asset = a;
        actors = users;
        asset.approve(address(vault), type(uint256).max);
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % 3];
    }

    function idsLength() external view returns (uint256) {
        return ids.length;
    }

    function _state(address c) private view returns (StructuredFundVault.RedeemState memory r) {
        (
            r.pendingShares,
            r.lockedPrincipal,
            r.claimableShares,
            r.claimableAssets,
            r.cancelPending,
            r.cancelShares,
            r.cancelPrincipal
        ) = vault.redeemState(c);
    }

    function deposit(uint256 seed, uint96 amountSeed) external {
        address a = _actor(seed);
        uint256 max = vault.maxDeposit(a);
        if (max == 0) return;
        uint256 amount = bound(amountSeed, 1, min(max, 1000e6));
        if (vault.previewDeposit(amount) == 0) return;
        asset.mint(a, amount);
        vm.prank(a);
        if (seed % 2 == 0) vault.deposit(amount, a);
        else vault.deposit(amount, a, a);
        depositedPrincipal += amount;
        expectedNAV += int256(amount);
    }

    function exactMint(uint256 seed, uint96 shareSeed) external {
        address a = _actor(seed);
        uint256 max = vault.maxMint(a);
        if (max == 0) return;
        uint256 shares = bound(shareSeed, 1, min(max, 1000e18));
        uint256 amount = vault.previewMint(shares);
        asset.mint(a, amount);
        vm.prank(a);
        if (seed % 2 == 0) vault.mint(shares, a);
        else vault.mint(shares, a, a);
        depositedPrincipal += amount;
        expectedNAV += int256(amount);
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint96 shareSeed) external {
        address a = _actor(fromSeed);
        address b = _actor(toSeed);
        uint256 balance = vault.balanceOf(a);
        if (vault.paused() || !policy.isEligible(a) || !policy.isEligible(b) || balance == 0) return;
        uint256 shares = bound(shareSeed, 0, balance);
        vm.prank(a);
        vault.transfer(b, shares);
    }

    function request(uint256 ownerSeed, uint256 controllerSeed, uint96 shareSeed) external {
        address a = _actor(ownerSeed);
        address c = _actor(controllerSeed);
        uint256 balance = vault.balanceOf(a);
        StructuredFundVault.RedeemState memory r = _state(c);
        if (
            vault.paused() || !policy.isEligible(a) || !policy.isEligible(c) || balance == 0 || r.cancelPending
                || r.cancelShares != 0
        ) return;
        uint256 shares = bound(shareSeed, 1, balance);
        vm.prank(a);
        vault.requestRedeem(shares, c, a);
    }

    function fulfill(uint256 seed) external {
        address c = _actor(seed);
        StructuredFundVault.RedeemState memory r = _state(c);
        uint256 assets = vault.convertToAssets(r.pendingShares);
        if (vault.paused() || r.pendingShares == 0 || r.cancelPending || assets > vault.managedCash()) return;
        vault.fulfillRedeem(c);
        retiredByRedeem += r.lockedPrincipal;
        fulfilledAssets += assets;
        expectedNAV -= int256(assets);
    }

    function redeem(uint256 seed, uint96 shareSeed) external {
        address c = _actor(seed);
        uint256 max = vault.maxRedeem(c);
        if (max == 0) return;
        uint256 shares = bound(shareSeed, 1, max);
        vm.prank(c);
        redeemedAssets += vault.redeem(shares, c, c);
    }

    function withdraw(uint256 seed, uint96 assetSeed) external {
        address c = _actor(seed);
        StructuredFundVault.RedeemState memory r = _state(c);
        if (vault.paused() || !policy.isEligible(c) || r.claimableAssets == 0) return;
        // Full assets claim avoids sub-share dust; partial claims are separately fuzz tested.
        uint256 assets = assetSeed % 2 == 0 ? r.claimableAssets : r.claimableAssets / 2;
        if (assets == 0) return;
        uint256 shares = (assets * r.claimableShares + r.claimableAssets - 1) / r.claimableAssets;
        if (shares == r.claimableShares && assets < r.claimableAssets) return;
        vm.prank(c);
        vault.withdraw(assets, c, c);
        redeemedAssets += assets;
    }

    function cancel(uint256 seed) external {
        address c = _actor(seed);
        StructuredFundVault.RedeemState memory r = _state(c);
        if (r.pendingShares == 0 || r.cancelPending) return;
        vm.prank(c);
        vault.cancelRedeemRequest(0, c);
    }

    function fulfillCancel(uint256 seed) external {
        address c = _actor(seed);
        if (!_state(c).cancelPending) return;
        vault.fulfillCancel(c);
    }

    function claimCancel(uint256 seed, uint256 receiverSeed) external {
        address c = _actor(seed);
        address to = _actor(receiverSeed);
        if (_state(c).cancelShares == 0 || !policy.isEligible(c) || !policy.isEligible(to)) return;
        vm.prank(c);
        vault.claimCancelRedeemRequest(0, to, c);
    }

    function deploy(uint96 amountSeed) external {
        uint256 cash = vault.managedCash();
        if (vault.paused() || cash == 0) return;
        vault.deployCredit(bound(amountSeed, 1, cash));
    }

    function repay(uint96 amountSeed) external {
        uint256 credit = vault.creditNAV();
        if (credit == 0) return;
        uint256 amount = bound(amountSeed, 1, credit);
        asset.mint(address(this), amount);
        vault.repayCredit(amount);
    }

    function reportNAV(uint96 valueSeed) external {
        if (vault.paused() || vault.totalSupply() == 0) return;
        uint256 ceiling = vault.assetCap() - vault.managedCash();
        uint256 value = bound(valueSeed, 0, ceiling);
        expectedNAV += int256(value) - int256(vault.creditNAV());
        vault.reportCreditNAV(value, vault.navNonce() + 1, keccak256(abi.encode(++nonce)));
    }

    function recordCashflow(uint256 seed, uint96 principalSeed, uint96 yieldSeed, uint96 taxSeed) external {
        address a = _actor(seed);
        if (vault.paused() || !policy.isEligible(a)) return;
        uint256 p = bound(principalSeed, 0, min(vault.principalOf(a), vault.creditNAV()));
        uint256 y = bound(yieldSeed, 0, 100e6);
        if (p + y == 0) return;
        uint256 w = bound(taxSeed, 0, y);
        uint64 start = vault.lastCashflowPeriodEnd(a);
        if (start == 0) start = uint64(vm.getBlockTimestamp() - 1);
        vm.warp(vm.getBlockTimestamp() + 1);
        bytes32 id = keccak256(abi.encode("cashflow", ++nonce));
        IStructuredFundCashflows.Cashflow memory pay = IStructuredFundCashflows.Cashflow(
            a, p, y, w, start, uint64(vm.getBlockTimestamp()), keccak256("evidence"), false
        );
        asset.mint(address(this), p + y);
        uint256 release = p + min(y, vault.creditNAV() - p);
        vault.recordCashflow(id, pay, release);
        expectedNAV -= int256(release);
        ids.push(id);
        originalTerms[id] = keccak256(abi.encode(pay));
        amortizedPrincipal += p;
        cashflowNetRecorded += p + y - w;
    }

    function claimCashflow(uint256 seed) external {
        if (ids.length == 0) return;
        bytes32 id = ids[seed % ids.length];
        IStructuredFundCashflows.Cashflow memory p = vault.cashflow(id);
        if (p.claimed || !policy.isEligible(p.beneficiary)) return;
        vm.prank(p.beneficiary);
        cashflowNetClaimed += vault.claimCashflow(id, p.beneficiary);
        consumed[id] = true;
    }

    function recordBatch(uint96 principalSeed, uint96 yieldSeed, uint96 taxSeed) external {
        if (vault.paused()) return;
        for (uint256 i; i < 3; ++i) {
            if (!policy.isEligible(actors[i])) return;
        }
        bytes32[] memory batchIds = new bytes32[](3);
        IStructuredFundCashflows.Cashflow[] memory payments = new IStructuredFundCashflows.Cashflow[](3);
        uint256[] memory releases = new uint256[](3);
        uint256 remainingNAV = vault.creditNAV();
        uint256 grossFunding;
        vm.warp(vm.getBlockTimestamp() + 1);
        for (uint256 i; i < 3; ++i) {
            address a = actors[i];
            uint256 p = bound(principalSeed, 0, min(vault.principalOf(a), remainingNAV));
            uint256 y = bound(yieldSeed, 1, 100e6);
            uint256 w = bound(taxSeed, 0, y);
            uint64 start = vault.lastCashflowPeriodEnd(a);
            if (start == 0) start = uint64(vm.getBlockTimestamp() - 1);
            batchIds[i] = keccak256(abi.encode("batch", ++nonce));
            payments[i] = IStructuredFundCashflows.Cashflow(
                a, p, y, w, start, uint64(vm.getBlockTimestamp()), keccak256("batch evidence"), false
            );
            releases[i] = p + min(y, remainingNAV - p);
            remainingNAV -= releases[i];
            grossFunding += p + y;
        }
        asset.mint(address(this), grossFunding);
        vault.recordCashflowBatch(batchIds, payments, releases);
        for (uint256 i; i < 3; ++i) {
            ids.push(batchIds[i]);
            originalTerms[batchIds[i]] = keccak256(abi.encode(payments[i]));
            amortizedPrincipal += payments[i].principal;
            cashflowNetRecorded += payments[i].principal + payments[i].grossYield - payments[i].withheld;
            expectedNAV -= int256(releases[i]);
        }
    }

    function donate(uint96 amountSeed) external {
        uint256 amount = bound(amountSeed, 1, 1000e6);
        asset.mint(address(vault), amount);
        donatedAssets += amount;
    }

    function delegatedTransfer(uint256 fromSeed, uint256 toSeed, uint96 shareSeed) external {
        address a = _actor(fromSeed);
        address b = _actor(toSeed);
        uint256 balance = vault.balanceOf(a);
        if (vault.paused() || !policy.isEligible(a) || !policy.isEligible(b) || balance == 0) return;
        uint256 shares = bound(shareSeed, 0, balance);
        vm.prank(a);
        vault.approve(address(this), shares);
        vault.transferFrom(a, b, shares);
    }

    function togglePause() external {
        if (vault.paused()) vault.unpause();
        else vault.pause();
    }

    function toggleFreeze(uint256 seed) external {
        address a = _actor(seed);
        policy.setEligibility(a, true, !policy.frozen(a));
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}

contract StructuredFundInvariantTest is StructuredFundBase {
    StructuredFundHandler internal handler;

    function setUp() public override {
        super.setUp();
        handler = new StructuredFundHandler(vault, policy, asset, [alice, bob, carol]);
        vault.grantRole(vault.SETTLER_ROLE(), address(handler));
        vault.grantRole(vault.TREASURY_ROLE(), address(handler));
        vault.grantRole(vault.VALUER_ROLE(), address(handler));
        vault.grantRole(vault.PAUSER_ROLE(), address(handler));
        policy.grantRole(policy.COMPLIANCE_ROLE(), address(handler));
        bytes4[] memory selectors = new bytes4[](20);
        selectors[0] = handler.deposit.selector;
        selectors[1] = handler.exactMint.selector;
        selectors[2] = handler.transfer.selector;
        selectors[3] = handler.request.selector;
        selectors[4] = handler.fulfill.selector;
        selectors[5] = handler.redeem.selector;
        selectors[6] = handler.withdraw.selector;
        selectors[7] = handler.cancel.selector;
        selectors[8] = handler.fulfillCancel.selector;
        selectors[9] = handler.claimCancel.selector;
        selectors[10] = handler.deploy.selector;
        selectors[11] = handler.repay.selector;
        selectors[12] = handler.reportNAV.selector;
        selectors[13] = handler.recordCashflow.selector;
        selectors[14] = handler.claimCashflow.selector;
        selectors[15] = handler.togglePause.selector;
        selectors[16] = handler.toggleFreeze.selector;
        selectors[17] = handler.recordBatch.selector;
        selectors[18] = handler.donate.selector;
        selectors[19] = handler.delegatedTransfer.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyAndEscrowConservation() public view {
        uint256 circulating;
        uint256 escrow;
        for (uint256 i; i < 3; ++i) {
            address a = handler.actors(i);
            circulating += vault.balanceOf(a);
            (uint256 pending,,,,, uint256 cancelShares,) = vault.redeemState(a);
            escrow += pending + cancelShares;
            if (vault.balanceOf(a) == 0) assertEq(vault.principalOf(a), 0);
        }
        assertEq(escrow, vault.totalEscrowedShares());
        assertEq(vault.balanceOf(address(vault)), escrow);
        assertEq(vault.totalSupply(), circulating + escrow);
        assertLe(vault.totalSupply(), vault.MAX_SHARES());
    }

    function invariant_PrincipalConservationAndGhostAccounting() public view {
        uint256 freePrincipal;
        uint256 locked;
        for (uint256 i; i < 3; ++i) {
            address a = handler.actors(i);
            freePrincipal += vault.principalOf(a);
            (, uint256 pendingP,,,,, uint256 cancelP) = vault.redeemState(a);
            locked += pendingP + cancelP;
        }
        assertEq(locked, vault.totalLockedPrincipal());
        assertEq(freePrincipal + locked, vault.totalOutstandingPrincipal());
        assertEq(
            handler.depositedPrincipal(),
            vault.totalOutstandingPrincipal() + handler.retiredByRedeem() + handler.amortizedPrincipal()
        );
    }

    function invariant_ExactLiquidityAndReserveBacking() public view {
        assertEq(
            asset.balanceOf(address(vault)),
            vault.managedCash() + vault.reservedRedemptions() + vault.reservedCashflows() + handler.donatedAssets()
        );
        assertLe(vault.totalAssets(), vault.assetCap());
        assertEq(vault.totalAssets(), vault.managedCash() + vault.creditNAV());
        assertGe(handler.expectedNAV(), 0);
        assertEq(vault.totalAssets(), uint256(handler.expectedNAV()));
    }

    function invariant_RedemptionLiabilitiesEqualReserves() public view {
        uint256 owed;
        for (uint256 i; i < 3; ++i) {
            (,,, uint256 a,,,) = vault.redeemState(handler.actors(i));
            owed += a;
        }
        assertEq(owed, vault.reservedRedemptions());
        assertEq(handler.fulfilledAssets(), handler.redeemedAssets() + owed);
    }

    function invariant_CashflowLiabilitiesAndNoDoublePayment() public view {
        uint256 owed;
        uint256 count = handler.idsLength();
        for (uint256 i; i < count; ++i) {
            IStructuredFundCashflows.Cashflow memory p = vault.cashflow(handler.ids(i));
            assertLe(p.withheld, p.grossYield);
            if (!p.claimed) owed += p.principal + p.grossYield - p.withheld;
        }
        assertEq(owed, vault.reservedCashflows());
        assertEq(handler.cashflowNetRecorded(), handler.cashflowNetClaimed() + owed);
    }

    function invariant_RecordedTermsAreImmutableAndClaimsAreMonotonic() public view {
        uint256 count = handler.idsLength();
        for (uint256 i; i < count; ++i) {
            bytes32 id = handler.ids(i);
            IStructuredFundCashflows.Cashflow memory p = vault.cashflow(id);
            assertEq(p.claimed, handler.consumed(id));
            p.claimed = false;
            assertEq(keccak256(abi.encode(p)), handler.originalTerms(id));
        }
    }

    function invariant_LimitViewsRespectPauseEligibilityAndCapacity() public view {
        for (uint256 i; i < 3; ++i) {
            address a = handler.actors(i);
            uint256 deposits = vault.maxDeposit(a);
            uint256 mints = vault.maxMint(a);
            uint256 redemptions = vault.maxRedeem(a);
            uint256 withdrawals = vault.maxWithdraw(a);
            if (vault.paused() || !policy.isEligible(a)) {
                assertEq(deposits | mints | redemptions | withdrawals, 0);
            } else {
                assertLe(deposits, vault.assetCap() - vault.totalAssets());
                assertLe(mints, vault.MAX_SHARES() - vault.totalSupply());
                assertLe(vault.previewMint(mints), deposits);
                (,, uint256 shares, uint256 assets,,,) = vault.redeemState(a);
                assertEq(redemptions, shares);
                assertEq(withdrawals, assets);
            }
        }
    }
}
