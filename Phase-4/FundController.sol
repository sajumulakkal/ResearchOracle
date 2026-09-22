Here is the complete, compiled source code for **`FundController.sol`** transcribed from all the provided images:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title FundController
 * @notice Phase 4 coordinator and configuration registry for the
 * Smart Value Fund platform.
 *
 * The controller stores the addresses of the Phase 3.5 intelligence
 * contracts and the Phase 4 tokenized fund contracts. It does not
 * custody assets, mint shares, redeem shares, calculate NAV, or execute
 * portfolio trades.
 */
contract FundController is Ownable, Pausable {
    struct PlatformAddresses {
        address researchOracle;
        address strategyEngine;
        address portfolioManager;
        address svfToken;
        address fundVault;
        address fundRegistry;
        address subscriptionManager;
        address redemptionManager;
        address portfolioSnapshot;
    }

    PlatformAddresses private platform;
    uint256 public lastConfigUpdate;

    event ComponentUpdated(
        string component,
        address indexed oldAddress,
        address indexed newAddress,
        uint256 updatedAt
    );

    event PlatformConfigured(
        address indexed configuredBy,
        uint256 updatedAt
    );

    event PlatformPaused(uint256 timestamp);
    event PlatformResumed(uint256 timestamp);

    error InvalidOwner();
    error InvalidAddress();
    error NotContract();
    error PlatformAlreadyPaused();
    error PlatformNotPaused();

    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert InvalidOwner();
        }

        if (initialOwner != msg.sender) {
            transferOwnership(initialOwner);
        }
    }

    function setResearchOracle(address newAddress)
        external
        onlyOwner
        whenNotPaused
    {
        _setResearchOracle(newAddress);
    }

    function setStrategyEngine(address newAddress)
        external
        onlyOwner
        whenNotPaused
    {
        _setStrategyEngine(newAddress);
    }

    function setPortfolioManager(address newAddress)
        external
        onlyOwner
        whenNotPaused
    {
        _setPortfolioManager(newAddress);
    }

    function setSVFToken(address newAddress)
        external
        onlyOwner
        whenNotPaused
    {
        _setSVFToken(newAddress);
    }

    function setFundVault(address newAddress)
        external
        onlyOwner
        whenNotPaused
    {
        _setFundVault(newAddress);
    }

    function setFundRegistry(address newAddress)
        external
        onlyOwner
        whenNotPaused
    {
        _setFundRegistry(newAddress);
    }

    function setSubscriptionManager(address newAddress)
        external
        onlyOwner
        whenNotPaused
    {
        _setSubscriptionManager(newAddress);
    }

    function setRedemptionManager(address newAddress)
        external
        onlyOwner
        whenNotPaused
    {
        _setRedemptionManager(newAddress);
    }

    function setPortfolioSnapshot(address newAddress)
        external
        onlyOwner
        whenNotPaused
    {
        _setPortfolioSnapshot(newAddress);
    }

    /**
     * @notice Configure all platform contract addresses atomically.
     * @dev Every address must contain deployed contract bytecode.
     */
    function configurePlatform(
        address researchOracle,
        address strategyEngine,
        address portfolioManager,
        address svfToken,
        address fundVault,
        address fundRegistry,
        address subscriptionManager,
        address redemptionManager,
        address portfolioSnapshot
    )
        external
        onlyOwner
        whenNotPaused
    {
        _validateContract(researchOracle);
        _validateContract(strategyEngine);
        _validateContract(portfolioManager);
        _validateContract(svfToken);
        _validateContract(fundVault);
        _validateContract(fundRegistry);
        _validateContract(subscriptionManager);
        _validateContract(redemptionManager);
        _validateContract(portfolioSnapshot);

        _emitIfChanged(
            "ResearchOracle",
            platform.researchOracle,
            researchOracle
        );
        _emitIfChanged(
            "StrategyEngine",
            platform.strategyEngine,
            strategyEngine
        );
        _emitIfChanged(
            "PortfolioManager",
            platform.portfolioManager,
            portfolioManager
        );
        _emitIfChanged(
            "SVFToken",
            platform.svfToken,
            svfToken
        );
        _emitIfChanged(
            "FundVault",
            platform.fundVault,
            fundVault
        );
        _emitIfChanged(
            "FundRegistry",
            platform.fundRegistry,
            fundRegistry
        );
        _emitIfChanged(
            "SubscriptionManager",
            platform.subscriptionManager,
            subscriptionManager
        );
        _emitIfChanged(
            "RedemptionManager",
            platform.redemptionManager,
            redemptionManager
        );
        _emitIfChanged(
            "PortfolioSnapshot",
            platform.portfolioSnapshot,
            portfolioSnapshot
        );

        platform = PlatformAddresses({
            researchOracle: researchOracle,
            strategyEngine: strategyEngine,
            portfolioManager: portfolioManager,
            svfToken: svfToken,
            fundVault: fundVault,
            fundRegistry: fundRegistry,
            subscriptionManager: subscriptionManager,
            redemptionManager: redemptionManager,
            portfolioSnapshot: portfolioSnapshot
        });

        lastConfigUpdate = block.timestamp;

        emit PlatformConfigured(
            msg.sender,
            block.timestamp
        );
    }

    function getPlatformAddresses()
        external
        view
        returns (PlatformAddresses memory)
    {
        return platform;
    }

    function isPlatformReady()
        external
        view
        returns (bool)
    {
        return
            _isContract(platform.researchOracle) &&
            _isContract(platform.strategyEngine) &&
            _isContract(platform.portfolioManager) &&
            _isContract(platform.svfToken) &&
            _isContract(platform.fundVault) &&
            _isContract(platform.fundRegistry) &&
            _isContract(platform.subscriptionManager) &&
            _isContract(platform.redemptionManager) &&
            _isContract(platform.portfolioSnapshot);
    }

    function pausePlatform()
        external
        onlyOwner
    {
        if (paused()) {
            revert PlatformAlreadyPaused();
        }

        _pause();
        emit PlatformPaused(block.timestamp);
    }

    function resumePlatform()
        external
        onlyOwner
    {
        if (!paused()) {
            revert PlatformNotPaused();
        }

        _unpause();
        emit PlatformResumed(block.timestamp);
    }

    function _setResearchOracle(address newAddress) internal {
        _validateContract(newAddress);
        _emitIfChanged(
            "ResearchOracle",
            platform.researchOracle,
            newAddress
        );
        platform.researchOracle = newAddress;
        lastConfigUpdate = block.timestamp;
    }

    function _setStrategyEngine(address newAddress) internal {
        _validateContract(newAddress);
        _emitIfChanged(
            "StrategyEngine",
            platform.strategyEngine,
            newAddress
        );
        platform.strategyEngine = newAddress;
        lastConfigUpdate = block.timestamp;
    }

    function _setPortfolioManager(address newAddress) internal {
        _validateContract(newAddress);
        _emitIfChanged(
            "PortfolioManager",
            platform.portfolioManager,
            newAddress
        );
        platform.portfolioManager = newAddress;
        lastConfigUpdate = block.timestamp;
    }

    function _setSVFToken(address newAddress) internal {
        _validateContract(newAddress);
        _emitIfChanged(
            "SVFToken",
            platform.svfToken,
            newAddress
        );
        platform.svfToken = newAddress;
        lastConfigUpdate = block.timestamp;
    }

    function _setFundVault(address newAddress) internal {
        _validateContract(newAddress);
        _emitIfChanged(
            "FundVault",
            platform.fundVault,
            newAddress
        );
        platform.fundVault = newAddress;
        lastConfigUpdate = block.timestamp;
    }

    function _setFundRegistry(address newAddress) internal {
        _validateContract(newAddress);
        _emitIfChanged(
            "FundRegistry",
            platform.fundRegistry,
            newAddress
        );
        platform.fundRegistry = newAddress;
        lastConfigUpdate = block.timestamp;
    }

    function _setSubscriptionManager(address newAddress) internal {
        _validateContract(newAddress);
        _emitIfChanged(
            "SubscriptionManager",
            platform.subscriptionManager,
            newAddress
        );
        platform.subscriptionManager = newAddress;
        lastConfigUpdate = block.timestamp;
    }

    function _setRedemptionManager(address newAddress) internal {
        _validateContract(newAddress);
        _emitIfChanged(
            "RedemptionManager",
            platform.redemptionManager,
            newAddress
        );
        platform.redemptionManager = newAddress;
        lastConfigUpdate = block.timestamp;
    }

    function _setPortfolioSnapshot(address newAddress) internal {
        _validateContract(newAddress);
        _emitIfChanged(
            "PortfolioSnapshot",
            platform.portfolioSnapshot,
            newAddress
        );
        platform.portfolioSnapshot = newAddress;
        lastConfigUpdate = block.timestamp;
    }

    function _validateContract(address candidate)
        internal
        view
    {
        if (candidate == address(0)) {
            revert InvalidAddress();
        }

        if (!_isContract(candidate)) {
            revert NotContract();
        }
    }

    function _isContract(address candidate)
        internal
        view
        returns (bool)
    {
        return candidate.code.length > 0;
    }

    function _emitIfChanged(
        string memory component,
        address oldAddress,
        address newAddress
    ) internal {
        if (oldAddress != newAddress) {
            emit ComponentUpdated(
                component,
                oldAddress,
                newAddress,
                block.timestamp
            );
        }
    }
}

```
