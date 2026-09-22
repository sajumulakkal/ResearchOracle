// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockUSDC
 * @notice Test-only USDC-style token for SVF integration testing.
 * Uses 6 decimals to match USDC behaviour.
 */
contract MockUSDC is ERC20, Ownable {
    uint256 public totalMinted;
    uint256 public totalBurned;

    event TokensMinted(
        address indexed account,
        uint256 amount
    );

    event TokensBurned(
        address indexed account,
        uint256 amount
    );

    error InvalidOwner();
    error InvalidAccount();
    error InvalidAmount();

    constructor(address initialOwner)
        ERC20("Mock USD Coin", "mUSDC")
    {
        if (initialOwner == address(0)) {
            revert InvalidOwner();
        }

        if (initialOwner != msg.sender) {
            transferOwnership(initialOwner);
        }

        uint256 initialSupply = 1000000000 * 10 ** 6;
        totalMinted = initialSupply;
        _mint(initialOwner, initialSupply);

        emit TokensMinted(
            initialOwner,
            initialSupply
        );
    }

    function decimals()
        public
        pure
        override
        returns (uint8)
    {
        return 6;
    }

    function mint(
        address account,
        uint256 amount
    )
        external
        onlyOwner
    {
        if (account == address(0)) {
            revert InvalidAccount();
        }

        if (amount == 0) {
            revert InvalidAmount();
        }

        totalMinted += amount;
        _mint(account, amount);

        emit TokensMinted(account, amount);
    }

    function burn(
        address account,
        uint256 amount
    )
        external
        onlyOwner
    {
        if (account == address(0)) {
            revert InvalidAccount();
        }

        if (amount == 0) {
            revert InvalidAmount();
        }

        totalBurned += amount;

        _burn(account, amount);

        emit TokensBurned(account, amount);
    }
}
