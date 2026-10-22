// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Mutually Assured Destruction (MAD)
/// @notice Fixed-supply ERC-20. The immediate deployer receives the entire supply.
/// @dev No administrative roles, transfer customizations, or public mint/burn functions.
contract MADToken is ERC20 {
    /// @notice One billion MAD, expressed in the token's 18-decimal base units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev A factory deployment credits the factory, which handles launch distribution.
    constructor() ERC20("Mutually Assured Destruction", "MAD") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
