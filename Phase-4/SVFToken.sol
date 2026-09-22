
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title SVFToken
 * @notice Smart Value Fund ownership token for the Phase 4 tokenized fund layer[cite: 1]
 *
 * Features:
 * - ERC20 transferable fund shares[cite: 1]
 * - FundVault-only minting and burning[cite: 1]
 * - Configurable and lockable FundVault[cite: 1]
 * - Emergency pause for transfers, minting, and burning[cite: 1]
 * - Global and investor-level mint/burn accounting[cite: 1]
 * - Ownership calculations in basis points[cite: 1]
 * - OpenZeppelin 4.x compatibility[cite: 1]
 */
contract SVFToken is ERC20, Ownable, Pausable {
    uint256 public constant BASIS_POINTS = 10000;[cite: 1]

    address public fundVault;[cite: 1]
    bool public fundVaultLocked;[cite: 1]

    uint256 public immutable deploymentTimestamp;[cite: 1]

    uint256 public totalMinted;[cite: 1]
    uint256 public totalBurned;[cite: 1]
    uint256 public lastMintTimestamp;[cite: 1]
    uint256 public lastBurnTimestamp;[cite: 1]

    mapping(address => uint256) public lifetimeMinted;[cite: 1]
    mapping(address => uint256) public lifetimeBurned;[cite: 1]

    event FundVaultUpdated(
        address indexed oldVault,
        address indexed newvault,
        uint256 updatedAt
    );[cite: 1, 2]

    event FundVaultLocked(
        address indexed vault,
        uint256 lockedAt
    );[cite: 2]

    event SharesMinted(
        address indexed investor,
        uint256 amount,
        uint256 mintedAt
    );[cite: 2]

    event SharesBurned(
        address indexed investor,
        uint256 amount,
        uint256 burnedAt
    );[cite: 2]

    event TokenPaused(
        address indexed account,
        uint256 pausedAt
    );[cite: 2]

    event TokenResumed(
        address indexed account,
        uint256 resumedAt
    );[cite: 2]

    error InvalidOwner();[cite: 2]
    error InvalidVault();[cite: 2]
    error InvalidInvestor();[cite: 2]
    error InvalidAmount();[cite: 2]
    error VaultAlreadySet();[cite: 2]
    error VaultNotConfigured();[cite: 2, 3]
    error VaultConfigurationLocked();[cite: 2, 4]
    error OnlyFundVault();[cite: 3]
    error TokenAlreadyPaused();[cite: 3, 10]
    error TokenNotPaused();[cite: 3, 10]

    modifier onlyFundVault() {
        if (fundVault == address(0)) {
            revert VaultNotConfigured();
        }

        if (msg.sender != fundVault) {
            revert OnlyFundVault();
        }

        _;
    }

    constructor(address initialOwner)
        ERC20("Smart Value Fund", "SVF")
    {
        if (initialOwner == address(0)) {
            revert InvalidOwner();
        }

        if (initialOwner != msg.sender) {
            transferOwnership(initialOwner);
        }

        deploymentTimestamp = block.timestamp;
    }

    /**
     * @notice Set or replace the authorized FundVault.
     * @dev The owner can update the vault until lockFundVault() is called.
     */
    function setFundVault(address newVault)
        external
        onlyOwner
        whenNotPaused
    {
        if (fundVaultLocked) {
            revert VaultConfigurationLocked();
        }

        if (newVault == address(0)) {
            revert InvalidVault();
        }

        if (newVault.code.length == 0) {
            revert InvalidVault();
        }

        if (newVault == fundVault) {
            revert VaultAlreadySet();
        }

        address oldVault = fundVault;
        fundVault = newVault;

        emit FundVaultUpdated(
            oldVault,
            newVault,
            block.timestamp
        );
    }

    /**
     * @notice Permanently lock the current FundVault configuration.
     * @dev This action cannot be reversed.
     */
    function lockFundVault()
        external
        onlyOwner
        whenNotPaused
    {
        if (fundVaultLocked) {
            revert VaultConfigurationLocked();
        }

        if (fundVault == address(0)) {
            revert VaultNotConfigured();
        }

        fundVaultLocked = true;

        emit FundVaultLocked(
            fundVault,
            block.timestamp
        );
    }

    /**
     * @notice Mint fund shares to an investor.
     * @dev Only the configured FundVault can mint.
     */
    function mint(
        address investor,
        uint256 amount
    )
        external
        onlyFundVault
        whenNotPaused
    {
        if (investor == address(0)) {
            revert InvalidInvestor();
        }

        if (amount == 0) {
            revert InvalidAmount();
        }

        totalMinted += amount;
        lifetimeMinted[investor] += amount;
        lastMintTimestamp = block.timestamp;

        _mint(investor, amount);

        emit SharesMinted(
            investor,
            amount,
            block.timestamp
        );
    }

    /**
     * @notice Burn fund shares from an investor.
     * @dev Only the configured FundVault can burn.
     */
    function burn(
        address investor,
        uint256 amount
    )
        external
        onlyFundVault
        whenNotPaused
    {
        if (investor == address(0)) {
            revert InvalidInvestor();
        }

        if (amount == 0) {
            revert InvalidAmount();
        }

        if (balanceOf(investor) < amount) {
            revert InvalidAmount();
        }

        totalBurned += amount;
        lifetimeBurned[investor] += amount;
        lastBurnTimestamp = block.timestamp;

        _burn(investor, amount);

        emit SharesBurned(
            investor,
            amount,
            block.timestamp
        );
    }

    /**
     * @notice Return currently outstanding fund shares.
     */
    function totalActiveShares()
        external
        view
        returns (uint256)
    {
        return totalSupply();
    }

    /**
     * @notice Return currently outstanding fund shares.
     */
    function circulatingSupply()
        external
        view
        returns (uint256)
    {
        return totalSupply();
    }

    /**
     * @notice Return net shares issued from cumulative accounting.
     */
    function netSharesIssued()
        external
        view
        returns (uint256)
    {
        return totalMinted - totalBurned;
    }

    /**
     * @notice Return investor ownership in basis points.
     * @dev 10000 basis points equals 100 percent.
     */
    function ownershipBps(address investor)
        external
        view
        returns (uint256)
    {
        uint256 supply = totalSupply();

        if (supply == 0) {
            return 0;
        }

        return (balanceOf(investor) * BASIS_POINTS) / supply;
    }

    /**
     * @notice Return an investor's lifetime mint/burn activity.
     */
    function investorShareActivity(address investor)
        external
        view
        returns (
            uint256 minted,
            uint256 burned,
            uint256 currentBalance
        )
    {
        return (
            lifetimeMinted[investor],
            lifetimeBurned[investor],
            balanceOf(investor)
        );
    }

    /**
     * @notice Pause transfers, minting, burning, and vault reconfiguration.
     */
    function pause()
        external
        onlyOwner
    {
        if (paused()) {
            revert TokenAlreadyPaused();
        }

        _pause();

        emit TokenPaused(
            msg.sender,
            block.timestamp
        );
    }

    /**
     * @notice Resume token operations.
     */
    function unpause()
        external
        onlyOwner
    {
        if (!paused()) {
            revert TokenNotPaused();
        }

        _unpause();

        emit TokenResumed(
            msg.sender,
            block.timestamp
        );
    }

    /**
     * @dev OpenZeppelin 4.x ERC20 transfer hook.
     * @notice Blocks regular transfers, minting, and burning while paused.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    )
        internal
        virtual
        override(ERC20, Pausable)
    {
        super._beforeTokenTransfer(
            from,
            to,
            amount
        );

        require(
            !paused(),
            "SVFToken: token transfer while paused"
        );
    }
}
