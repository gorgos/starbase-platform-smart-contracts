pragma solidity 0.4.23;

import "zeppelin-solidity/contracts/lifecycle/Pausable.sol";
import "./custom-zeppelin-solidity/FinalizableCrowdsale.sol";
import "./CompanyToken.sol";
import "./Whitelist.sol";


/**
 * @title Token Sale contract - crowdsale of company tokens.
 * @author Gustavo Guimaraes - <gustavo@starbase.co>
 */
contract TokenSale is FinalizableCrowdsale, Pausable {
    uint256 public crowdsaleCap;
    // amount of raised money in STAR
    uint256 public starRaised;
    uint256 public starRate;
    address public initialTokenOwner;
    bool public enableWei;

    // external contracts
    Whitelist public whitelist;
    StandardToken public starToken;

    event TokenRateChanged(uint256 previousRate, uint256 newRate);
    event TokenStarRateChanged(uint256 previousStarRate, uint256 newStarRate);
    event TokenPurchaseWithStar(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);

    /**
     * @dev Contract constructor function
     * @param _startTime The timestamp of the beginning of the crowdsale
     * @param _endTime Timestamp when the crowdsale will finish
     * @param _whitelist contract containing the whitelisted addresses
     * @param _starToken STAR token contract address
     * @param _companyToken ERC20 CompanyToken contract address
     * @param _rate The token rate per ETH
     * @param _starRate The token rate per STAR
     * @param _wallet Multisig wallet that will hold the crowdsale funds.
     * @param _crowdsaleCap Cap for the token sale
     */
    constructor(
            uint256 _startTime,
            uint256 _endTime,
            address _whitelist,
            address _starToken,
            address _companyToken,
            uint256 _rate,
            uint256 _starRate,
            address _wallet,
            uint256 _crowdsaleCap
        )
        public
        FinalizableCrowdsale()
        Crowdsale(_startTime, _endTime, _rate, _wallet)
    {
        require(
                _whitelist != address(0) &&
                _starToken != address(0) &&
                _starRate != 0 &&
                _companyToken != address(0) &&
                _crowdsaleCap != 0
        );

        tokenOnSale = CompanyToken(_companyToken);
        whitelist = Whitelist(_whitelist);
        starToken = StandardToken(_starToken);
        starRate = _starRate;

        initialTokenOwner = CompanyToken(tokenOnSale).owner();
        uint256 tokenDecimals = CompanyToken(tokenOnSale).decimals();
        crowdsaleCap = _crowdsaleCap.mul(10 ** tokenDecimals);

        require(CompanyToken(tokenOnSale).paused());
    }

    modifier isWhitelisted(address beneficiary) {
        require(whitelist.allowedAddresses(beneficiary));
        _;
    }

    modifier crowdsaleIsTokenOwner() {
        // token owner should be contract address
        require(tokenOnSale.owner() == address(this));
        _;
    }

    /**
     * @dev override fallback function. cannot use it
     */
    function () external payable {
        revert();
    }

    /**
     * @dev change crowdsale ETH rate
     * @param newRate Figure that corresponds to the new ETH rate per token
     */
    function setRate(uint256 newRate) external onlyOwner {
        require(newRate != 0);

        emit TokenRateChanged(rate, newRate);
        rate = newRate;
    }

    /**
     * @dev change crowdsale STAR rate
     * @param newStarRate Figure that corresponds to the new STAR rate per token
     */
    function setStarRate(uint256 newStarRate) external onlyOwner {
        require(newStarRate != 0);

        emit TokenStarRateChanged(starRate, newStarRate);
        starRate = newStarRate;
    }

    /**
     * @dev enable sale to receive
     */
    function toggleEnableWei() external onlyOwner {
        enableWei = !enableWei;
    }

    /**
     * @dev function that allows token purchases with STAR
     * @param beneficiary Address of the purchaser
     */
    function buyTokens(address beneficiary)
        public
        payable
        whenNotPaused
        isWhitelisted(beneficiary)
        crowdsaleIsTokenOwner
    {
        require(beneficiary != address(0));
        require(validPurchase() && tokenOnSale.totalSupply() < crowdsaleCap);

        if (!enableWei) {
            require(msg.value == 0);
        } else if (msg.value > 0) {
            buyTokensWithWei(beneficiary);
        }

        // beneficiary must allow TokenSale address to transfer star tokens on its behalf
        uint256 starAllocationToTokenSale = starToken.allowance(beneficiary, this);
        if (starAllocationToTokenSale > 0) {
            // calculate token amount to be created
            uint256 tokens = starAllocationToTokenSale.mul(starRate);

            //remainder logic
            if (tokenOnSale.totalSupply().add(tokens) > crowdsaleCap) {
                tokens = crowdsaleCap.sub(tokenOnSale.totalSupply());

                starAllocationToTokenSale = tokens.div(starRate);
            }

            // update state
            starRaised = starRaised.add(starAllocationToTokenSale);

            tokenOnSale.mint(beneficiary, tokens);
            emit TokenPurchaseWithStar(msg.sender, beneficiary, starAllocationToTokenSale, tokens);

            // forward funds
            starToken.transferFrom(beneficiary, wallet, starAllocationToTokenSale);
        }
    }

    /**
     * @dev function that allows token purchases with Wei
     * @param beneficiary Address of the purchaser
     */
    function buyTokensWithWei(address beneficiary)
        internal
    {
        uint256 weiAmount = msg.value;
        uint256 weiRefund = 0;

        // calculate token amount to be created
        uint256 tokens = weiAmount.mul(rate);

        //remainder logic
        if (tokenOnSale.totalSupply().add(tokens) > crowdsaleCap) {
            tokens = crowdsaleCap.sub(tokenOnSale.totalSupply());
            weiAmount = tokens.div(rate);

            weiRefund = msg.value.sub(weiAmount);
        }

        // update state
        weiRaised = weiRaised.add(weiAmount);

        tokenOnSale.mint(beneficiary, tokens);
        emit TokenPurchase(msg.sender, beneficiary, weiAmount, tokens);

        wallet.transfer(weiAmount);
        if (weiRefund > 0) {
            msg.sender.transfer(weiRefund);
        }
    }

    // override Crowdsale#hasEnded to add cap logic
    // @return true if crowdsale event has ended
    function hasEnded() public view returns (bool) {
        if (tokenOnSale.totalSupply() >= crowdsaleCap) {
            return true;
        }

        return super.hasEnded();
    }

    /**
     * @dev override Crowdsale#validPurchase
     * @return true if the transaction can buy tokens
     */
    function validPurchase() internal view returns (bool) {
      return now >= startTime && now <= endTime;
    }

    /**
     * @dev finalizes crowdsale
     */
    function finalization() internal {
        if (crowdsaleCap > tokenOnSale.totalSupply()) {
            uint256 remainingTokens = crowdsaleCap.sub(tokenOnSale.totalSupply());

            tokenOnSale.mint(wallet, remainingTokens);
        }

        tokenOnSale.transferOwnership(initialTokenOwner);
        super.finalization();
    }
}
