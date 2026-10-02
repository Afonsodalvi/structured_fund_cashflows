// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

/// @notice External eligibility boundary; an ERC-3643 identity adapter may implement it.
interface IStructuredFundEligibility {
    function isEligible(address account) external view returns (bool);
}
