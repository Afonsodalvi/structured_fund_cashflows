// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockAsset is ERC20 {
    uint8 private immutable _decimals;
    uint256 public feeBps;
    address public callbackTarget;
    bytes public callbackData;
    bool public callbackSucceeded;
    bytes public callbackReturnData;
    bool public requireCallback;

    constructor(uint8 d) ERC20("Reference USD", "rUSD") {
        _decimals = d;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setFee(uint256 bps) external {
        feeBps = bps;
    }

    function setCallback(address target, bytes calldata data, bool required_) external {
        callbackTarget = target;
        callbackData = data;
        requireCallback = required_;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            if (callbackTarget != address(0)) {
                (bool ok, bytes memory result) = callbackTarget.call(callbackData);
                callbackSucceeded = ok;
                callbackReturnData = result;
                if (requireCallback) require(ok, "callback failed");
            }
            uint256 fee = value * feeBps / 10_000;
            if (fee != 0) {
                super._update(from, address(0), fee);
                value -= fee;
            }
        }
        super._update(from, to, value);
    }
}
