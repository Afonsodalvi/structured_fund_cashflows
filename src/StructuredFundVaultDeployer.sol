// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {StructuredFundVault} from "./StructuredFundVault.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

/// @notice Isolates vault creation bytecode from the factory's role-management runtime.
contract StructuredFundVaultDeployer {
    address public immutable factory;
    error OnlyFactory();

    constructor() {
        factory = msg.sender;
    }

    function predictVault(bytes32 scope, bytes calldata configuration) external view returns (address) {
        return Create2.computeAddress(scope, keccak256(_creationCode(configuration)));
    }

    function deployVault(bytes32 scope, bytes calldata configuration) external returns (address) {
        if (msg.sender != factory) revert OnlyFactory();
        return Create2.deploy(0, scope, _creationCode(configuration));
    }

    function _creationCode(bytes calldata configuration) private pure returns (bytes memory) {
        return abi.encodePacked(type(StructuredFundVault).creationCode, configuration);
    }
}
