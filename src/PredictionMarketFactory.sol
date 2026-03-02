// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { PredictionMarket } from "./PredictionMarket.sol";
import { IPredictionMarketFactory } from "./interfaces/IPredictionMarketFactory.sol";

/**
 * @title PredictionMarketFactory
 * @notice Factory contract for creating and managing prediction markets
 * @dev Supports multiple market types, categories, and resolution mechanisms
 */
contract PredictionMarketFactory is IPredictionMarketFactory {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Platform fee in basis points (max 5%)
    uint16 public platformFeeBps;
    
    /// @notice Platform fee recipient
    address public feeRecipient;
    
    /// @notice Factory owner
    address public owner;
    
    /// @notice Minimum market duration (e.g., 1 hour)
    uint256 public minMarketDuration = 1 hours;
    
    /// @notice Maximum market duration (e.g., 1 year)
    uint256 public maxMarketDuration = 365 days;
    
    /// @notice Minimum initial liquidity required
    uint256 public minInitialLiquidity = 0.01 ether;
    
    /// @notice All created markets
    address[] public allMarkets;
    
    /// @notice Market address => market info
    mapping(address => MarketInfo) public marketInfo;
    
    /// @notice Category => market addresses
    mapping(string => address[]) public marketsByCategory;
    
    /// @notice Creator => market addresses
    mapping(address => address[]) public marketsByCreator;
    
    /// @notice Resolver => market addresses
    mapping(address => address[]) public marketsByResolver;
    
    /// @notice Approved resolvers
    mapping(address => bool) public approvedResolvers;
    
    /// @notice Market templates
    mapping(bytes32 => MarketTemplate) public marketTemplates;
    
    /// @notice Template names array
    bytes32[] public templateNames;

    struct MarketTemplate {
        string name;
        string description;
        MarketType marketType;
        uint256 suggestedDuration;
        bool requiresOracle;
        bool active;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event MarketCreated(
        address indexed marketAddress,
        address indexed creator,
        address indexed resolver,
        string question,
        string category,
        MarketType marketType,
        uint256 endTime
    );

    event PlatformFeeUpdated(uint16 oldFee, uint16 newFee);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);
    event ResolverApproved(address indexed resolver, bool approved);
    event TemplateAdded(bytes32 indexed templateId, string name);
    event TemplateUpdated(bytes32 indexed templateId);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error Unauthorized();
    error InvalidFee();
    error InvalidDuration();
    error InvalidLiquidity();
    error ResolverNotApproved();
    error MarketNotFound();
    error InvalidTemplate();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _feeRecipient, uint16 _platformFeeBps) {
        require(_feeRecipient != address(0), "Invalid recipient");
        require(_platformFeeBps <= 500, "Fee too high"); // Max 5%
        
        owner = msg.sender;
        feeRecipient = _feeRecipient;
        platformFeeBps = _platformFeeBps;
        
        // Approve owner as default resolver
        approvedResolvers[msg.sender] = true;
        
        // Add default templates
        _addDefaultTemplates();
    }

    /*//////////////////////////////////////////////////////////////
                            MARKET CREATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Create a new binary prediction market
     * @param question The market question
     * @param description Detailed description
     * @param category Market category (e.g., "Sports", "Politics")
     * @param subcategory Subcategory (e.g., "Football", "US Elections")
     * @param resolver Address that will resolve the market
     * @param endTime When the market closes for trading
     * @param resolutionTime When the market can be resolved
     * @param initialLiquidity Initial liquidity in ETH
     * @return market Address of the created market
     */
    function createBinaryMarket(
        string calldata question,
        string calldata description,
        string calldata category,
        string calldata subcategory,
        address resolver,
        uint256 endTime,
        uint256 resolutionTime,
        uint256 initialLiquidity
    ) external payable returns (address market) {
        _validateMarketParams(resolver, endTime, resolutionTime, initialLiquidity);
        
        // Create market contract
        PredictionMarket newMarket = new PredictionMarket(
            question,
            description,
            msg.sender,
            resolver,
            endTime,
            resolutionTime,
            platformFeeBps,
            feeRecipient
        );
        
        market = address(newMarket);
        
        // Initialize with liquidity if provided
        if (initialLiquidity > 0) {
            require(msg.value >= initialLiquidity, "Insufficient ETH");
            newMarket.addInitialLiquidity{value: initialLiquidity}();
            
            // Refund excess
            if (msg.value > initialLiquidity) {
                payable(msg.sender).transfer(msg.value - initialLiquidity);
            }
        }
        
        // Store market info
        _registerMarket(
            market,
            msg.sender,
            resolver,
            category,
            subcategory,
            MarketType.BINARY
        );
        
        emit MarketCreated(
            market,
            msg.sender,
            resolver,
            question,
            category,
            MarketType.BINARY,
            endTime
        );
        
        return market;
    }

    /**
     * @notice Create market from template
     */
    function createFromTemplate(
        bytes32 templateId,
        string calldata question,
        string calldata description,
        address resolver,
        uint256 endTime,
        string calldata category,
        string calldata subcategory
    ) public payable returns (address market) {
        MarketTemplate storage template = marketTemplates[templateId];
        require(template.active, "Template inactive");
        
        uint256 resolutionTime = endTime + 1 days; // Default 1 day after end
        
        return this.createBinaryMarket(
            question,
            description,
            category,
            subcategory,
            resolver,
            endTime,
            resolutionTime,
            minInitialLiquidity
        );
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setPlatformFee(uint16 newFeeBps) external {
        require(msg.sender == owner, Unauthorized());
        require(newFeeBps <= 500, InvalidFee()); // Max 5%
        
        uint16 oldFee = platformFeeBps;
        platformFeeBps = newFeeBps;
        
        emit PlatformFeeUpdated(oldFee, newFeeBps);
    }

    function setFeeRecipient(address newRecipient) external {
        require(msg.sender == owner, Unauthorized());
        require(newRecipient != address(0), "Invalid recipient");
        
        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;
        
        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }

    function approveResolver(address resolver, bool approved) external {
        require(msg.sender == owner, Unauthorized());
        approvedResolvers[resolver] = approved;
        emit ResolverApproved(resolver, approved);
    }

    function setMinMarketDuration(uint256 duration) external {
        require(msg.sender == owner, Unauthorized());
        minMarketDuration = duration;
    }

    function setMaxMarketDuration(uint256 duration) external {
        require(msg.sender == owner, Unauthorized());
        maxMarketDuration = duration;
    }

    function setMinInitialLiquidity(uint256 amount) external {
        require(msg.sender == owner, Unauthorized());
        minInitialLiquidity = amount;
    }

    function transferOwnership(address newOwner) external {
        require(msg.sender == owner, Unauthorized());
        require(newOwner != address(0), "Invalid owner");
        owner = newOwner;
    }

    /*//////////////////////////////////////////////////////////////
                        TEMPLATE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function addTemplate(
        string calldata name,
        string calldata description,
        MarketType marketType,
        uint256 suggestedDuration,
        bool requiresOracle
    ) external {
        require(msg.sender == owner, Unauthorized());
        
        string memory name_ = name;
        bytes32 templateId;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, name_)
            mstore(add(ptr, mload(name_)), timestamp())
            templateId := keccak256(ptr, add(mload(name_), 32))
            mstore(0x40, add(ptr, add(mload(name_), 32)))
        }
        
        marketTemplates[templateId] = MarketTemplate({
            name: name,
            description: description,
            marketType: marketType,
            suggestedDuration: suggestedDuration,
            requiresOracle: requiresOracle,
            active: true
        });
        
        templateNames.push(templateId);
        
        emit TemplateAdded(templateId, name);
    }

    function updateTemplate(bytes32 templateId, bool active) external {
        require(msg.sender == owner, Unauthorized());
        require(bytes(marketTemplates[templateId].name).length > 0, InvalidTemplate());
        
        marketTemplates[templateId].active = active;
        emit TemplateUpdated(templateId);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getAllMarkets() external view returns (address[] memory) {
        return allMarkets;
    }

    function getMarketsByCategory(string calldata category) 
        external 
        view 
        returns (address[] memory) 
    {
        return marketsByCategory[category];
    }

    function getMarketsByCreator(address creator) 
        external 
        view 
        returns (address[] memory) 
    {
        return marketsByCreator[creator];
    }

    function getMarketsByResolver(address resolver) 
        external 
        view 
        returns (address[] memory) 
    {
        return marketsByResolver[resolver];
    }

    function getTotalMarkets() external view returns (uint256) {
        return allMarkets.length;
    }

    function getMarketInfo(address market) 
        external 
        view 
        returns (MarketInfo memory) 
    {
        return marketInfo[market];
    }

    function getAllTemplates() external view returns (bytes32[] memory) {
        return templateNames;
    }

    function getTemplate(bytes32 templateId) 
        external 
        view 
        returns (MarketTemplate memory) 
    {
        return marketTemplates[templateId];
    }

    function getActiveMarkets(uint256 offset, uint256 limit) 
        external 
        view 
        returns (address[] memory markets, uint256 total) 
    {
        total = allMarkets.length;
        
        if (offset >= total) {
            return (new address[](0), total);
        }
        
        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }
        
        uint256 resultSize = end - offset;
        markets = new address[](resultSize);
        
        for (uint256 i = 0; i < resultSize; i++) {
            markets[i] = allMarkets[offset + i];
        }
        
        return (markets, total);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _validateMarketParams(
        address resolver,
        uint256 endTime,
        uint256 resolutionTime,
        uint256 initialLiquidity
    ) internal view {
        require(approvedResolvers[resolver] || resolver == msg.sender, 
            ResolverNotApproved());
        
        uint256 duration = endTime - block.timestamp;
        require(duration >= minMarketDuration && duration <= maxMarketDuration, 
            InvalidDuration());
        
        require(resolutionTime > endTime, "Invalid resolution time");
        
        if (initialLiquidity > 0) {
            require(initialLiquidity >= minInitialLiquidity, InvalidLiquidity());
        }
    }

    function _registerMarket(
        address market,
        address creator,
        address resolver,
        string calldata category,
        string calldata subcategory,
        MarketType marketType
    ) internal {
        allMarkets.push(market);
        
        marketInfo[market] = MarketInfo({
            creator: creator,
            resolver: resolver,
            category: category,
            subcategory: subcategory,
            createdAt: block.timestamp,
            isActive: true,
            marketType: marketType
        });
        
        marketsByCategory[category].push(market);
        marketsByCreator[creator].push(market);
        marketsByResolver[resolver].push(market);
    }

    function _addDefaultTemplates() internal {
        // Sports template
        bytes32 sportId;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, "sports")
            mstore(add(ptr, 6), timestamp())
            sportId := keccak256(ptr, 38)
            mstore(0x40, add(ptr, 38))
        }
        marketTemplates[sportId] = MarketTemplate({
            name: "Sports Match",
            description: "Will team X win against team Y?",
            marketType: MarketType.BINARY,
            suggestedDuration: 7 days,
            requiresOracle: true,
            active: true
        });
        templateNames.push(sportId);

        // Price prediction template
        bytes32 priceId;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, "price")
            mstore(add(ptr, 5), add(timestamp(), 1))
            priceId := keccak256(ptr, 37)
            mstore(0x40, add(ptr, 37))
        }
        marketTemplates[priceId] = MarketTemplate({
            name: "Price Prediction",
            description: "Will asset X reach price Y by date Z?",
            marketType: MarketType.BINARY,
            suggestedDuration: 30 days,
            requiresOracle: true,
            active: true
        });
        templateNames.push(priceId);

        // Event outcome template
        bytes32 eventId;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, "event")
            mstore(add(ptr, 5), add(timestamp(), 2))
            eventId := keccak256(ptr, 37)
            mstore(0x40, add(ptr, 37))
        }
        marketTemplates[eventId] = MarketTemplate({
            name: "Event Outcome",
            description: "Will event X happen by date Y?",
            marketType: MarketType.BINARY,
            suggestedDuration: 14 days,
            requiresOracle: false,
            active: true
        });
        templateNames.push(eventId);
    }

    receive() external payable {}
}
