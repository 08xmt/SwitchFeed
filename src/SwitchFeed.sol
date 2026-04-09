pragma solidity ^0.8.24;

interface IChainlinkFeed {
    function decimals() external view returns (uint8 decimals);

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 price,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function latestAnswer() external view returns (int256 price);

    function description() external view returns (string memory description);
}

//Pass through price feed that can dynamically switch between different chainlink-like feeds
contract SwitchFeed is IChainlinkFeed{
    
    address public operator;
    address public pendingOperator;
    uint8 public immutable decimals;
    int32 public immutable MAX_PRICE_DIVERGENCE_BPS;

    IChainlinkFeed public feed;

    event SwitchedFeed(address newFeed);
    event NewOperator(address newOperator);
    event NewPendingOperator(address newPendingOperator);
    
    constructor(address _feed, address _operator, int32 _maxPriceDivergenceBps) {
        require(_maxPriceDivergenceBps >= 0, "Cannot be negative");
        require(_feed != address(0));
        require(_operator != address(0));
        operator = _operator;
        feed = IChainlinkFeed(_feed);
        decimals = feed.decimals();
        MAX_PRICE_DIVERGENCE_BPS = _maxPriceDivergenceBps;
    }

    function latestRoundData() external view returns(uint80, int256, uint256, uint256, uint80) {
        return feed.latestRoundData();
    }

    function latestAnswer() external view returns(int256) {
        return feed.latestAnswer();
    }

    function description() external view returns(string memory) {
        return feed.description();
    }
    
    //Important that operator is fully trusted, as a malicious operator can sidestep the price divergence guardrails;
    function switchFeed(address newFeed) external {
        require(msg.sender == operator, "Only operator");
        (,int curPrice,,,) = feed.latestRoundData();
        feed = IChainlinkFeed(newFeed);
        (,int newPrice,,,) = feed.latestRoundData();
        require(newPrice > 0, "New price must be positive");
        require(newPrice <= curPrice * (10000 + MAX_PRICE_DIVERGENCE_BPS) / 10000 &&
                newPrice >= curPrice * (10000 - MAX_PRICE_DIVERGENCE_BPS) / 10000,
                "New price diverge by more than max price divergence");
        //Check for matching decimals. Switching feeds between feeds with different decimals is dangerous
        require(feed.decimals() == decimals, "Mismatching decimals");
        emit SwitchedFeed(newFeed);
    }

    function setPendingOperator(address newOperator) external {
        require(msg.sender == operator, "Only operator");
        pendingOperator = newOperator;
        emit NewPendingOperator(newOperator);
    }

    function acceptOperator() external {
        require(msg.sender == pendingOperator, "Only pendingOperator");
        operator = pendingOperator;
        pendingOperator = address(0);
        emit NewOperator(operator);
    }
}
