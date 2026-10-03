// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.37;

/// @notice Candidate interface. No ERC number has been assigned.
/// @dev Every monetary amount uses asset() native units, never implicit WAD.
interface IStructuredFundCashflows {
    struct Cashflow {
        address beneficiary;
        uint256 principal;
        uint256 grossYield;
        uint256 withheld;
        uint64 periodStart;
        uint64 periodEnd;
        bytes32 evidenceHash;
        bool claimed;
    }

    event CashflowRecorded(
        bytes32 indexed cashflowId,
        bytes32 indexed scopeId,
        address indexed beneficiary,
        uint256 principal,
        uint256 grossYield,
        uint256 withheld,
        uint64 periodStart,
        uint64 periodEnd,
        bytes32 evidenceHash
    );
    event CashflowClaimed(
        bytes32 indexed cashflowId, address indexed beneficiary, address indexed receiver, uint256 netAssets
    );
    event PrincipalMoved(address indexed from, address indexed to, uint256 principal);
    event PrincipalRetired(address indexed controller, uint256 principal, uint256 shares);

    function scopeId() external view returns (bytes32);
    function principalOf(address account) external view returns (uint256);
    function lockedPrincipalOf(address controller) external view returns (uint256);
    function totalOutstandingPrincipal() external view returns (uint256);
    function cashflow(bytes32 cashflowId) external view returns (Cashflow memory);
    function claimCashflow(bytes32 cashflowId, address receiver) external returns (uint256 netAssets);
}
