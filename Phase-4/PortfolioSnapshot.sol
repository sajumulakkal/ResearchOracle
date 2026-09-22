// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract PortfolioSnapshot is Ownable, Pausable {
    uint8 public constant MAX_SIGNAL = 5;
    uint16 public constant MAX_BPS = 10000;

    struct SnapshotHeader {
        uint256 snapshotId;
        uint256 portfolioCompositeScore;
        uint256 latestInstructionId;
        uint256 createdAt;
        uint256 positionCount;
        bytes32 sourceHash;
        address publisher;
        bool exists;
    }

    struct PositionSnapshot {
        string ticker;
        uint8 signal;
        uint8 compositeScore;
        uint8 riskScore;
        int256 targetWeightChangeBps;
        uint16 currentWeightBps;
        uint16 targetWeightBps;
    }

    address public snapshotPublisher;
    uint256 public latestSnapshotId;
    uint256 public totalSnapshots;
    uint256 public lastSnapshotTimestamp;

    mapping(uint256 => SnapshotHeader) private snapshotHeaders;
    mapping(uint256 => PositionSnapshot[]) private snapshotPositions;

    error InvalidAddress();
    error InvalidArrayLength();
    error InvalidTicker();
    error DuplicateTicker();
    error InvalidSignal();
    error InvalidScore();
    error InvalidWeight();
    error SnapshotNotFound();
    error PositionNotFound();
    error NotAuthorizedPublisher();

    event SnapshotPublisherUpdated(address indexed previousPublisher, address indexed newPublisher);
    event SnapshotCreated(
        uint256 indexed snapshotId,
        uint256 portfolioCompositeScore,
        uint256 latestInstructionId,
        uint256 positionCount,
        bytes32 indexed sourceHash,
        address indexed publisher,
        uint256 createdAt
    );
    event PositionRecorded(
        uint256 indexed snapshotId,
        uint256 indexed positionIndex,
        string ticker,
        uint8 signal,
        uint8 compositeScore,
        uint8 riskScore,
        int256 targetWeightChangeBps,
        uint16 currentWeightBps,
        uint16 targetWeightBps
    );
    event SnapshotPaused(uint256 timestamp);
    event SnapshotResumed(uint256 timestamp);

    modifier onlyPublisher() {
        if (msg.sender != owner() && msg.sender != snapshotPublisher) {
            revert NotAuthorizedPublisher();
        }
        _;
    }

    constructor(address initialOwner, address initialPublisher) {
        if (initialOwner == address(0)) revert InvalidAddress();
        if (initialOwner != msg.sender) {
            transferOwnership(initialOwner);
        }
        if (initialPublisher != address(0)) {
            snapshotPublisher = initialPublisher;
            emit SnapshotPublisherUpdated(address(0), initialPublisher);
        }
    }

    function setSnapshotPublisher(address newPublisher) external onlyOwner {
        if (newPublisher == address(0)) revert InvalidAddress();
        address previousPublisher = snapshotPublisher;
        snapshotPublisher = newPublisher;
        emit SnapshotPublisherUpdated(previousPublisher, newPublisher);
    }

    function clearSnapshotPublisher() external onlyOwner {
        address previousPublisher = snapshotPublisher;
        snapshotPublisher = address(0);
        emit SnapshotPublisherUpdated(previousPublisher, address(0));
    }

    function createSnapshot(
        uint256 portfolioCompositeScore,
        uint256 latestInstructionId,
        bytes32 sourceHash,
        string[] calldata tickers,
        uint8[] calldata signals,
        uint8[] calldata compositeScores,
        uint8[] calldata riskScores,
        int256[] calldata targetWeightChangesBps,
        uint16[] calldata currentWeightsBps,
        uint16[] calldata targetWeightsBps
    ) external onlyPublisher whenNotPaused returns (uint256 snapshotId) {
        uint256 count = tickers.length;
        if (
            count == 0 ||
            signals.length != count ||
            compositeScores.length != count ||
            riskScores.length != count ||
            targetWeightChangesBps.length != count ||
            currentWeightsBps.length != count ||
            targetWeightsBps.length != count
        ) {
            revert InvalidArrayLength();
        }
        if (portfolioCompositeScore > 100) revert InvalidScore();

        uint256 totalCurrent;
        uint256 totalTarget;

        for (uint256 i = 0; i < count; i++) {
            if (bytes(tickers[i]).length == 0) revert InvalidTicker();
            for (uint256 j = 0; j < i; j++) {
                if (keccak256(bytes(tickers[i])) == keccak256(bytes(tickers[j]))) revert DuplicateTicker();
            }
            if (signals[i] > MAX_SIGNAL) revert InvalidSignal();
            if (compositeScores[i] > 100 || riskScores[i] > 100) revert InvalidScore();
            if (
                currentWeightsBps[i] > MAX_BPS ||
                targetWeightsBps[i] > MAX_BPS ||
                targetWeightChangesBps[i] < -10000 ||
                targetWeightChangesBps[i] > 10000
            ) {
                revert InvalidWeight();
            }
            totalCurrent += currentWeightsBps[i];
            totalTarget += targetWeightsBps[i];
        }

        if (totalCurrent > MAX_BPS || totalTarget > MAX_BPS) revert InvalidWeight();

        snapshotId = ++latestSnapshotId;
        totalSnapshots++;
        lastSnapshotTimestamp = block.timestamp;

        snapshotHeaders[snapshotId] = SnapshotHeader(
            snapshotId,
            portfolioCompositeScore,
            latestInstructionId,
            block.timestamp,
            count,
            sourceHash,
            msg.sender,
            true
        );

        for (uint256 i = 0; i < count; i++) {
            snapshotPositions[snapshotId].push(
                PositionSnapshot(
                    tickers[i],
                    signals[i],
                    compositeScores[i],
                    riskScores[i],
                    targetWeightChangesBps[i],
                    currentWeightsBps[i],
                    targetWeightsBps[i]
                )
            );
            emit PositionRecorded(
                snapshotId,
                i,
                tickers[i],
                signals[i],
                compositeScores[i],
                riskScores[i],
                targetWeightChangesBps[i],
                currentWeightsBps[i],
                targetWeightsBps[i]
            );
        }

        emit SnapshotCreated(
            snapshotId,
            portfolioCompositeScore,
            latestInstructionId,
            count,
            sourceHash,
            msg.sender,
            block.timestamp
        );
    }

    function getSnapshotHeader(uint256 snapshotId) external view returns (SnapshotHeader memory) {
        _requiresSnapshot(snapshotId);
        return snapshotHeaders[snapshotId];
    }

    function getPositionCount(uint256 snapshotId) external view returns (uint256) {
        _requiresSnapshot(snapshotId);
        return snapshotPositions[snapshotId].length;
    }

    function getPosition(uint256 snapshotId, uint256 positionIndex) external view returns (PositionSnapshot memory) {
        _requiresSnapshot(snapshotId);
        if (positionIndex >= snapshotPositions[snapshotId].length) revert PositionNotFound();
        return snapshotPositions[snapshotId][positionIndex];
    }

    function getPositions(uint256 snapshotId) external view returns (PositionSnapshot[] memory) {
        _requiresSnapshot(snapshotId);
        return snapshotPositions[snapshotId];
    }

    function getLatestSnapshotHeader() external view returns (SnapshotHeader memory) {
        _requiresSnapshot(latestSnapshotId);
        return snapshotHeaders[latestSnapshotId];
    }

    function snapshotExists(uint256 snapshotId) external view returns (bool) {
        return snapshotHeaders[snapshotId].exists;
    }

    function pause() external onlyOwner {
        _pause();
        emit SnapshotPaused(block.timestamp);
    }

    function unpause() external onlyOwner {
        _unpause();
        emit SnapshotResumed(block.timestamp);
    }

    function _requiresSnapshot(uint256 snapshotId) internal view {
        if (!snapshotHeaders[snapshotId].exists) revert SnapshotNotFound();
    }
}
