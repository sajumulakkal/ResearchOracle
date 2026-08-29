pragma solidity ^0.8.20;

/**
 * @title PortfolioManager
 * @notice Integrated portfolio manager covering Phase 0 to Phase 3.
 *
 * Covers:
 * - Phase 0: Basic rebalance instructions
 * - Phase 2: STRONG_BUY and EXCLUDE
 * - Phase 3: Position tracking and target weight updates
 */
contract PortfolioManager {
    enum Signal {
        NONE,
        STRONG_BUY,
        BUY,
        HOLD,
        REDUCE,
        EXCLUDE
    }

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

    struct Position {
        string ticker;
        uint256 currentWeightBps;
        uint256 targetWeightBps;
        bool exists;
    }

    struct RebalanceInstruction {
        uint256 instructionId;
        string ticker;
        uint256 roundId;
        Signal signal;
        int256 valuationGapPct;
        uint8 qualityScore;
        uint8 compositeScore;
        uint8 riskScore;
        uint256 warrantedPrice;
        uint256 marketPrice;
        int256 targetWeightChangeBps;
        uint256 previousWeightBps;
        uint256 newTargetWeightBps;
        bytes32 researchHash;
        uint256 version;
        string reason;
        address requestedBy;
        uint256 createdAt;
    }

    address public owner;
    address public strategyEngine;

    uint256 public latestInstructionId;
    uint256 public maxPositionWeightBps;
    mapping(bytes32 => Position) private positions;
    mapping(uint256 => RebalanceInstruction) private instructions;

    string[] private positionTickers;

    event StrategyEngineUpdated(
        address oldStrategyEngine,
        address newStrategyEngine
    );

    event PositionSet(
        string ticker,
        uint256 currentWeightBps,
        uint256 targetWeightBps
    );

    event MaxPositionWeightUpdated(
        uint256 oldValue,
        uint256 newValue
    );

    event RebalanceInstructionCreated(
        uint256 indexed instructionId,
        string ticker,
        uint256 indexed roundId,
        Signal signal,
        int256 targetWeightChangeBps,
        uint256 previousWeightBps,
        uint256 newTargetWeight,
        string reason,
        uint256 createdAt
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyStrategyEngine() {
        require(msg.sender == strategyEngine, "Not strategy engine");
        _;
    }

    constructor() {
        owner = msg.sender;
        maxPositionWeightBps = 2500;
    }

    function setStrategyEngine(address _strategyEngine) external onlyOwner {
        require(_strategyEngine != address(0), "Invalid strategy engine");

        address oldStrategyEngine = strategyEngine;
        strategyEngine = _strategyEngine;
        emit StrategyEngineUpdated(oldStrategyEngine, _strategyEngine);
    }

    function setMaxPositionWeight(uint256 newMaxPositionWeightBps)
        external
        onlyOwner
    {
        require(newMaxPositionWeightBps > 0, "Invalid max weight");
        require(newMaxPositionWeightBps <= 10000, "Max too high");

        uint256 oldValue = maxPositionWeightBps;
        maxPositionWeightBps = newMaxPositionWeightBps;

        emit MaxPositionWeightUpdated(oldValue, newMaxPositionWeightBps);
    }

    function setPosition(
        string calldata ticker,
        uint256 currentWeightBps,
        uint256 targetWeightBps
    ) external onlyOwner {
        require(bytes(ticker).length > 0, "Ticker required");
        require(currentWeightBps <= 10000, "Invalid current weight");
        require(targetWeightBps <= 10000, "Invalid target weight");
        require(targetWeightBps <= maxPositionWeightBps, "Target exceeds max");

        bytes32 key = _tickerKey(ticker);

        if (!positions[key].exists) {
            positionTickers.push(ticker);
        }

        positions[key] = Position({
            ticker: ticker,
            currentWeightBps: currentWeightBps,
            targetWeightBps: targetWeightBps,
            exists: true
        });

        emit PositionSet(ticker, currentWeightBps, targetWeightBps);
    }

    function createRebalanceInstruction(InstructionInput calldata input)
        external
        onlyStrategyEngine
        returns (uint256 instructionId)
    {
        require(bytes(input.ticker).length > 0, "Ticker required");
        require(input.signal <= uint8(Signal.EXCLUDE), "Invalid signal");
        require(input.warrantedPrice > 0, "Invalid warranted price");
        require(input.marketPrice > 0, "Invalid market price");

        Signal signal = Signal(input.signal);

        require(
            signal == Signal.STRONG_BUY ||
            signal == Signal.BUY ||
            signal == Signal.REDUCE ||
            signal == Signal.EXCLUDE,
            "No rebalance instruction needed"
        );

        bytes32 key = _tickerKey(input.ticker);

        if (!positions[key].exists) {
            positions[key] = Position({
                ticker: input.ticker,
                currentWeightBps: 0,
                targetWeightBps: 0,
                exists: true
            });

            positionTickers.push(input.ticker);
        }

        Position memory position = positions[key];

        int256 weightChange = _calculateWeightChange(signal, position);

        uint256 newTargetWeight = _applyWeightChange(
            position.targetWeightBps,
            weightChange
        );

        positions[key].targetWeightBps = newTargetWeight;

        latestInstructionId++;
        instructionId = latestInstructionId;

        string memory reason = _buildReason(signal);

        instructions[instructionId] = RebalanceInstruction({
            instructionId: instructionId,
            ticker: input.ticker,
            roundId: input.roundId,
            signal: signal,
            valuationGapPct: input.valuationGapPct,
            qualityScore: input.qualityScore,
            compositeScore: input.compositeScore,
            riskScore: input.riskScore,
            warrantedPrice: input.warrantedPrice,
            marketPrice: input.marketPrice,
            targetWeightChangeBps: weightChange,
            previousWeightBps: position.targetWeightBps,
            newTargetWeightBps: newTargetWeight,
            researchHash: input.researchHash,
            version: input.version,
            reason: reason,
            requestedBy: msg.sender,
            createdAt: block.timestamp
        });

        emit RebalanceInstructionCreated(
            instructionId,
            input.ticker,
            input.roundId,
            signal,
            weightChange,
            position.targetWeightBps,
            newTargetWeight,
            reason,
            block.timestamp
        );

        return instructionId;
    }

    function getPosition(string calldata ticker)
        external
        view
        returns (Position memory)
    {
        return positions[_tickerKey(ticker)];
    }

    function getInstruction(uint256 instructionId)
        external
        view
        returns (RebalanceInstruction memory)
    {
        return instructions[instructionId];
    }

    function getPositionTickers() external view returns (string[] memory) {
        return positionTickers;
    }

    function getPositionCount() external view returns (uint256) {
        return positionTickers.length;
    }

    function _calculateWeightChange(
        Signal signal,
        Position memory position
    ) internal pure returns (int256) {
        if (signal == Signal.STRONG_BUY) {
            return 500;
        }

        if (signal == Signal.BUY) {
            return 250;
        }

        if (signal == Signal.REDUCE) {
            if (position.targetWeightBps < 250) {
                return -int256(position.targetWeightBps);
            }
            return -250;
        }

        if (signal == Signal.EXCLUDE) {
            return -int256(position.targetWeightBps);
        }

        return 0;
    }

    function _applyWeightChange(
        uint256 currentTargetWeightBps,
        int256 weightChangeBps
    ) internal view returns (uint256) {
        int256 rawTarget =
            int256(currentTargetWeightBps) + weightChangeBps;

        if (rawTarget < 0) {
            return 0;
        }

        uint256 newTarget = uint256(rawTarget);

        if (newTarget > maxPositionWeightBps) {
            return maxPositionWeightBps;
        }

        return newTarget;
    }

    function _buildReason(Signal signal)
        internal
        pure
        returns (string memory)
    {
        if (signal == Signal.STRONG_BUY) {
            return "STRONG BUY allocation increase";
        }

        if (signal == Signal.BUY) {
            return "BUY allocation increase";
        }

        if (signal == Signal.REDUCE) {
            return "REDUCE allocation decrease";
        }

        if (signal == Signal.EXCLUDE) {
            return "EXCLUDE asset from target allocation";
        }

        return "No rebalance required";
    }

    function _tickerKey(string memory ticker)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(ticker));
    }
}