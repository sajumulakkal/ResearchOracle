// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ResearchOracle
 * @notice Integrated research oracle covering Phase 0 to Phase 3.
 *
 * Covers:
 * - Phase 0: Basic research data publishing
 * - Phase 1: Research hash, versioning, oracle node signatures
 * - Phase 2: Enhanced research factors and composite score
 * - Phase 3: Multi-asset ticker support
 */
library SimpleECDSAIntegrated {
    function recover(bytes32 ethSignedMessageHash, bytes memory signature)
        internal
        pure
        returns (address)
    {
        require(signature.length == 65, "Invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly ("memory-safe") {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        if (v < 27) {
            v += 27;
        }
        require(v == 27 || v == 28, "Invalid signature v");

        address signer = ecrecover(ethSignedMessageHash, v, r, s);
        require(signer != address(0), "Invalid signer");

        return signer;
    }

    function toEthSignedMessageHash(bytes32 hash)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
        );
    }
}

contract ResearchOracle {
    using SimpleECDSAIntegrated for bytes32;

    struct ResearchInput {
        string ticker;
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
        uint256 version;
    }

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

    address public owner;

    uint256 public latestGlobalRoundId;

    uint256 public requiredSignatures;
    uint256 public oracleNodeCount;

    string[] private tickers;

    mapping(address => bool) public oracleNodes;
    mapping(bytes32 => bool) public tickerExists;
    mapping(bytes32 => ResearchData) private latestResearchByTicker;

    event OracleNodeAdded(address indexed node);
    event OracleNodeRemoved(address indexed node);

    event RequiredSignaturesUpdated(
        uint256 oldValue,
        uint256 newValue
    );

    event TickerAdded(string ticker);

    event ResearchPublished(
        string ticker,
        uint256 indexed roundId,
        uint256 warrantedPrice,
        uint256 marketPrice,
        int256 valuationGapPct,
        uint8 compositeScore,
        uint8 riskScore,
        bytes32 researchHash,
        uint256 version,
        uint256 updatedAt
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(
        address[] memory initialOracleNodes,
        uint256 _requiredSignatures
    ) {
        owner = msg.sender;

        if (initialOracleNodes.length > 0) {
            require(_requiredSignatures > 0, "Invalid threshold");
            require(
                _requiredSignatures <= initialOracleNodes.length,
                "Threshold too high"
            );

            requiredSignatures = _requiredSignatures;

            for (uint256 i = 0; i < initialOracleNodes.length; i++) {
                address node = initialOracleNodes[i];

                require(node != address(0), "Invalid oracle node");
                require(!oracleNodes[node], "Duplicate oracle node");

                oracleNodes[node] = true;
                oracleNodeCount++;

                emit OracleNodeAdded(node);
            }
        }
    }

    function addOracleNode(address node) external onlyOwner {
        require(node != address(0), "Invalid oracle node");
        require(!oracleNodes[node], "Already oracle node");

        oracleNodes[node] = true;
        oracleNodeCount++;

        emit OracleNodeAdded(node);
    }

    function removeOracleNode(address node) external onlyOwner {
        require(oracleNodes[node], "Not oracle node");

        if (requiredSignatures > 0) {
            require(
                oracleNodeCount - 1 >= requiredSignatures,
                "Would break threshold"
            );
        }

        oracleNodes[node] = false;
        oracleNodeCount--;

        emit OracleNodeRemoved(node);
    }

    function updateRequiredSignatures(uint256 newRequiredSignatures)
        external
        onlyOwner
    {
        require(newRequiredSignatures > 0, "Invalid threshold");
        require(
            newRequiredSignatures <= oracleNodeCount,
            "Threshold too high"
        );

        uint256 oldValue = requiredSignatures;
        requiredSignatures = newRequiredSignatures;

        emit RequiredSignaturesUpdated(oldValue, newRequiredSignatures);
    }

    function publishResearchData(ResearchInput calldata input)
        external
        onlyOwner
    {
        _publishResearchData(input);
    }

    function publishSignedResearchData(
        ResearchInput calldata input,
        uint256 signedAt,
        bytes[] calldata signatures
    ) external {
        require(requiredSignatures > 0, "Signature threshold not set");
        require(signatures.length >= requiredSignatures, "Not enough sigs");

        bytes32 researchHash = _computeResearchHash(input);

        bytes32 messageHash = getMessageHash(
            input.ticker,
            researchHash,
            input.version,
            signedAt
        );

        bytes32 ethSignedHash = messageHash.toEthSignedMessageHash();

        address[] memory seenSigners = new address[](signatures.length);
        uint256 validSignatureCount = 0;

        for (uint256 i = 0; i < signatures.length; i++) {
            address recoveredSigner = SimpleECDSAIntegrated.recover(
                ethSignedHash,
                signatures[i]
            );

            if (!oracleNodes[recoveredSigner]) {
                continue;
            }

            bool duplicate = false;

            for (uint256 j = 0; j < validSignatureCount; j++) {
                if (seenSigners[j] == recoveredSigner) {
                    duplicate = true;
                    break;
                }
            }

            if (duplicate) {
                continue;
            }

            seenSigners[validSignatureCount] = recoveredSigner;
            validSignatureCount++;
        }

        require(
            validSignatureCount >= requiredSignatures,
            "Insufficient valid signatures"
        );

        _publishResearchData(input);
    }

    function latestResearchData(string calldata ticker)
        external
        view
        returns (ResearchData memory)
    {
        return latestResearchByTicker[_tickerKey(ticker)];
    }

    function getTickers() external view returns (string[] memory) {
        return tickers;
    }

    function getTickerCount() external view returns (uint256) {
        return tickers.length;
    }

    function computeResearchHash(ResearchInput calldata input)
        external
        pure
        returns (bytes32)
    {
        return _computeResearchHash(input);
    }

    function getMessageHash(
        string memory ticker,
        bytes32 researchHash,
        uint256 version,
        uint256 signedAt
    ) public view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                address(this),
                block.chainid,
                ticker,
                researchHash,
                version,
                signedAt
            )
        );
    }

    function _publishResearchData(ResearchInput calldata input) internal {
        require(bytes(input.ticker).length > 0, "Ticker required");
        require(input.warrantedPrice > 0, "Invalid warranted price");
        require(input.marketPrice > 0, "Invalid market price");
        require(input.version > 0, "Invalid version");

        _validateScore(input.qualityScore);
        _validateScore(input.cfroiScore);
        _validateScore(input.businessResilienceScore);
        _validateScore(input.accountingQualityScore);
        _validateScore(input.riskScore);
        _validateScore(input.momentumScore);
        _validateScore(input.esgScore);

        uint8 compositeScore = _calculateCompositeScore(
            input.qualityScore,
            input.cfroiScore,
            input.businessResilienceScore,
            input.accountingQualityScore,
            input.riskScore,
            input.momentumScore,
            input.esgScore
        );

        bytes32 researchHash = _computeResearchHash(input);

        latestGlobalRoundId++;

        bytes32 tickerKey = _tickerKey(input.ticker);

        if (!tickerExists[tickerKey]) {
            tickerExists[tickerKey] = true;
            tickers.push(input.ticker);

            emit TickerAdded(input.ticker);
        }

        latestResearchByTicker[tickerKey] = ResearchData({
            ticker: input.ticker,
            roundId: latestGlobalRoundId,
            warrantedPrice: input.warrantedPrice,
            marketPrice: input.marketPrice,
            valuationGapPct: input.valuationGapPct,
            qualityScore: input.qualityScore,
            cfroiScore: input.cfroiScore,
            businessResilienceScore: input.businessResilienceScore,
            accountingQualityScore: input.accountingQualityScore,
            riskScore: input.riskScore,
            momentumScore: input.momentumScore,
            esgScore: input.esgScore,
            compositeScore: compositeScore,
            researchHash: researchHash,
            version: input.version,
            updatedAt: block.timestamp,
            valid: true
        });

        emit ResearchPublished(
            input.ticker,
            latestGlobalRoundId,
            input.warrantedPrice,
            input.marketPrice,
            input.valuationGapPct,
            compositeScore,
            input.riskScore,
            researchHash,
            input.version,
            block.timestamp
        );
    }

    function _computeResearchHash(ResearchInput calldata input)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                input.ticker,
                input.warrantedPrice,
                input.marketPrice,
                input.valuationGapPct,
                input.qualityScore,
                input.cfroiScore,
                input.businessResilienceScore,
                input.accountingQualityScore,
                input.riskScore,
                input.momentumScore,
                input.esgScore,
                input.version
            )
        );
    }

    function _calculateCompositeScore(
        uint8 qualityScore,
        uint8 cfroiScore,
        uint8 businessResilienceScore,
        uint8 accountingQualityScore,
        uint8 riskScore,
        uint8 momentumScore,
        uint8 esgScore
    ) internal pure returns (uint8) {
        uint256 invertedRiskScore = 100 - riskScore;

        uint256 total =
            uint256(qualityScore) +
            uint256(cfroiScore) +
            uint256(businessResilienceScore) +
            uint256(accountingQualityScore) +
            invertedRiskScore +
            uint256(momentumScore) +
            uint256(esgScore);

        return uint8(total / 7);
    }

    function _validateScore(uint8 score) internal pure {
        require(score <= 100, "Invalid score");
    }

    function _tickerKey(string memory ticker) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(ticker));
    }
}