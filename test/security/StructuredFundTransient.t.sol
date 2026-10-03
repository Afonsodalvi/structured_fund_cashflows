// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {StructuredFundBase} from "../Base.t.sol";
import {StructuredFundVault} from "../../src/StructuredFundVault.sol";
import {StructuredFundFactory} from "../../src/StructuredFundFactory.sol";
import {IStructuredFundEligibility} from "../../src/interfaces/IStructuredFundEligibility.sol";
import {IStructuredFundCashflows} from "../../src/interfaces/IStructuredFundCashflows.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Isolated, identical external work measures guard overhead, not whole-vault transaction savings.
contract PersistentGuardProbe is ReentrancyGuard {
    function guarded() external nonReentrant returns (uint256) {
        return 1;
    }
}

contract TransientGuardProbe is ReentrancyGuardTransient {
    function guarded() external nonReentrant returns (uint256) {
        return 1;
    }
}

contract FactoryReentryAsset is ERC20 {
    StructuredFundFactory private immutable _factory;

    constructor(StructuredFundFactory factory_) ERC20("Callback", "CB") {
        _factory = factory_;
    }

    function decimals() public view override returns (uint8) {
        (bool ok, bytes memory result) = address(_factory)
            .staticcall(
                abi.encodeCall(
                    _factory.createVault,
                    (
                        bytes32(0),
                        bytes32(0),
                        0,
                        IERC20(address(this)),
                        IStructuredFundEligibility(address(0)),
                        address(this),
                        address(1),
                        address(2),
                        1,
                        "Nested",
                        "N"
                    )
                )
            );
        require(
            !ok
                && keccak256(result)
                    == keccak256(
                        abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector)
                    ),
            "factory lock missing"
        );
        return 6;
    }
}

contract StructuredFundTransientTest is StructuredFundBase {
    function _authorizeCallbackToken() private {
        vault.grantRole(vault.SETTLER_ROLE(), address(asset));
        vault.grantRole(vault.TREASURY_ROLE(), address(asset));
        vault.grantRole(vault.VALUER_ROLE(), address(asset));
        policy.setEligibility(address(asset), true, false);
    }

    function _callback(uint256 index) private view returns (bytes memory) {
        if (index == 0) return abi.encodeWithSignature("deposit(uint256,address)", UNIT, alice);
        if (index == 1) return abi.encodeWithSignature("mint(uint256,address)", 1e18, alice);
        if (index == 2) return abi.encodeWithSignature("deposit(uint256,address,address)", UNIT, alice, alice);
        if (index == 3) return abi.encodeWithSignature("mint(uint256,address,address)", 1e18, alice, alice);
        if (index == 4) return abi.encodeCall(vault.depositWithMinShares, (UNIT, alice, 0));
        if (index == 5) return abi.encodeCall(vault.transfer, (bob, 1));
        if (index == 6) return abi.encodeCall(vault.transferFrom, (alice, bob, 1));
        if (index == 7) return abi.encodeCall(vault.requestRedeem, (1, alice, alice));
        if (index == 8) return abi.encodeCall(vault.fulfillRedeem, (alice));
        if (index == 9) return abi.encodeCall(vault.redeem, (1, alice, alice));
        if (index == 10) return abi.encodeCall(vault.withdraw, (1, alice, alice));
        if (index == 11) return abi.encodeCall(vault.cancelRedeemRequest, (0, alice));
        if (index == 12) return abi.encodeCall(vault.fulfillCancel, (alice));
        if (index == 13) return abi.encodeCall(vault.claimCancelRedeemRequest, (0, alice, alice));
        if (index == 14) return abi.encodeCall(vault.deployCredit, (UNIT));
        if (index == 15) return abi.encodeCall(vault.repayCredit, (UNIT));
        if (index == 16) return abi.encodeCall(vault.reportCreditNAV, (UNIT, 1, keccak256("reentrant")));
        if (index == 17) return abi.encodeCall(vault.recordCashflow, (keccak256("id"), _payment(alice, 0, 1, 0), 0));
        if (index == 18) {
            bytes32[] memory ids = new bytes32[](0);
            IStructuredFundCashflows.Cashflow[] memory payments = new IStructuredFundCashflows.Cashflow[](0);
            uint256[] memory releases = new uint256[](0);
            return abi.encodeCall(vault.recordCashflowBatch, (ids, payments, releases));
        }
        return abi.encodeCall(vault.claimCashflow, (keccak256("id"), alice));
    }

    function test_AllTwentyFinancialEntrypointsRejectCrossFunctionReentrancy() public {
        _authorizeCallbackToken();
        for (uint256 i; i < 20; ++i) {
            asset.setCallback(address(vault), _callback(i), false);
            _deposit(alice, UNIT);
            assertFalse(asset.callbackSucceeded());
            assertEq(
                asset.callbackReturnData(),
                abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector)
            );
        }
        assertEq(vault.principalOf(alice), 20 * UNIT);
        assertEq(vault.managedCash(), 20 * UNIT);
    }

    function testFuzz_TransientGuardBlocksCallbackAndUnlocks(uint8 target, uint96 amountSeed) public {
        _authorizeCallbackToken();
        uint256 amount = bound(amountSeed, 1, 1000 * UNIT);
        asset.setCallback(address(vault), _callback(uint256(target) % 20), false);
        _deposit(alice, amount);
        assertEq(
            asset.callbackReturnData(),
            abi.encodeWithSelector(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector)
        );
        asset.setCallback(address(0), "", false);
        _deposit(alice, amount);
        assertEq(vault.totalOutstandingPrincipal(), amount * 2);
        assertEq(asset.balanceOf(address(vault)), amount * 2);
    }

    function test_RevertedCallbackDoesNotLatchTransientLockOrChangeAccounting() public {
        asset.setCallback(address(vault), _callback(0), true);
        vm.prank(alice);
        vm.expectRevert(bytes("callback failed"));
        vault.deposit(UNIT, alice);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalOutstandingPrincipal(), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        asset.setCallback(address(0), "", false);
        _deposit(alice, UNIT);
        assertEq(vault.principalOf(alice), UNIT);
    }

    function test_PostDepositSlippageRevertUnlocksAndRollsBackSameTransaction() public {
        vm.startPrank(alice);
        vm.expectRevert(StructuredFundVault.Slippage.selector);
        vault.depositWithMinShares(UNIT, alice, 1e18 + 1);
        assertEq(vault.principalOf(alice), 0);
        assertEq(vault.depositWithMinShares(UNIT, alice, 1e18), 1e18);
        vm.stopPrank();
    }

    function test_SequentialDepositTransferRequestAndCancelInSameTransaction() public {
        _deposit(alice, 2 * UNIT);
        vm.prank(alice);
        vault.transfer(bob, 1e18);
        _request(bob, bob, 1e18);
        vm.prank(bob);
        vault.cancelRedeemRequest(0, bob);
        vault.fulfillCancel(bob);
        vm.prank(bob);
        vault.claimCancelRedeemRequest(0, bob, bob);
        assertEq(vault.principalOf(bob), UNIT);
        assertEq(vault.lockedPrincipalOf(bob), 0);
        assertEq(vault.totalOutstandingPrincipal(), 2 * UNIT);
    }

    function test_TwoCashflowClaimsInSameTransactionAndRetryAfterFailedPayment() public {
        bytes32 first = keccak256("first");
        bytes32 second = keccak256("second");
        vault.recordCashflow(first, _payment(alice, 0, 2 * UNIT, 0), 0);
        vm.warp(block.timestamp + 101);
        vault.recordCashflow(second, _payment(alice, 0, UNIT, 0), 0);
        asset.setFee(100);
        vm.prank(alice);
        vm.expectRevert(StructuredFundVault.NonExactAssetTransfer.selector);
        vault.claimCashflow(first, alice);
        assertFalse(vault.cashflow(first).claimed);
        assertEq(vault.reservedCashflows(), 3 * UNIT);
        asset.setFee(0);
        vm.startPrank(alice);
        assertEq(vault.claimCashflow(first, alice), 2 * UNIT);
        assertEq(vault.claimCashflow(second, alice), UNIT);
        vm.stopPrank();
        assertEq(vault.reservedCashflows(), 0);
    }

    function test_SeparateVaultsHaveIndependentTransientLocks() public {
        StructuredFundVault other = new StructuredFundVault(
            asset, policy, keccak256("other"), address(this), treasury, tax, 1000 * UNIT, "Other", "OTHER"
        );
        policy.setEligibility(address(asset), true, false);
        asset.setCallback(address(other), abi.encodeCall(other.reportCreditNAV, (0, 1, keccak256("zero nav"))), true);
        other.grantRole(other.VALUER_ROLE(), address(asset));
        _deposit(alice, UNIT);
        assertTrue(asset.callbackSucceeded());
        assertEq(other.navNonce(), 1);
        assertEq(other.totalAssets(), 0);
        assertEq(vault.totalAssets(), UNIT);
    }

    function test_FactoryConstructorCallbackEncountersGuardAndNextCreationWorks() public {
        StructuredFundFactory factory = new StructuredFundFactory(address(this));
        FactoryReentryAsset callbackAsset = new FactoryReentryAsset(factory);
        factory.grantRole(factory.CREATOR_ROLE(), address(callbackAsset));
        address created = factory.createVault(
            keccak256("fund"),
            keccak256("series"),
            0,
            callbackAsset,
            policy,
            address(this),
            treasury,
            tax,
            UNIT,
            "Callback vault",
            "CV"
        );
        assertEq(StructuredFundVault(created).decimals(), 18);
        address next = factory.createVault(
            keccak256("fund"), keccak256("series"), 1, asset, policy, address(this), treasury, tax, UNIT, "Next", "N"
        );
        assertNotEq(created, next);
    }

    function test_TransientGuardUsesLessGasThanPersistentGuard() public {
        PersistentGuardProbe persistent = new PersistentGuardProbe();
        TransientGuardProbe transientProbe = new TransientGuardProbe();
        // Warm the persistent status slot: even this favorable case must cost more than transient storage.
        persistent.guarded();
        uint256 persistentWarm = vm.snapshotGasLastFrame("guard", "persistent_warm");
        transientProbe.guarded();
        uint256 transientWarm = vm.snapshotGasLastFrame("guard", "transient_warm");
        assertLt(transientWarm, persistentWarm);
        emit log_named_uint("persistent_guard_execution_gas", persistentWarm);
        emit log_named_uint("transient_guard_execution_gas", transientWarm);
    }
}
