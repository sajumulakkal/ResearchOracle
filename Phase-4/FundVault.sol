event Redeemed(address indexed investor, uint256 shareAmount, uint256 assetAmount);
event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
event TreasuryWithdrawal(address indexed treasury, uint256 amount);
event VaultPaused(uint256 timestamp);
event VaultResumed(uint256 timestamp);

error InvalidOwner();
error InvalidAddress();
error InvalidAmount();
error InvalidTreasury();
error InsufficientLiquidity();
error InsufficientShares();

constructor(
    address initialOwner,
    address assetAddress,
    address tokenAddress
) {
    if (initialOwner == address(0)) revert InvalidOwner();
    if (assetAddress == address(0) || tokenAddress == address(0)) revert InvalidAddress();

    if (initialOwner != msg.sender) {
        transferOwnership(initialOwner);
    }

    settlementAsset = IERC20(assetAddress);
    svfToken = ISVFToken(tokenAddress);

    assetDecimals = IERC20Metadata(assetAddress).decimals();
    shareDecimals = svfToken.decimals();
    lastActivityTimestamp = block.timestamp;
}

function subscribe(uint256 assetAmount)
    external
    nonReentrant
    whenNotPaused
    returns (uint256 shareAmount)
{
    if (assetAmount == 0) revert InvalidAmount();

    shareAmount = previewSubscription(assetAmount);

    settlementAsset.safeTransferFrom(msg.sender, address(this), assetAmount);
    svfToken.mint(msg.sender, shareAmount);

    totalAssetsSubscribed += assetAmount;
    totalSharesMinted += shareAmount;
    lastActivityTimestamp = block.timestamp;

    emit Subscribed(msg.sender, assetAmount, shareAmount);
}

function redeem(uint256 shareAmount)
    external
    nonReentrant
    whenNotPaused
    returns (uint256 assetAmount)
{
    if (shareAmount == 0) revert InvalidAmount();
    if (svfToken.balanceOf(msg.sender) < shareAmount) revert InsufficientShares();

    assetAmount = previewRedemption(shareAmount);

    if (settlementAsset.balanceOf(address(this)) < assetAmount) {
        revert InsufficientLiquidity();
    }

    svfToken.burn(msg.sender, shareAmount);
    settlementAsset.safeTransfer(msg.sender, assetAmount);

    totalSharesBurned += shareAmount;
    totalAssetsRedeemed += assetAmount;
    lastActivityTimestamp = block.timestamp;

    emit Redeemed(msg.sender, shareAmount, assetAmount);
}

function previewSubscription(uint256 assetAmount) public view returns (uint256) {
    return _convertDecimals(assetAmount, assetDecimals, shareDecimals);
}

function previewRedemption(uint256 shareAmount) public view returns (uint256) {
    return _convertDecimals(shareAmount, shareDecimals, assetDecimals);
}

function totalAssets() public view returns (uint256) {
    return settlementAsset.balanceOf(address(this));
}

function availableLiquidity() external view returns (uint256) {
    return settlementAsset.balanceOf(address(this));
}

function setTreasury(address newTreasury) external onlyOwner whenNotPaused {
    if (newTreasury == address(0)) revert InvalidTreasury();
    emit TreasuryUpdated(treasury, newTreasury);
    treasury = newTreasury;
}

function withdrawToTreasury(uint256 amount)
    external
    onlyOwner
    whenNotPaused
{
    if (treasury == address(0)) revert InvalidTreasury();
    if (amount == 0) revert InvalidAmount();

    settlementAsset.safeTransfer(treasury, amount);
    emit TreasuryWithdrawal(treasury, amount);
}

function assetsPerShare() external view returns (uint256) {
    uint256 supply = svfToken.totalSupply();
    if (supply == 0) return 0;
    return (totalAssets() * 1e18) / supply;
}

function pause() external onlyOwner {
    _pause();
    emit VaultPaused(block.timestamp);
}

function unpause() external onlyOwner {
    _unpause();
    emit VaultResumed(block.timestamp);
}

function _convertDecimals(uint256 amount, uint8 fromDecimals, uint8 toDecimals)
    internal
    pure
    returns (uint256)
{
    if (fromDecimals == toDecimals) return amount;
    if (fromDecimals < toDecimals) {
        return amount * (10 ** uint256(toDecimals - fromDecimals));
    }
    return amount / (10 ** uint256(fromDecimals - toDecimals));
}
