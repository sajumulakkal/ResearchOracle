// State Variables, Events, and Errors[cite: 1]
mapping(uint256 => Redemption) private redemptions;
mapping(address => uint256) public investorRedemptionCount;
mapping(address => uint256) public investorAssetsRedeemed;

event RedemptionCompleted(
    uint256 indexed redemptionId,
    address indexed investor,
    uint256 shareAmount,
    uint256 assetAmount,
    uint256 timestamp
);

event FundRegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
event ManagerPaused(uint256 timestamp);
event ManagerResumed(uint256 timestamp);

error InvalidAddress();
error InvalidAmount();
error InvalidRedemption();
error FundInactive();
error SlippageExceeded();

// Constructor[cite: 1, 2]
constructor(
    address initialOwner,
    address vaultAddress,
    address assetAddress,
    address tokenAddress
) {
    if (
        initialOwner == address(0) ||
        vaultAddress == address(0) ||
        assetAddress == address(0) ||
        tokenAddress == address(0)
    ) revert InvalidAddress();

    if (initialOwner != msg.sender) {
        transferOwnership(initialOwner);
    }

    fundVault = IFundVaultRedemption(vaultAddress);
    settlementAsset = IERC20(assetAddress);
    svfToken = IERC20(tokenAddress);
}

// Redeem Function[cite: 2, 3]
function redeem(
    uint256 shareAmount,
    uint256 minimumAssets
)
    external
    nonReentrant
    whenNotPaused
    returns (uint256 redemptionId, uint256 assetAmount)
{
    if (shareAmount == 0) revert InvalidAmount();

    if (address(fundRegistry) != address(0) && !fundRegistry.isActive()) {
        revert FundInactive();
    }

    uint256 expectedAssets = fundVault.previewRedemption(shareAmount);
    if (expectedAssets < minimumAssets) revert SlippageExceeded();

    svfToken.safeTransferFrom(msg.sender, address(this), shareAmount);

    assetAmount = fundVault.redeem(shareAmount);

    if (assetAmount < minimumAssets) revert SlippageExceeded();

    settlementAsset.safeTransfer(msg.sender, assetAmount);

    redemptionId = ++totalRedemptions;
    totalSharesRedeemed += shareAmount;
    totalAssetsRedeemed += assetAmount;
    lastRedemptionTimestamp = block.timestamp;

    investorRedemptionCount[msg.sender] += 1;
    investorAssetsRedeemed[msg.sender] += assetAmount;

    redemptions[redemptionId] = Redemption(
        redemptionId,
        msg.sender,
        shareAmount,
        assetAmount,
        block.timestamp
    );

    emit RedemptionCompleted(
        redemptionId,
        msg.sender,
        shareAmount,
        assetAmount,
        block.timestamp
    );
}

// Preview Redemption[cite: 3]
function previewRedemption(uint256 shareAmount)
    external
    view
    returns (uint256)
{
    return fundVault.previewRedemption(shareAmount);
}

// Get Redemption[cite: 3]
function getRedemption(uint256 redemptionId)
    external
    view
    returns (Redemption memory)
{
    if (redemptionId == 0 || redemptionId > totalRedemptions) {
        revert InvalidRedemption();
    }
    return redemptions[redemptionId];
}

// Admin Functions: Set Fund Registry, Pause, and Unpause[cite: 3, 4]
function setFundRegistry(address registryAddress)
    external
    onlyOwner
    whenNotPaused
{
    if (registryAddress == address(0)) revert InvalidAddress();

    emit FundRegistryUpdated(address(fundRegistry), registryAddress);
    fundRegistry = IFundRegistryRedemption(registryAddress);
}

function pause() external onlyOwner {
    _pause();
    emit ManagerPaused(block.timestamp);
}

function unpause() external onlyOwner {
    _unpause();
    emit ManagerResumed(block.timestamp);
}
