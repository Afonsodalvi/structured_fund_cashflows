// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {Test} from "forge-std/Test.sol";
import {StructuredFundVault} from "../src/StructuredFundVault.sol";
import {StructuredFundEligibility} from "../src/StructuredFundEligibility.sol";
import {IStructuredFundCashflows} from "../src/interfaces/IStructuredFundCashflows.sol";
import {MockAsset} from "./mocks/MockAsset.sol";

abstract contract StructuredFundBase is Test {
    MockAsset internal asset;
    StructuredFundEligibility internal policy;
    StructuredFundVault internal vault;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA401);
    address internal outsider = address(0xBAD);
    address internal treasury = address(0x1111);
    address internal tax = address(0x2222);
    uint256 internal constant UNIT = 1e6;

    function setUp() public virtual {
        vm.warp(1_800_000_000);
        asset = new MockAsset(6);
        policy = new StructuredFundEligibility(address(this));
        vault = new StructuredFundVault(
            asset,
            policy,
            keccak256("FIDC:SERIES-A:SENIOR"),
            address(this),
            treasury,
            tax,
            1_000_000 * UNIT,
            "Structured Fund Cashflows Reference USD Senior",
            "sfcUSD-S"
        );
        address[4] memory accounts = [alice, bob, carol, address(this)];
        for (uint256 i; i < accounts.length; ++i) {
            policy.setEligibility(accounts[i], true, false);
            asset.mint(accounts[i], 10_000_000 * UNIT);
            vm.prank(accounts[i]);
            asset.approve(address(vault), type(uint256).max);
        }
    }

    function _deposit(address account, uint256 assets) internal returns (uint256 shares) {
        vm.prank(account);
        shares = vault.deposit(assets, account);
    }

    function _request(address owner, address controller, uint256 shares) internal {
        vm.prank(owner);
        assertEq(vault.requestRedeem(shares, controller, owner), 0);
    }

    function _payment(address beneficiary, uint256 p, uint256 y, uint256 w)
        internal
        view
        returns (IStructuredFundCashflows.Cashflow memory)
    {
        return IStructuredFundCashflows.Cashflow(
            beneficiary,
            p,
            y,
            w,
            uint64(block.timestamp - 100),
            uint64(block.timestamp),
            keccak256("settlement evidence"),
            false
        );
    }
}
