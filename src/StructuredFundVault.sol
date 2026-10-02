// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20, IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {
    AccessControlDefaultAdminRules
} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {IStructuredFundEligibility} from "./interfaces/IStructuredFundEligibility.sol";
import {IStructuredFundCashflows} from "./interfaces/IStructuredFundCashflows.sol";

/// @notice One immutable fund/series/class scope, synchronous entry and asynchronous exit.
/// @dev Reference candidate, not an upgrade implementation for the existing Diamond.
contract StructuredFundVault is
    ERC4626,
    AccessControlDefaultAdminRules,
    ReentrancyGuard,
    Pausable,
    IStructuredFundCashflows
{
    using SafeERC20 for IERC20;

    bytes32 public constant VALUER_ROLE = keccak256("VALUER_ROLE");
    bytes32 public constant SETTLER_ROLE = keccak256("SETTLER_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    uint256 public constant MAX_ASSETS = type(uint96).max;
    uint256 public constant MAX_SHARES = type(uint160).max;
    uint256 public constant MAX_CASHFLOW_BATCH = 64;
    bytes32 public immutable override scopeId;
    IStructuredFundEligibility public immutable eligibility;
    address public immutable treasury;
    address public immutable taxReceiver;
    uint256 public immutable assetCap;
    uint8 private immutable _offset;

    // Donations are excluded. Reserves are outside totalAssets and cannot be deployed.
    uint256 public managedCash;
    uint256 public creditNAV;
    uint256 public reservedRedemptions;
    uint256 public reservedCashflows;
    uint256 public totalEscrowedShares;
    uint256 public totalLockedPrincipal;
    uint256 public override totalOutstandingPrincipal;
    uint256 public navNonce;
    mapping(address => uint256) public override principalOf;
    mapping(address => mapping(address => bool)) public isOperator;
    mapping(bytes32 => Cashflow) private _cashflows;
    mapping(address => uint64) public lastCashflowPeriodEnd;

    struct RedeemState {
        uint256 pendingShares;
        uint256 lockedPrincipal;
        uint256 claimableShares;
        uint256 claimableAssets;
        bool cancelPending;
        uint256 cancelShares;
        uint256 cancelPrincipal;
    }
    mapping(address => RedeemState) public redeemState;
    bool private _escrowOperation;

    error InvalidConfiguration();
    error Ineligible(address account);
    error UnauthorizedController();
    error InvalidRequest();
    error ZeroAmount();
    error InsufficientLiquidity();
    error NonExactAssetTransfer();
    error InvalidCashflow();
    error InvalidCashflowBatch();
    error DirectEscrowTransfer();
    error AsyncPreview();
    error Slippage();

    event OperatorSet(address indexed controller, address indexed operator, bool approved);
    event RedeemRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address sender, uint256 shares
    );
    event RedeemFulfilled(address indexed controller, uint256 shares, uint256 assets, uint256 retiredPrincipal);
    event CancelRedeemRequest(address indexed controller, uint256 indexed requestId, address sender);
    event CancelRedeemClaim(
        address indexed controller, address indexed receiver, uint256 indexed requestId, address sender, uint256 shares
    );
    event CancelFulfilled(address indexed controller, uint256 shares);
    event CreditDeployed(uint256 assets, address indexed treasury);
    event CreditRepaid(uint256 assets);
    event CreditNAVReported(uint256 indexed nonce, uint256 oldNAV, uint256 newNAV, bytes32 evidenceHash);
    event CashflowNAVReleased(bytes32 indexed cashflowId, uint256 releasedNAV);

    constructor(
        IERC20 asset_,
        IStructuredFundEligibility eligibility_,
        bytes32 scope_,
        address admin,
        address treasury_,
        address taxReceiver_,
        uint256 cap_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) ERC4626(asset_) AccessControlDefaultAdminRules(2 days, admin) {
        if (
            address(asset_).code.length == 0 || address(eligibility_).code.length == 0 || scope_ == bytes32(0)
                || treasury_ == address(0) || taxReceiver_ == address(0) || treasury_ == address(this)
                || taxReceiver_ == address(this) || cap_ == 0 || cap_ > MAX_ASSETS
        ) revert InvalidConfiguration();
        uint8 d = IERC20Metadata(address(asset_)).decimals();
        if (d > 18) revert InvalidConfiguration();
        _offset = 18 - d;
        scopeId = scope_;
        eligibility = eligibility_;
        treasury = treasury_;
        taxReceiver = taxReceiver_;
        assetCap = cap_;
        _grantRole(VALUER_ROLE, admin);
        _grantRole(SETTLER_ROLE, admin);
        _grantRole(TREASURY_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    function _decimalsOffset() internal view override returns (uint8) {
        return _offset;
    }

    function totalAssets() public view override returns (uint256) {
        return managedCash + creditNAV;
    }

    function share() external view returns (address) {
        return address(this);
    }

    /// @notice ERC-7575 share-to-vault discovery for this single-asset share token.
    function vault(address asset_) external view returns (address) {
        return asset_ == asset() ? address(this) : address(0);
    }

    function lockedPrincipalOf(address controller) external view override returns (uint256) {
        RedeemState storage r = redeemState[controller];
        return r.lockedPrincipal + r.cancelPrincipal;
    }

    function supportsInterface(bytes4 id) public view override returns (bool) {
        return id == 0xe3bc4e65 || id == 0x2f0a18c5 || id == 0xf815c03d || id == 0x620ee8e4 || id == 0xe76cffc7
            || id == type(IStructuredFundCashflows).interfaceId || super.supportsInterface(id);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // Views fail closed if an external eligibility service is unavailable.
    function _eligible(address account) internal view returns (bool) {
        if (account == address(0) || account == address(this)) return false;
        try eligibility.isEligible(account) returns (bool ok) {
            return ok;
        } catch {
            return false;
        }
    }

    function _checkEligible(address account) internal view {
        if (!_eligible(account)) revert Ineligible(account);
    }

    function maxDeposit(address receiver) public view override returns (uint256) {
        if (paused() || !_eligible(receiver)) return 0;
        uint256 nav = totalAssets();
        if (nav >= assetCap || totalSupply() >= MAX_SHARES) return 0;
        // Both factors have bounded widths (160 + 96), avoiding limit-view overflow.
        uint256 shareHeadroomAssets = _convertToAssets(MAX_SHARES - totalSupply(), Math.Rounding.Floor);
        return Math.min(assetCap - nav, shareHeadroomAssets);
    }

    function maxMint(address receiver) public view override returns (uint256) {
        return Math.min(MAX_SHARES - totalSupply(), convertToShares(maxDeposit(receiver)));
    }

    function maxRedeem(address controller) public view override returns (uint256) {
        return paused() || !_eligible(controller) ? 0 : redeemState[controller].claimableShares;
    }

    function maxWithdraw(address controller) public view override returns (uint256) {
        return paused() || !_eligible(controller) ? 0 : redeemState[controller].claimableAssets;
    }

    function previewRedeem(uint256) public pure override returns (uint256) {
        revert AsyncPreview();
    }

    function previewWithdraw(uint256) public pure override returns (uint256) {
        revert AsyncPreview();
    }

    function deposit(uint256 assets, address receiver) public override nonReentrant whenNotPaused returns (uint256) {
        _checkEligible(msg.sender);
        if (assets == 0) revert ZeroAmount();
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public override nonReentrant whenNotPaused returns (uint256) {
        _checkEligible(msg.sender);
        if (shares == 0) revert ZeroAmount();
        return super.mint(shares, receiver);
    }

    /// @notice ERC-7540 overload; entry remains synchronous and is funded by controller.
    function deposit(uint256 assets, address receiver, address controller)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        _authorize(controller);
        _checkEligible(controller);
        if (assets == 0) revert ZeroAmount();
        uint256 limit = maxDeposit(receiver);
        if (assets > limit) revert ERC4626ExceededMaxDeposit(receiver, assets, limit);
        shares = previewDeposit(assets);
        _deposit(controller, receiver, assets, shares);
    }

    /// @notice Operator approval does not replace the asset allowance to this vault.
    function mint(uint256 shares, address receiver, address controller)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        _authorize(controller);
        _checkEligible(controller);
        if (shares == 0) revert ZeroAmount();
        uint256 limit = maxMint(receiver);
        if (shares > limit) revert ERC4626ExceededMaxMint(receiver, shares, limit);
        assets = previewMint(shares);
        _deposit(controller, receiver, assets, shares);
    }

    function depositWithMinShares(uint256 assets, address receiver, uint256 minShares)
        external
        returns (uint256 shares)
    {
        shares = deposit(assets, receiver);
        if (shares < minShares) revert Slippage();
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        if (shares == 0) revert ZeroAmount();
        _pullExact(caller, assets);
        managedCash += assets;
        principalOf[receiver] += assets;
        totalOutstandingPrincipal += assets;
        _mint(receiver, shares);
        emit Deposit(caller, receiver, assets, shares);
    }

    function transfer(address to, uint256 amount) public override(ERC20, IERC20) nonReentrant returns (bool) {
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount)
        public
        override(ERC20, IERC20)
        nonReentrant
        returns (bool)
    {
        return super.transferFrom(from, to, amount);
    }

    function _update(address from, address to, uint256 shares) internal override {
        if (!_escrowOperation) {
            _requireNotPaused();
            if (from == address(this) || to == address(this)) revert DirectEscrowTransfer();
            if (from != address(0)) _checkEligible(from);
            if (to != address(0)) _checkEligible(to);
            if (from != address(0) && to != address(0) && from != to) {
                uint256 p = _principalForShares(from, shares);
                principalOf[from] -= p;
                principalOf[to] += p;
                emit PrincipalMoved(from, to, p);
            }
        }
        super._update(from, to, shares);
    }

    function _principalForShares(address owner, uint256 shares) internal view returns (uint256) {
        uint256 balance = balanceOf(owner);
        if (shares > balance) revert InvalidRequest();
        if (shares == balance) return principalOf[owner];
        return Math.mulDiv(principalOf[owner], shares, balance);
    }

    function setOperator(address operator, bool approved) external returns (bool) {
        if (operator == address(0) || operator == msg.sender) revert InvalidRequest();
        isOperator[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
        return true;
    }

    function _authorize(address controller) internal view {
        if (msg.sender != controller && !isOperator[controller][msg.sender]) revert UnauthorizedController();
    }

    function requestRedeem(uint256 shares, address controller, address owner)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 requestId)
    {
        if (shares == 0) revert ZeroAmount();
        _checkEligible(owner);
        _checkEligible(controller);
        if (msg.sender != owner && !isOperator[owner][msg.sender]) _spendAllowance(owner, msg.sender, shares);
        RedeemState storage r = redeemState[controller];
        if (r.cancelPending || r.cancelShares != 0) revert InvalidRequest();
        uint256 p = _principalForShares(owner, shares);
        principalOf[owner] -= p;
        r.pendingShares += shares;
        r.lockedPrincipal += p;
        totalEscrowedShares += shares;
        totalLockedPrincipal += p;
        _escrowOperation = true;
        _transfer(owner, address(this), shares);
        _escrowOperation = false;
        emit RedeemRequest(controller, owner, 0, msg.sender, shares);
        return 0;
    }

    function pendingRedeemRequest(uint256 id, address controller) external view returns (uint256) {
        return id == 0 ? redeemState[controller].pendingShares : 0;
    }

    function claimableRedeemRequest(uint256 id, address controller) external view returns (uint256) {
        return id == 0 ? redeemState[controller].claimableShares : 0;
    }

    function fulfillRedeem(address controller) external onlyRole(SETTLER_ROLE) nonReentrant whenNotPaused {
        RedeemState storage r = redeemState[controller];
        uint256 shares = r.pendingShares;
        if (shares == 0 || r.cancelPending) revert InvalidRequest();
        uint256 assets = convertToAssets(shares);
        if (assets > managedCash) revert InsufficientLiquidity();
        uint256 p = r.lockedPrincipal;
        r.pendingShares = 0;
        r.lockedPrincipal = 0;
        r.claimableShares += shares;
        r.claimableAssets += assets;
        managedCash -= assets;
        reservedRedemptions += assets;
        totalEscrowedShares -= shares;
        totalLockedPrincipal -= p;
        totalOutstandingPrincipal -= p;
        _escrowOperation = true;
        _burn(address(this), shares);
        _escrowOperation = false;
        emit RedeemFulfilled(controller, shares, assets, p);
        emit PrincipalRetired(controller, p, shares);
    }

    function redeem(uint256 shares, address receiver, address controller)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        _authorize(controller);
        _checkEligible(controller);
        _checkEligible(receiver);
        RedeemState storage r = redeemState[controller];
        if (shares == 0 || shares > r.claimableShares) revert InvalidRequest();
        assets =
            shares == r.claimableShares ? r.claimableAssets : Math.mulDiv(shares, r.claimableAssets, r.claimableShares);
        _claimRedeem(r, shares, assets, receiver, controller);
    }

    function withdraw(uint256 assets, address receiver, address controller)
        public
        override
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        _authorize(controller);
        _checkEligible(controller);
        _checkEligible(receiver);
        RedeemState storage r = redeemState[controller];
        if (assets == 0 || assets > r.claimableAssets) revert InvalidRequest();
        shares = assets == r.claimableAssets
            ? r.claimableShares
            : Math.mulDiv(assets, r.claimableShares, r.claimableAssets, Math.Rounding.Ceil);
        // If a partial assets claim rounds to every share, require a redeem of all rights instead.
        if (shares == r.claimableShares && assets != r.claimableAssets) revert InvalidRequest();
        _claimRedeem(r, shares, assets, receiver, controller);
    }

    function _claimRedeem(RedeemState storage r, uint256 shares, uint256 assets, address receiver, address controller)
        private
    {
        r.claimableShares -= shares;
        r.claimableAssets -= assets;
        reservedRedemptions -= assets;
        _pushExact(receiver, assets);
        emit Withdraw(msg.sender, receiver, controller, assets, shares);
    }

    function cancelRedeemRequest(uint256 id, address controller) external nonReentrant {
        _authorize(controller);
        RedeemState storage r = redeemState[controller];
        if (id != 0 || r.pendingShares == 0 || r.cancelPending) revert InvalidRequest();
        r.cancelPending = true;
        emit CancelRedeemRequest(controller, 0, msg.sender);
    }

    function fulfillCancel(address controller) external onlyRole(SETTLER_ROLE) nonReentrant {
        RedeemState storage r = redeemState[controller];
        if (!r.cancelPending) revert InvalidRequest();
        r.cancelPending = false;
        r.cancelShares += r.pendingShares;
        r.cancelPrincipal += r.lockedPrincipal;
        r.pendingShares = 0;
        r.lockedPrincipal = 0;
        emit CancelFulfilled(controller, r.cancelShares);
    }

    function pendingCancelRedeemRequest(uint256 id, address controller) external view returns (bool) {
        return id == 0 && redeemState[controller].cancelPending;
    }

    function claimableCancelRedeemRequest(uint256 id, address controller) external view returns (uint256) {
        return id == 0 ? redeemState[controller].cancelShares : 0;
    }

    function claimCancelRedeemRequest(uint256 id, address receiver, address controller) external nonReentrant {
        _authorize(controller);
        _checkEligible(controller);
        _checkEligible(receiver);
        RedeemState storage r = redeemState[controller];
        uint256 shares = r.cancelShares;
        uint256 p = r.cancelPrincipal;
        if (id != 0 || shares == 0) revert InvalidRequest();
        r.cancelShares = 0;
        r.cancelPrincipal = 0;
        totalEscrowedShares -= shares;
        totalLockedPrincipal -= p;
        principalOf[receiver] += p;
        _escrowOperation = true;
        _transfer(address(this), receiver, shares);
        _escrowOperation = false;
        emit CancelRedeemClaim(controller, receiver, 0, msg.sender, shares);
    }

    function deployCredit(uint256 assets) external onlyRole(TREASURY_ROLE) nonReentrant whenNotPaused {
        if (assets == 0 || assets > managedCash) revert InsufficientLiquidity();
        managedCash -= assets;
        creditNAV += assets;
        _pushExact(treasury, assets);
        emit CreditDeployed(assets, treasury);
    }

    function repayCredit(uint256 assets) external onlyRole(SETTLER_ROLE) nonReentrant {
        if (assets == 0 || assets > creditNAV) revert InvalidRequest();
        creditNAV -= assets;
        managedCash += assets;
        _pullExact(msg.sender, assets);
        emit CreditRepaid(assets);
    }

    function reportCreditNAV(uint256 value, uint256 nonce, bytes32 evidenceHash)
        external
        onlyRole(VALUER_ROLE)
        nonReentrant
        whenNotPaused
    {
        if (nonce != navNonce + 1 || evidenceHash == bytes32(0) || value > assetCap - managedCash) revert InvalidRequest();
        // No phantom credit in an empty vault. Valuation is a trusted administrative assertion.
        if (totalSupply() == 0 && value != 0) revert InvalidRequest();
        uint256 old = creditNAV;
        creditNAV = value;
        navNonce = nonce;
        emit CreditNAVReported(nonce, old, value, evidenceHash);
    }

    function cashflow(bytes32 id) external view override returns (Cashflow memory) {
        return _cashflows[id];
    }

    function recordCashflow(bytes32 id, Cashflow calldata payment, uint256 navRelease)
        external
        onlyRole(SETTLER_ROLE)
        nonReentrant
        whenNotPaused
    {
        _recordCashflow(id, payment, navRelease);
    }

    /// @notice Book all beneficiaries of a bounded distribution atomically.
    /// @dev Entitlement allocation remains the settler's responsibility. No holder enumeration is inferred.
    function recordCashflowBatch(bytes32[] calldata ids, Cashflow[] calldata payments, uint256[] calldata navReleases)
        external
        onlyRole(SETTLER_ROLE)
        nonReentrant
        whenNotPaused
    {
        uint256 length = ids.length;
        if (length == 0 || length > MAX_CASHFLOW_BATCH || length != payments.length || length != navReleases.length) {
            revert InvalidCashflowBatch();
        }
        for (uint256 i; i < length; ++i) {
            _recordCashflow(ids[i], payments[i], navReleases[i]);
        }
    }

    function _recordCashflow(bytes32 id, Cashflow calldata payment, uint256 navRelease) private {
        if (
            id == bytes32(0) || _cashflows[id].beneficiary != address(0) || payment.claimed
                || payment.evidenceHash == bytes32(0) || payment.periodStart >= payment.periodEnd
                || payment.periodEnd > block.timestamp
                || payment.periodStart < lastCashflowPeriodEnd[payment.beneficiary]
                || payment.withheld > payment.grossYield || payment.principal > principalOf[payment.beneficiary]
                || navRelease < payment.principal || navRelease > creditNAV
                || navRelease > payment.principal + payment.grossYield || payment.principal + payment.grossYield == 0
        ) revert InvalidCashflow();
        _checkEligible(payment.beneficiary);
        uint256 gross = payment.principal + payment.grossYield;
        if (gross > MAX_ASSETS) revert InvalidCashflow();
        _cashflows[id] = payment;
        lastCashflowPeriodEnd[payment.beneficiary] = payment.periodEnd;
        principalOf[payment.beneficiary] -= payment.principal;
        totalOutstandingPrincipal -= payment.principal;
        // Release any yield already recognized in NAV as well as principal. Yield not previously
        // recognized is funded directly into reserves. The settler attests the accounting bridge.
        creditNAV -= navRelease;
        reservedCashflows += gross - payment.withheld;
        _pullExact(msg.sender, gross);
        // Withholding is transferred atomically to a designated recipient, never retained as NAV.
        _pushExact(taxReceiver, payment.withheld);
        emit CashflowRecorded(
            id,
            scopeId,
            payment.beneficiary,
            payment.principal,
            payment.grossYield,
            payment.withheld,
            payment.periodStart,
            payment.periodEnd,
            payment.evidenceHash
        );
        emit CashflowNAVReleased(id, navRelease);
    }

    function claimCashflow(bytes32 id, address receiver) external override nonReentrant returns (uint256 netAssets) {
        Cashflow storage p = _cashflows[id];
        _authorize(p.beneficiary);
        _checkEligible(p.beneficiary);
        _checkEligible(receiver);
        if (p.claimed || p.beneficiary == address(0)) revert InvalidCashflow();
        p.claimed = true;
        netAssets = p.principal + p.grossYield - p.withheld;
        reservedCashflows -= netAssets;
        _pushExact(receiver, netAssets);
        emit CashflowClaimed(id, p.beneficiary, receiver, netAssets);
    }

    function _pullExact(address from, uint256 assets) private {
        IERC20 token = IERC20(asset());
        uint256 beforeBalance = token.balanceOf(address(this));
        uint256 beforeSender = token.balanceOf(from);
        token.safeTransferFrom(from, address(this), assets);
        if (token.balanceOf(address(this)) != beforeBalance + assets || token.balanceOf(from) + assets != beforeSender)
        {
            revert NonExactAssetTransfer();
        }
    }

    function _pushExact(address to, uint256 assets) private {
        if (assets == 0) return;
        IERC20 token = IERC20(asset());
        uint256 beforeVault = token.balanceOf(address(this));
        uint256 beforeReceiver = token.balanceOf(to);
        token.safeTransfer(to, assets);
        if (token.balanceOf(address(this)) + assets != beforeVault || token.balanceOf(to) != beforeReceiver + assets) {
            revert NonExactAssetTransfer();
        }
    }
}
