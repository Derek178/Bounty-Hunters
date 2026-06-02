// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../contracts/PriceOracle.sol";

interface Vm {
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData) external;
    function expectRevert(bytes memory message) external;
    function prank(address sender) external;
    function warp(uint256 timestamp) external;
}

contract MockAggregatorV3 is AggregatorV3Interface {
    uint80 public roundId = 1;
    int256 public answer = 1000;
    uint256 public startedAt = 1;
    uint256 public updatedAt = 1;
    uint80 public answeredInRound = 1;
    uint8 private immutable feedDecimals;

    constructor(uint8 _decimals) {
        feedDecimals = _decimals;
    }

    function setRoundData(
        uint80 _roundId,
        int256 _answer,
        uint256 _startedAt,
        uint256 _updatedAt,
        uint80 _answeredInRound
    ) external {
        roundId = _roundId;
        answer = _answer;
        startedAt = _startedAt;
        updatedAt = _updatedAt;
        answeredInRound = _answeredInRound;
    }

    function latestRoundData() external view returns (
        uint80,
        int256,
        uint256,
        uint256,
        uint80
    ) {
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    function decimals() external view returns (uint8) {
        return feedDecimals;
    }
}

contract PriceOracleTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    event StalePrice(address indexed feed, uint256 updatedAt);

    function testReturnsValidPrimaryPrice() public {
        vm.warp(10_000);

        MockAggregatorV3 primary = new MockAggregatorV3(8);
        primary.setRoundData(7, 1234, 9_990, 9_990, 7);

        PriceOracle oracle = new PriceOracle(address(primary));

        assert(oracle.getLatestPrice() == 1234);
        assert(oracle.getDecimals() == 8);
    }

    function testStalePrimaryFallsBackAndEmitsEvent() public {
        vm.warp(10_000);

        MockAggregatorV3 primary = new MockAggregatorV3(8);
        MockAggregatorV3 fallbackOracle = new MockAggregatorV3(8);
        primary.setRoundData(7, 1234, 5_000, 5_000, 7);
        fallbackOracle.setRoundData(8, 4321, 9_990, 9_990, 8);

        PriceOracle oracle = new PriceOracle(address(primary));
        oracle.setFallbackFeed(address(fallbackOracle));

        vm.expectEmit(true, false, false, true);
        emit StalePrice(address(primary), 5_000);

        assert(oracle.getLatestPrice() == 4321);
    }

    function testNegativePrimaryPriceReverts() public {
        vm.warp(10_000);

        MockAggregatorV3 primary = new MockAggregatorV3(8);
        primary.setRoundData(7, -1, 9_990, 9_990, 7);

        PriceOracle oracle = new PriceOracle(address(primary));

        vm.expectRevert(bytes("Invalid price"));
        oracle.getLatestPrice();
    }

    function testIncompleteRoundReverts() public {
        vm.warp(10_000);

        MockAggregatorV3 primary = new MockAggregatorV3(8);
        primary.setRoundData(7, 1234, 9_990, 9_990, 6);

        PriceOracle oracle = new PriceOracle(address(primary));

        vm.expectRevert(bytes("Incomplete round"));
        oracle.getLatestPrice();
    }

    function testBothOraclesStaleReverts() public {
        vm.warp(10_000);

        MockAggregatorV3 primary = new MockAggregatorV3(8);
        MockAggregatorV3 fallbackOracle = new MockAggregatorV3(8);
        primary.setRoundData(7, 1234, 5_000, 5_000, 7);
        fallbackOracle.setRoundData(8, 4321, 5_100, 5_100, 8);

        PriceOracle oracle = new PriceOracle(address(primary));
        oracle.setFallbackFeed(address(fallbackOracle));

        vm.expectRevert(bytes("Stale price"));
        oracle.getLatestPrice();
    }

    function testOnlyOwnerCanUpdateMaxStaleness() public {
        MockAggregatorV3 primary = new MockAggregatorV3(8);
        PriceOracle oracle = new PriceOracle(address(primary));

        oracle.setMaxStaleness(7200);
        assert(oracle.MAX_STALENESS() == 7200);

        vm.prank(address(0xBEEF));
        vm.expectRevert(bytes("Not owner"));
        oracle.setMaxStaleness(3600);
    }
}
