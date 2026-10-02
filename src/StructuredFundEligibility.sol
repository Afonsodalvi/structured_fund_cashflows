// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {IStructuredFundEligibility} from "./interfaces/IStructuredFundEligibility.sol";

/// @notice Reference allowlist/freeze policy. This is not a full ERC-3643 token.
contract StructuredFundEligibility is AccessControlDefaultAdminRules, IStructuredFundEligibility {
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");
    mapping(address => bool) public approved;
    mapping(address => bool) public frozen;
    event EligibilityUpdated(address indexed account, bool approved, bool frozen);

    constructor(address admin) AccessControlDefaultAdminRules(2 days, admin) {
        _grantRole(COMPLIANCE_ROLE, admin);
    }

    function setEligibility(address account, bool approved_, bool frozen_) external onlyRole(COMPLIANCE_ROLE) {
        approved[account] = approved_;
        frozen[account] = frozen_;
        emit EligibilityUpdated(account, approved_, frozen_);
    }

    function isEligible(address account) external view returns (bool) {
        return account != address(0) && approved[account] && !frozen[account];
    }
}
