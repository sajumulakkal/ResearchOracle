// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IFundVaultSubscription {
    function settlementAsset() external view returns (address);
    function svfToken() external view returns (address);
    function subscribe(uint256 assetAmount) external returns (uint256 shareAmount);
    function previewSubscription(uint256 assetAmount) external view returns (uint256 shareAmount);
}

interface IFundRegistrySubscription {
    function isActive() external view returns (bool);
    function fundVault() external view returns (address);
    function svfToken() external view returns (address);
}

/**
 * @title SubscriptionManager
 * @notice Phase 4 subscription entry point for Smart Value Fund.
 *
 * Flow:
 * 1. Investor approves settlement assets to SubscriptionManager.
 * 2. SubscriptionManager transfers the assets from the investor.
 * 3. SubscriptionManager approves FundVault.
 * 4. FundVault receives the assets.
 * 5. FundVault mints SVF shares to SubscriptionManager.
 * 6. SubscriptionManager transfers the SVF shares to the investor.
 */[cite: 10]

contract SubscriptionManager is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable settlementAsset;
    IERC20 public immutable svfToken;

    IFundVaultSubscription public immutable fundVault;
    IFundRegistrySubscription public immutable fundRegistry;

    uint256 public minimumSubscriptionAmount;

    uint256 public totalSubscriptionCount;
    uint256 public totalAssetsSubscribed;
    uint256 public totalSharesIssued;

    mapping(address => uint256) public investorAssetsSubscribed;
    mapping(address => uint256) public investorSharesIssued;
    mapping(address => uint256) public investorSubscriptionCount;

    struct SubscriptionRecord {
        uint256 subscriptionId;
        address investor;
        uint256 assetAmount;
        uint256 shareAmount;
        uint256 subscribedAt;
    }

    mapping(uint256 => SubscriptionRecord) private subscriptionRecords;

    event SubscriptionCompleted(
        uint256 indexed subscriptionId,
        address indexed investor,
        uint256 assetAmount,
        uint256 shareAmount,
        uint256 subscribedAt
    );[cite: 1]

    event MinimumSubscriptionAmountUpdated(
        uint256 previousAmount,
        uint256 newAmount
    );

    event FundRegistryUpdated(
        address indexed previousRegistry,
        address indexed newRegistry
    );

    error InvalidAddress();
    error InvalidAmount();
    error BelowMinimumSubscription();
    error MinimumSharesNotMet();
    error FundNotActive();
    error RegistryVaultMismatch();
    error RegistryTokenMismatch();
    error VaultAssetMismatch();
    error VaultTokenMismatch();
    error AssetTransferMismatch();
    error ShareMintMismatch();
    error SubscriptionNotFound();
    error DirectRecoveryNotAllowed();

    constructor(
        address initialOwner,
        address settlementAssetAddress,
        address svfTokenAddress,
        address fundVaultAddress,
        uint256 initialMinimumSubscription
    ) {
        if (
            initialOwner == address(0) ||
            settlementAssetAddress == address(0) ||
            svfTokenAddress == address(0) ||
            fundVaultAddress == address(0)
        ) {
            revert InvalidAddress();
        }[cite: 2]

        if (initialOwner != msg.sender) {
            transferOwnership(initialOwner);
        }

        IFundVaultSubscription vault = IFundVaultSubscription(fundVaultAddress);

        if (vault.settlementAsset() != settlementAssetAddress) {
            revert VaultAssetMismatch();
        }

        if (vault.svfToken() != svfTokenAddress) {
            revert VaultTokenMismatch();
        }

        settlementAsset = IERC20(settlementAssetAddress);
        svfToken = IERC20(svfTokenAddress);
        fundVault = vault;
        minimumSubscriptionAmount = initialMinimumSubscription;
    }

    function subscribe(
        uint256 assetAmount,
        uint256 minimumShares
    )
        external
        nonReentrant
        whenNotPaused
        returns (uint256 subscriptionId, uint256 shareAmount)
    {
        if (assetAmount == 0) {
            revert InvalidAmount();
        }

        if (assetAmount < minimumSubscriptionAmount) {
            revert BelowMinimumSubscription();
        }[cite: 3]

        _validateFundConfiguration();

        uint256 previewedShares = fundVault.previewSubscription(assetAmount);

        if (previewedShares == 0) {
            revert InvalidAmount();
        }

        if (previewedShares < minimumShares) {
            revert MinimumSharesNotMet();
        }

        uint256 managerAssetBalanceBefore = settlementAsset.balanceOf(address(this));

        settlementAsset.safeTransferFrom(
            msg.sender,
            address(this),
            assetAmount
        );

        uint256 managerAssetBalanceAfter = settlementAsset.balanceOf(address(this));

        if (managerAssetBalanceAfter - managerAssetBalanceBefore != assetAmount) {
            revert AssetTransferMismatch();
        }

        uint256 vaultAssetBalanceBefore = settlementAsset.balanceOf(address(fundVault));
        uint256 managerShareBalanceBefore = svfToken.balanceOf(address(this));

        settlementAsset.safeApprove(address(fundVault), 0);
        settlementAsset.safeApprove(address(fundVault), assetAmount);

        uint256 returnedShareAmount = fundVault.subscribe(assetAmount);

        settlementAsset.safeApprove(address(fundVault), 0);

        uint256 vaultAssetBalanceAfter = settlementAsset.balanceOf(address(fundVault));[cite: 4]

        if (vaultAssetBalanceAfter - vaultAssetBalanceBefore != assetAmount) {
            revert AssetTransferMismatch();
        }

        uint256 managerShareBalanceAfter = svfToken.balanceOf(address(this));
        shareAmount = managerShareBalanceAfter - managerShareBalanceBefore;

        if (
            shareAmount == 0 ||
            shareAmount != returnedShareAmount ||
            shareAmount != previewedShares
        ) {
            revert ShareMintMismatch();
        }

        if (shareAmount < minimumShares) {
            revert MinimumSharesNotMet();
        }

        svfToken.safeTransfer(msg.sender, shareAmount);

        totalSubscriptionCount += 1;
        subscriptionId = totalSubscriptionCount;

        totalAssetsSubscribed += assetAmount;
        totalSharesIssued += shareAmount;

        investorAssetsSubscribed[msg.sender] += assetAmount;
        investorSharesIssued[msg.sender] += shareAmount;
        investorSubscriptionCount[msg.sender] += 1;

        subscriptionRecords[subscriptionId] = SubscriptionRecord({
            subscriptionId: subscriptionId,
            investor: msg.sender,
            assetAmount: assetAmount,
            shareAmount: shareAmount,
            subscribedAt: block.timestamp
        });[cite: 5]

        emit SubscriptionCompleted(
            subscriptionId,
            msg.sender,
            assetAmount,
            shareAmount,
            block.timestamp
        );
    }

    function previewSubscription(uint256 assetAmount)
        external
        view
        returns (uint256)
    {
        if (assetAmount == 0) {
            return 0;
        }

        return fundVault.previewSubscription(assetAmount);
    }

    function getSubscription(uint256 subscriptionId)
        external
        view
        returns (SubscriptionRecord memory)
    {
        if (
            subscriptionId == 0 ||
            subscriptionId > totalSubscriptionCount
        ) {
            revert SubscriptionNotFound();
        }

        return subscriptionRecords[subscriptionId];
    }

    function setMinimumSubscriptionAmount(uint256 newMinimum)
        external
        onlyOwner
    {
        uint256 previousMinimum = minimumSubscriptionAmount;
        minimumSubscriptionAmount = newMinimum;

        emit MinimumSubscriptionAmountUpdated(previousMinimum, newMinimum);
    }

    function setFundRegistry(address newRegistry)
        external
        onlyOwner
    {
        if (newRegistry == address(0)) {
            revert InvalidAddress();
        }

        IFundRegistrySubscription registry = IFundRegistrySubscription(newRegistry);

        if (registry.fundVault() != address(fundVault)) {
            revert RegistryVaultMismatch();
        }

        if (registry.svfToken() != address(svfToken)) {
            revert RegistryTokenMismatch();
        }

        address previousRegistry = address(fundRegistry);
        fundRegistry = registry;

        emit FundRegistryUpdated(previousRegistry, newRegistry);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }[cite: 7]

    function recoverUnsupportedToken(
        address tokenAddress,
        address recipient,
        uint256 amount
    ) external onlyOwner nonReentrant {
        if (
            tokenAddress == address(0) ||
            recipient == address(0)
        ) {
            revert InvalidAddress();
        }

        if (
            tokenAddress == address(settlementAsset) ||
            tokenAddress == address(svfToken)
        ) {
            revert DirectRecoveryNotAllowed();
        }

        if (amount == 0) {
            revert InvalidAmount();
        }

        IERC20(tokenAddress).safeTransfer(recipient, amount);
    }

    function _validateFundConfiguration()
        internal
        view
    {
        if (address(fundRegistry) == address(0)) {
            return;
        }

        if (!fundRegistry.isActive()) {
            revert FundNotActive();
        }[cite: 8]

        if (fundRegistry.fundVault() != address(fundVault)) {
            revert RegistryVaultMismatch();
        }

        if (fundRegistry.svfToken() != address(svfToken)) {
            revert RegistryTokenMismatch();
        }
    }
}
