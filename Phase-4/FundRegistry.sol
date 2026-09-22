// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract FundRegistry {

    struct FundInfo {
        string fundName;
        string fundSymbol;
        address svfToken;
        address fundVault;
        address researchOracle;
        address strategyEngine;
        address portfolioManager;
        address fundManager;
        uint256 launchTimestamp;
        uint256 lastUpdated;
        bool active;
    }

    FundInfo private fund;

    // Events[cite: 1, 2]
    event FundInitialized(
        string fundName,
        string fundSymbol,
        address indexed fundManager,
        uint256 launchTimestamp
    );
    event FundManagerUpdated(
        address indexed oldManager,
        address indexed newManager,
        uint256 updatedAt
    );
    event SVFTokenUpdated(
        address indexed oldAddress,
        address indexed newAddress,
        uint256 updatedAt
    );
    event FundVaultUpdated(
        address indexed oldAddress,
        address indexed newAddress,
        uint256 updatedAt
    );
    event ResearchOracleUpdated(
        address indexed oldAddress,
        address indexed newAddress,
        uint256 updatedAt
    );
    event StrategyEngineUpdated(
        address indexed oldAddress,
        address indexed newAddress,
        uint256 updatedAt
    );
    event PortfolioManagerUpdated(
        address indexed oldAddress,
        address indexed newAddress,
        uint256 updatedAt
    );
    event FundContractsConfigured(
        address indexed configuredBy,
        uint256 updatedAt
    );
    event FundStatusUpdated(
        bool previousStatus,
        bool newStatus,
        uint256 updatedAt
    );
    event RegistryPaused(uint256 timestamp);
    event RegistryResumed(uint256 timestamp);

    // Custom Errors[cite: 2]
    error InvalidOwner();
    error InvalidAddress();
    error InvalidFundName();
    error InvalidFundSymbol();
    error InvalidManager();
    error NotContract();
    error AddressAlreadySet();
    error StatusAlreadySet();
    error RegistryAlreadyPaused();
    error RegistryNotPaused();

    // Modifiers & Inherited state placeholders (assumed standard OZ-like controls)
    bool private _paused;
    address private _owner;

    modifier onlyOwner() {
        if (msg.sender != _owner) revert InvalidOwner();
        _;
    }

    modifier whenNotPaused() {
        if (_paused) revert RegistryAlreadyPaused();
        _;
    }

    function paused() public view returns (bool) {
        return _paused;
    }

    function _pause() internal {
        _paused = true;
    }

    function _unpause() internal {
        _paused = false;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        if (newOwner == address(0)) revert InvalidOwner();
        _owner = newOwner;
    }

    // Constructor[cite: 2, 3, 4]
    constructor(
        address initialOwner,
        string memory fundName_,
        string memory fundSymbol_,
        address fundManager_
    ) {
        if (initialOwner == address(0)) {
            revert InvalidOwner();
        }
        if (bytes(fundName_).length == 0) {
            revert InvalidFundName();
        }
        if (bytes(fundSymbol_).length == 0) {
            revert InvalidFundSymbol();
        }
        if (fundManager_ == address(0)) {
            revert InvalidManager();
        }
        if (initialOwner != msg.sender) {
            transferOwnership(initialOwner);
        }

        fund.fundName = fundName_;
        fund.fundSymbol = fundSymbol_;
        fund.fundManager = fundManager_;
        fund.launchTimestamp = block.timestamp;
        fund.lastUpdated = block.timestamp;
        fund.active = true;

        emit FundInitialized(
            fundName_,
            fundSymbol_,
            fundManager_,
            block.timestamp
        );
    }

    // Setter Functions[cite: 4, 5, 6, 9]
    function setSVFToken(address newAddress) external onlyOwner whenNotPaused {
        _validateNewContractAddress(fund.svfToken, newAddress);
        address oldAddress = fund.svfToken;
        fund.svfToken = newAddress;
        _touch();
        emit SVFTokenUpdated(oldAddress, newAddress, block.timestamp);
    }

    function setFundVault(address newAddress) external onlyOwner whenNotPaused {
        _validateNewContractAddress(fund.fundVault, newAddress);
        address oldAddress = fund.fundVault;
        fund.fundVault = newAddress;
        _touch();
        emit FundVaultUpdated(oldAddress, newAddress, block.timestamp);
    }

    function setResearchOracle(address newAddress) external onlyOwner whenNotPaused {
        _validateNewContractAddress(fund.researchOracle, newAddress);
        address oldAddress = fund.researchOracle;
        fund.researchOracle = newAddress;
        _touch();
        emit ResearchOracleUpdated(oldAddress, newAddress, block.timestamp);
    }

    function setStrategyEngine(address newAddress) external onlyOwner whenNotPaused {
        _validateNewContractAddress(fund.strategyEngine, newAddress);
        address oldAddress = fund.strategyEngine;
        fund.strategyEngine = newAddress;
        _touch();
        emit StrategyEngineUpdated(oldAddress, newAddress, block.timestamp);
    }

    function setPortfolioManager(address newAddress) external onlyOwner whenNotPaused {
        _validateNewContractAddress(fund.portfolioManager, newAddress);
        address oldAddress = fund.portfolioManager;
        fund.portfolioManager = newAddress;
        _touch();
        emit PortfolioManagerUpdated(oldAddress, newAddress, block.timestamp);
    }

    /**
     * @notice Configure all registered contract addresses atomically.[cite: 7]
     * @dev All supplied addresses must contain deployed bytecode.[cite: 7]
     */
    function configureContracts(
        address svfToken_,
        address fundVault_,
        address researchOracle_,
        address strategyEngine_,
        address portfolioManager_
    ) external onlyOwner whenNotPaused {
        _validateContract(svfToken_);
        _validateContract(fundVault_);
        _validateContract(researchOracle_);
        _validateContract(strategyEngine_);
        _validateContract(portfolioManager_);

        if (
            fund.svfToken == svfToken_ &&
            fund.fundVault == fundVault_ &&
            fund.researchOracle == researchOracle_ &&
            fund.strategyEngine == strategyEngine_ &&
            fund.portfolioManager == portfolioManager_
        ) {
            revert AddressAlreadySet();
        }

        if (fund.svfToken != svfToken_) {
            emit SVFTokenUpdated(fund.svfToken, svfToken_, block.timestamp);
        }

        if (fund.fundVault != fundVault_) {
            emit FundVaultUpdated(fund.fundVault, fundVault_, block.timestamp);
        }

        if (fund.researchOracle != researchOracle_) {
            emit ResearchOracleUpdated(fund.researchOracle, researchOracle_, block.timestamp);
        }

        if (fund.strategyEngine != strategyEngine_) {
            emit StrategyEngineUpdated(fund.strategyEngine, strategyEngine_, block.timestamp);
        }

        if (fund.portfolioManager != portfolioManager_) {
            emit PortfolioManagerUpdated(fund.portfolioManager, portfolioManager_, block.timestamp);
        }

        fund.svfToken = svfToken_;
        fund.fundVault = fundVault_;
        fund.researchOracle = researchOracle_;
        fund.strategyEngine = strategyEngine_;
        fund.portfolioManager = portfolioManager_;

        _touch();

        emit FundContractsConfigured(msg.sender, block.timestamp);
    }

    function setFundManager(address newManager) external onlyOwner whenNotPaused {
        if (newManager == address(0)) {
            revert InvalidManager();
        }
        if (newManager == fund.fundManager) {
            revert AddressAlreadySet();
        }
        address oldManager = fund.fundManager;
        fund.fundManager = newManager;
        _touch();
        emit FundManagerUpdated(oldManager, newManager, block.timestamp);
    }

    function setFundStatus(bool active_) external onlyOwner {
        if (fund.active == active_) {
            revert StatusAlreadySet();
        }
        bool previousStatus = fund.active;
        fund.active = active_;
        _touch();
        emit FundStatusUpdated(previousStatus, active_, block.timestamp);
    }

    function pause() external onlyOwner {
        if (paused()) {
            revert RegistryAlreadyPaused();
        }
        _pause();
        emit RegistryPaused(block.timestamp);
    }

    function unpause() external onlyOwner {
        if (!paused()) {
            revert RegistryNotPaused();
        }
        _unpause();
        emit RegistryResumed(block.timestamp);
    }

    // Getter Functions[cite: 11, 12, 13, 14]
    function getFundInfo() external view returns (FundInfo memory) {
        return fund;
    }

    function areContractsConfigured() external view returns (bool) {
        return
            _isContract(fund.svfToken) &&
            _isContract(fund.fundVault) &&
            _isContract(fund.researchOracle) &&
            _isContract(fund.strategyEngine) &&
            _isContract(fund.portfolioManager);
    }

    function fundName() external view returns (string memory) {
        return fund.fundName;
    }

    function fundSymbol() external view returns (string memory) {
        return fund.fundSymbol;
    }

    function svfToken() external view returns (address) {
        return fund.svfToken;
    }

    function fundVault() external view returns (address) {
        return fund.fundVault;
    }

    function researchOracle() external view returns (address) {
        return fund.researchOracle;
    }

    function strategyEngine() external view returns (address) {
        return fund.strategyEngine;
    }

    function portfolioManager() external view returns (address) {
        return fund.portfolioManager;
    }

    function fundManager() external view returns (address) {
        return fund.fundManager;
    }

    function launchTimestamp() external view returns (uint256) {
        return fund.launchTimestamp;
    }

    function lastUpdated() external view returns (uint256) {
        return fund.lastUpdated;
    }

    function isActive() external view returns (bool) {
        return fund.active;
    }

    // Internal Validation & Helper Functions[cite: 14, 15]
    function _validateNewContractAddress(address currentAddress, address newAddress) internal view {
        _validateContract(newAddress);
        if (currentAddress == newAddress) {
            revert AddressAlreadySet();
        }
    }

    function _validateContract(address candidate) internal view {
        if (candidate == address(0)) {
            revert InvalidAddress();
        }
        if (!_isContract(candidate)) {
            revert NotContract();
        }
    }

    function _isContract(address candidate) internal view returns (bool) {
        return candidate.code.length > 0;
    }

    function _touch() internal {
        fund.lastUpdated = block.timestamp;
    }
}
