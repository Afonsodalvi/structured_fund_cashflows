// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {StructuredFundBase} from "../Base.t.sol";
import {StructuredFundFactory} from "../../src/StructuredFundFactory.sol";
import {StructuredFundVault} from "../../src/StructuredFundVault.sol";
import {StructuredFundVaultDeployer} from "../../src/StructuredFundVaultDeployer.sol";

contract StructuredFundFactoryTest is StructuredFundBase {
    function test_DeployerIsBoundToFactoryAndRejectsDirectCalls() public {
        StructuredFundFactory f = new StructuredFundFactory(address(this));
        StructuredFundVaultDeployer d = f.deployer();
        assertEq(d.factory(), address(f));
        vm.expectRevert(StructuredFundVaultDeployer.OnlyFactory.selector);
        d.deployVault(keccak256("scope"), "");
    }

    function test_FailedDeploymentDoesNotConsumeScope() public {
        StructuredFundFactory f = new StructuredFundFactory(address(this));
        bytes32 fund = keccak256("fund");
        bytes32 series = keccak256("series");
        bytes32 scope = f.computeScope(fund, series, 0);
        vm.expectRevert(StructuredFundVault.InvalidConfiguration.selector);
        f.createVault(fund, series, 0, asset, policy, alice, treasury, tax, 0, "SFC rUSD", "sfcUSD");
        assertEq(f.vaultForScope(scope), address(0));
        address created =
            f.createVault(fund, series, 0, asset, policy, alice, treasury, tax, UNIT, "SFC rUSD", "sfcUSD");
        assertEq(
            created,
            f.deployer()
                .predictVault(scope, abi.encode(asset, policy, scope, alice, treasury, tax, UNIT, "SFC rUSD", "sfcUSD"))
        );
        assertEq(f.vaultForScope(scope), created);
        assertEq(StructuredFundVault(created).defaultAdmin(), alice);
    }

    function test_FactoryScopesIncludeSeriesAndClass() public {
        StructuredFundFactory f = new StructuredFundFactory(address(this));
        bytes32 fund = keccak256("fund");
        bytes32 series = keccak256("series");
        address a = f.createVault(
            fund,
            series,
            0,
            asset,
            policy,
            address(this),
            treasury,
            tax,
            1000 * UNIT,
            "Structured Fund Cashflows rUSD S",
            "sfcUSD-S"
        );
        address b = f.createVault(
            fund,
            series,
            1,
            asset,
            policy,
            address(this),
            treasury,
            tax,
            1000 * UNIT,
            "Structured Fund Cashflows rUSD M",
            "sfcUSD-M"
        );
        address c = f.createVault(
            fund,
            keccak256("series2"),
            0,
            asset,
            policy,
            address(this),
            treasury,
            tax,
            1000 * UNIT,
            "Structured Fund Cashflows rUSD S2",
            "sfcUSD-S2"
        );
        assertNotEq(a, b);
        assertNotEq(a, c);
        assertNotEq(StructuredFundVault(a).scopeId(), StructuredFundVault(b).scopeId());
        vm.startPrank(alice);
        asset.approve(a, type(uint256).max);
        StructuredFundVault(a).deposit(100 * UNIT, alice);
        vm.stopPrank();
        assertEq(StructuredFundVault(b).totalAssets(), 0);
        assertEq(StructuredFundVault(c).totalAssets(), 0);
        assertEq(f.vaultForScope(f.computeScope(fund, series, 0)), a);
        vm.expectRevert(StructuredFundFactory.ScopeAlreadyExists.selector);
        f.createVault(
            fund,
            series,
            0,
            asset,
            policy,
            address(this),
            treasury,
            tax,
            1000 * UNIT,
            "Structured Fund Cashflows rUSD",
            "sfcUSD"
        );
    }

    function test_FactoryCreationRequiresRole() public {
        StructuredFundFactory f = new StructuredFundFactory(address(this));
        vm.prank(outsider);
        vm.expectRevert();
        f.createVault(
            keccak256("f"),
            keccak256("s"),
            0,
            asset,
            policy,
            alice,
            treasury,
            tax,
            UNIT,
            "Structured Fund Cashflows rUSD",
            "sfcUSD"
        );
    }

    function test_FactoryScopeIsChainAndFactoryBound() public {
        StructuredFundFactory f = new StructuredFundFactory(address(this));
        StructuredFundFactory g = new StructuredFundFactory(address(this));
        bytes32 x = f.computeScope(keccak256("f"), keccak256("s"), 0);
        assertNotEq(x, g.computeScope(keccak256("f"), keccak256("s"), 0));
        vm.chainId(block.chainid + 1);
        assertNotEq(x, f.computeScope(keccak256("f"), keccak256("s"), 0));
    }
}
