// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title StrategyEngine
 * @notice Integrated strategy engine covering Phase 0 to Phase 3.
 *
 * Covers:
 * - Phase 0: BUY / HOLD / REDUCE
 * - Phase 1: Use research hash and version metadata
 * - Phase 2: Composite score, STRONG_BUY, EXCLUDE
 * - Phase 3: Multi-asset portfolio evaluation and rebalance
 */

interface AutomationCompatibleInterface {
    function checkUpkeep(bytes calldata checkData)
        external
        view
        returns (bool upkeepNeeded, bytes memory performData);

    function performUpkeep(bytes calldata performData) external;
}

interface IIntegratedResearchOracle {
    struct ResearchData {
        string ticker;
        uint256 roundId;
        uint256 warrantedPrice;
        uint256 marketPrice;
        int256 valuationGapPct;
        uint8 qualityScore;
        uint8 cfroiScore;
        uint8 businessResilienceScore;
        uint8 accountingQualityScore;
        uint8 riskScore;
        uint8 momentumScore;
        uint8 esgScore;
        uint8 compositeScore;
        bytes32 researchHash;
        uint256 version;
        uint256 updatedAt;
        bool valid;
    }

    function latestResearchData(string calldata ticker)
        external
        view
        returns (ResearchData memory);

    function getTickers() external view returns (string[] memory);

    function getTickerCount() external view returns (uint256);
}

interface IIntegratedPortfolioManager {
    struct InstructionInput {
        string ticker;
        uint256 roundId;
        uint8 signal;
        int256 valuationGapPct;
        uint8 qualityScore;
        uint8 compositeScore;
        uint8 riskScore;
        uint256 warrantedPrice;
        uint256 marketPrice;
        bytes32 researchHash;
        uint256 version;
    }

    function createRebalanceInstruction(InstructionInput calldata input)
        external
        returns (uint256 instructionId);
}

contract StrategyEngine is AutomationCompatibleInterface {
    enum Signal {
        NONE,
        STRONG_BUY,
        BUY,
        HOLD,
        REDUCE,
        EXCLUDE
    }

    IIntegratedResearchOracle public oracleFeed;
    IIntegratedPortfolioManager public portfolioManager;

    address public owner;

    string[] private portfolioTickers;

    uint8 public minQualityScore;
    uint8 public minCompositeBuyScore;
    uint8 public minCompositeStrongBuyScore;
    uint8 public maxRiskScore;
    uint8 public excludeRiskScore;
    uint8 public minAccountingQualityScore;

    int256 public minUpsidePct;
    int256 public strongBuyUpsidePct;
    int256 public reduceBelowPct;

    uint256 public maxDataAge;

    uint256 public lastPortfolioCompositeScore;
    uint256 public lastActionableCount;
    uint256 public lastEvaluationTime;

    event PortfolioTickersUpdated(uint256 tickerCount);

    event TickerSignalEvaluated(
        string ticker,
        uint256 indexed roundId,
        Signal signal,
        int256 valuationGapPct,
        uint8 qualityScore,
        uint8 compositeScore,
        uint8 riskScore,
        uint256 evaluatedAt
    );

    event PortfolioEvaluationSummary(
        uint256 tickerCount,
        uint256 actionableCount,
        uint256 portfolioCompositeScore,
        uint256 evaluatedAt
    );

    event PortfolioRebalanceTriggered(
        uint256 actionableCount,
        uint256 triggeredAt
    );

    event StrategyRulesUpdated(
        uint8 minQualityScore,
        uint8 minCompositeBuyScore,
        uint8 minCompositeStrongBuyScore,
        uint8 maxRiskScore,
        uint8 excludeRiskScore,
        uint8 minAccountingQualityScore,
        int256 minUpsidePct,
        int256 strongBuyUpsidePct,
        int256 reduceBelowPct,
        uint256 maxDataAge
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(
        address _oracleFeed,
        address _portfolioManager,
        string[] memory initialTickers
    ) {
        require(_oracleFeed != address(0), "Invalid oracle");
        require(_portfolioManager != address(0), "Invalid portfolio manager");
        require(initialTickers.length > 0, "No tickers");

        owner = msg.sender;

        oracleFeed = IIntegratedResearchOracle(_oracleFeed);
        portfolioManager = IIntegratedPortfolioManager(_portfolioManager);

        for (uint256 i = 0; i < initialTickers.length; i++) {
            require(bytes(initialTickers[i]).length > 0, "Invalid ticker");
            portfolioTickers.push(initialTickers[i]);
        }

        minQualityScore = 80;
        minCompositeBuyScore = 75;
        minCompositeStrongBuyScore = 85;
        maxRiskScore = 60;
        excludeRiskScore = 90;
        minAccountingQualityScore = 40;

        minUpsidePct = 15;
        strongBuyUpsidePct = 25;
        reduceBelowPct = -10;

        maxDataAge = 3600;
    }

    function getPortfolioTickers() external view returns (string[] memory) {
        return portfolioTickers;
    }

    function getTickerCount() external view returns (uint256) {
        return portfolioTickers.length;
    }

    function updatePortfolioTickers(string[] calldata newTickers)
        external
        onlyOwner
    {
        require(newTickers.length > 0, "No tickers");

        delete portfolioTickers;

        for (uint256 i = 0; i < newTickers.length; i++) {
            require(bytes(newTickers[i]).length > 0, "Invalid ticker");
            portfolioTickers.push(newTickers[i]);
        }

        emit PortfolioTickersUpdated(newTickers.length);
    }

    function evaluateTicker(string calldata ticker)
        public
        view
        returns (Signal)
    {
        IIntegratedResearchOracle.ResearchData memory data =
            _readFreshResearchData(ticker);

        return _decide(data);
    }

    function evaluatePortfolio()
        external
        returns (
            uint256 tickerCount,
            uint256 actionableCount,
            uint256 portfolioCompositeScore
        )
    {
        require(portfolioTickers.length > 0, "No tickers");

        uint256 totalComposite = 0;
        uint256 actions = 0;
        uint256 count = portfolioTickers.length;

        for (uint256 i = 0; i < count; i++) {
            IIntegratedResearchOracle.ResearchData memory data =
                _readFreshResearchData(portfolioTickers[i]);

            Signal signal = _decide(data);

            totalComposite += data.compositeScore;

            if (_isActionable(signal)) {
                actions++;
            }

            emit TickerSignalEvaluated(
                data.ticker,
                data.roundId,
                signal,
                data.valuationGapPct,
                data.qualityScore,
                data.compositeScore,
                data.riskScore,
                block.timestamp
            );
        }

        uint256 avgComposite = totalComposite / count;

        lastPortfolioCompositeScore = avgComposite;
        lastActionableCount = actions;
        lastEvaluationTime = block.timestamp;

        emit PortfolioEvaluationSummary(
            count,
            actions,
            avgComposite,
            block.timestamp
        );

        return (count, actions, avgComposite);
    }

    function checkUpkeep(bytes calldata)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        if (portfolioTickers.length == 0) {
            return (false, bytes(""));
        }

        for (uint256 i = 0; i < portfolioTickers.length; i++) {
            IIntegratedResearchOracle.ResearchData memory data =
                oracleFeed.latestResearchData(portfolioTickers[i]);

            bool fresh =
                data.valid &&
                data.updatedAt > 0 &&
                block.timestamp - data.updatedAt <= maxDataAge;

            if (!fresh) {
                continue;
            }

            Signal signal = _decide(data);

            if (_isActionable(signal)) {
                return (true, abi.encode(portfolioTickers.length));
            }
        }

        return (false, bytes(""));
    }

    function performUpkeep(bytes calldata) external override {
        require(portfolioTickers.length > 0, "No tickers");

        uint256 actions = 0;

        for (uint256 i = 0; i < portfolioTickers.length; i++) {
            IIntegratedResearchOracle.ResearchData memory data =
                _readFreshResearchData(portfolioTickers[i]);

            Signal signal = _decide(data);

            emit TickerSignalEvaluated(
                data.ticker,
                data.roundId,
                signal,
                data.valuationGapPct,
                data.qualityScore,
                data.compositeScore,
                data.riskScore,
                block.timestamp
            );

            if (!_isActionable(signal)) {
                continue;
            }

            IIntegratedPortfolioManager.InstructionInput memory input =
                IIntegratedPortfolioManager.InstructionInput({
                    ticker: data.ticker,
                    roundId: data.roundId,
                    signal: uint8(signal),
                    valuationGapPct: data.valuationGapPct,
                    qualityScore: data.qualityScore,
                    compositeScore: data.compositeScore,
                    riskScore: data.riskScore,
                    warrantedPrice: data.warrantedPrice,
                    marketPrice: data.marketPrice,
                    researchHash: data.researchHash,
                    version: data.version
                });

            portfolioManager.createRebalanceInstruction(input);

            actions++;
        }

        require(actions > 0, "No actionable signals");

        lastActionableCount = actions;
        lastEvaluationTime = block.timestamp;

        emit PortfolioRebalanceTriggered(actions, block.timestamp);
    }

    function updateStrategyRules(
        uint8 _minQualityScore,
        uint8 _minCompositeBuyScore,
        uint8 _minCompositeStrongBuyScore,
        uint8 _maxRiskScore,
        uint8 _excludeRiskScore,
        uint8 _minAccountingQualityScore,
        int256 _minUpsidePct,
        int256 _strongBuyUpsidePct,
        int256 _reduceBelowPct,
        uint256 _maxDataAge
    ) external onlyOwner {
        _validateScore(_minQualityScore);
        _validateScore(_minCompositeBuyScore);
        _validateScore(_minCompositeStrongBuyScore);
        _validateScore(_maxRiskScore);
        _validateScore(_excludeRiskScore);
        _validateScore(_minAccountingQualityScore);

        require(_maxDataAge > 0, "Invalid max data age");

        minQualityScore = _minQualityScore;
        minCompositeBuyScore = _minCompositeBuyScore;
        minCompositeStrongBuyScore = _minCompositeStrongBuyScore;
        maxRiskScore = _maxRiskScore;
        excludeRiskScore = _excludeRiskScore;
        minAccountingQualityScore = _minAccountingQualityScore;

        minUpsidePct = _minUpsidePct;
        strongBuyUpsidePct = _strongBuyUpsidePct;
        reduceBelowPct = _reduceBelowPct;

        maxDataAge = _maxDataAge;

        emit StrategyRulesUpdated(
            _minQualityScore,
            _minCompositeBuyScore,
            _minCompositeStrongBuyScore,
            _maxRiskScore,
            _excludeRiskScore,
            _minAccountingQualityScore,
            _minUpsidePct,
            _strongBuyUpsidePct,
            _reduceBelowPct,
            _maxDataAge
        );
    }

    function _readFreshResearchData(string memory ticker)
        internal
        view
        returns (IIntegratedResearchOracle.ResearchData memory)
    {
        IIntegratedResearchOracle.ResearchData memory data =
            oracleFeed.latestResearchData(ticker);
        require(data.valid, "No valid research data");
        require(data.updatedAt > 0, "Invalid update time");

        require(
            block.timestamp - data.updatedAt <= maxDataAge,
            "Research data stale"
        );

        return data;
    }

    function _decide(IIntegratedResearchOracle.ResearchData memory data)
        internal
        view
        returns (Signal)
    {
        if (
            data.riskScore >= excludeRiskScore ||
            data.accountingQualityScore < minAccountingQualityScore
        ) {
            return Signal.EXCLUDE;
        }

        if (data.valuationGapPct <= reduceBelowPct) {
            return Signal.REDUCE;
        }

        if (
            data.compositeScore >= minCompositeStrongBuyScore &&
            data.valuationGapPct >= strongBuyUpsidePct &&
            data.riskScore <= maxRiskScore
        ) {
            return Signal.STRONG_BUY;
        }

        if (
            data.compositeScore >= minCompositeBuyScore &&
            data.valuationGapPct >= minUpsidePct &&
            data.riskScore <= maxRiskScore
        ) {
            return Signal.BUY;
        }

        if (
            data.qualityScore >= minQualityScore &&
            data.valuationGapPct >= minUpsidePct
        ) {
            return Signal.BUY;
        }

        return Signal.HOLD;
    }

    function _isActionable(Signal signal) internal pure returns (bool) {
        return
            signal == Signal.STRONG_BUY ||
            signal == Signal.BUY ||
            signal == Signal.REDUCE ||
            signal == Signal.EXCLUDE;
    }

    function _validateScore(uint8 score) internal pure {
        require(score <= 100, "Invalid score");
    }
}