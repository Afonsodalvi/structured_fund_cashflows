// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStructuredFundEligibility} from "./interfaces/IStructuredFundEligibility.sol";
import {StructuredFundVaultDeployer} from "./StructuredFundVaultDeployer.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

/// @notice Deterministic scope registry; no shared quota inventory or cross-class NAV.
contract StructuredFundFactory is AccessControlDefaultAdminRules, ReentrancyGuardTransient {
    bytes32 public constant CREATOR_ROLE = keccak256("CREATOR_ROLE");
    mapping(bytes32 => address) public vaultForScope;
    StructuredFundVaultDeployer public immutable deployer;
    error ScopeAlreadyExists();
    event VaultCreated(
        bytes32 indexed scopeId, bytes32 indexed fundId, bytes32 indexed seriesId, uint8 classId, address vault
    );

    constructor(address admin) AccessControlDefaultAdminRules(2 days, admin) {
        _grantRole(CREATOR_ROLE, admin);
        deployer = new StructuredFundVaultDeployer();
    }

    function computeScope(bytes32 fundId, bytes32 seriesId, uint8 classId) public view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, address(this), fundId, seriesId, classId));
    }

    function createVault(
        bytes32 fundId,
        bytes32 seriesId,
        uint8 classId,
        IERC20 asset_,
        IStructuredFundEligibility policy,
        address admin,
        address treasury,
        address taxReceiver,
        uint256 cap,
        string calldata name,
        string calldata symbol
    ) external onlyRole(CREATOR_ROLE) nonReentrant returns (address vault) {
        bytes32 scope = computeScope(fundId, seriesId, classId);
        if (vaultForScope[scope] != address(0)) revert ScopeAlreadyExists();
        bytes memory configuration = abi.encode(asset_, policy, scope, admin, treasury, taxReceiver, cap, name, symbol);
        vault = deployer.predictVault(scope, configuration);
        // Register the deterministic address before deployment; constructor failure rolls back the registry.
        vaultForScope[scope] = vault;
        vault = deployer.deployVault(scope, configuration);
        emit VaultCreated(scope, fundId, seriesId, classId, vault);
    }
}
