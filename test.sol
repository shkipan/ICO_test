pragma solidity ^0.4.25;

import "./erc20.sol";
import "./ownable.sol";
import "./safemath.sol";
import "./roles.sol";

// ----------------------------------------------------------------------------
// Contract function to receive approval and execute function in one call
//
// Borrowed from MiniMeToken
// ----------------------------------------------------------------------------
contract ApproveAndCallFallBack {
    function receiveApproval(address from, uint256 tokens, address token, bytes data) public;
}

contract shkiToken is ERC20Interface, Owned, SafeMath {
    address public      admin;
    address public      fundKeeper;
    address public      portal;
    address public      team;
    address public      reserved;
    
    string public       symbol;
    string public       name;
    
    uint                _totalSupply;
    uint                maxSupply;
    
    uint                pricePrivateSale;
    uint                pricePreSale;
    uint                priceICOSale;
    uint                PrivateSaleBonus;
    uint                PreSaleBonus;
    uint                ICOBonus;
    
    uint public         startPrivateSaleTime;
    uint public         startPreSaleTime;
    uint public         startICOTime;
    
    uint8 public        decimals;
    bool                privateSalesStarted;
    bool                preSalesStarted;
    bool                icoStarted;
    bool                icoFinished;
    bool                contractActivated;
    bool                tokenTransfer = true;
    
    
    Roles.Role private  whitelist;
    Roles.Role private  privateInvestors;

    mapping(address => uint) balances;
    mapping(address => mapping(address => uint)) allowed;

    modifier OwnerAdmin() {
        require(msg.sender == owner || msg.sender == admin);
        _;
    }

    modifier OwnerAdminPortal() {
        require(msg.sender == owner || msg.sender == admin || msg.sender == portal);
        _;
    }


    // ------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------
    constructor() public onlyOwner() {
        symbol = "SKT";
        name = "shkiToken";
        decimals = 18;
        admin = owner;
        priceICOSale = 3000;
        pricePreSale = 3000;
        pricePrivateSale = 3000;
        PrivateSaleBonus = 6;
        PreSaleBonus = 3;
        ICOBonus = 2;
        maxSupply = 500000000;
    }

    // ------------------------------------------------------------------------
    // Total supply
    // ------------------------------------------------------------------------
    function totalSupply() public constant returns (uint) {
        return _totalSupply  - balances[address(0)];
    }
    
    // ------------------------------------------------------------------------
    // Withdraw money to fundkeeper
    // ------------------------------------------------------------------------
    function withdraw() public onlyOwner() {
        fundKeeper.transfer(_totalSupply);
    }

    // ------------------------------------------------------------------------
    // Get the token balance for account `tokenOwner`
    // ------------------------------------------------------------------------
    function balanceOf(address _tokenOwner) public constant returns (uint balance) {
        return balances[_tokenOwner];
    }
    
    // ------------------------------------------------------------------------
    // Get the token balance for account `tokenOwner`
    // ------------------------------------------------------------------------  
    function getCurrentState() public view returns (string) {
        if (!contractActivated) {
            return 'NotActivated';
        } 
        if (preSalesStarted) {
            return 'PreSales';
        }
        if (icoStarted && !icoFinished) {
            return 'ICOStarted';
        }
        if (icoFinished) {
            return 'ICOFinished';
        }
        if (privateSalesStarted) {
            return 'PrivateSales';
        }
        return 'Activated';
    }


    // ------------------------------------------------------------------------
    // Transfer the balance from token owner's account to `to` account
    // - Owner's account must have sufficient balance to transfer
    // - 0 value transfers are allowed
    // ------------------------------------------------------------------------
    function transfer(address _to, uint _tokens) public returns (bool success) {
        balances[msg.sender] = safeSub(balances[msg.sender], _tokens);
        balances[_to] = safeAdd(balances[_to], _tokens);
        emit Transfer(msg.sender, _to, _tokens);
        return true;
    }


    // ------------------------------------------------------------------------
    // Token owner can approve for `spender` to transferFrom(...) `tokens`
    // from the token owner's account
    //
    // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20-token-standard.md
    // recommends that there are no checks for the approval double-spend attack
    // as this should be implemented in user interfaces
    // ------------------------------------------------------------------------
    function approve(address _spender, uint _tokens) public returns (bool success) {
        allowed[msg.sender][_spender] = _tokens;
        emit Approval(msg.sender, _spender, _tokens);
        return true;
    }


    // ------------------------------------------------------------------------
    // Transfer `tokens` from the `from` account to the `to` account
    //
    // The calling account must already have sufficient tokens approve(...)-d
    // for spending from the `from` account and
    // - From account must have sufficient balance to transfer
    // - Spender must have sufficient allowance to transfer
    // - 0 value transfers are allowed
    // ------------------------------------------------------------------------
    function transferFrom(address _from, address _to, uint _tokens) public returns (bool success) {
        balances[_from] = safeSub(balances[_from], _tokens);
        allowed[_from][msg.sender] = safeSub(allowed[_from][msg.sender], _tokens);
        balances[_to] = safeAdd(balances[_to], _tokens);
        emit Transfer(_from, _to, _tokens);
        return true;
    }


    // ------------------------------------------------------------------------
    // Returns the amount of tokens approved by the owner that can be
    // transferred to the spender's account
    // ------------------------------------------------------------------------
    function allowance(address _tokenOwner, address _spender) public constant returns (uint remaining) {
        return allowed[_tokenOwner][_spender];
    }


    // ------------------------------------------------------------------------
    // Token owner can approve for `spender` to transferFrom(...) `tokens`
    // from the token owner's account. The `spender` contract function
    // `receiveApproval(...)` is then executed
    // ------------------------------------------------------------------------
    function approveAndCall(address _spender, uint _tokens, bytes _data) public returns (bool success) {
        allowed[msg.sender][_spender] = _tokens;
        emit Approval(msg.sender, _spender, _tokens);
        ApproveAndCallFallBack(_spender).receiveApproval(msg.sender, _tokens, this, _data);
        return true;
    }

    // ------------------------------------------------------------------------
    // 3,000 FWD Tokens per 1 ETH
    // ------------------------------------------------------------------------
    function () external payable {
        require(contractActivated);
        require(msg.value > 0 && msg.sender != address(0));
        issueToken(msg.sender, msg.value);
    }


    // ------------------------------------------------------------------------
    // Owner can transfer out any accidentally sent ERC20 tokens
    // ------------------------------------------------------------------------
    function transferAnyERC20Token(address _tokenAddress, uint _tokens) public onlyOwner returns (bool success) {
        return ERC20Interface(_tokenAddress).transfer(owner, _tokens);
    }


    // ------------------------------------------------------------------------
    // Whitelist interractions
    // ------------------------------------------------------------------------
    function addToWhitelist(address _investor) external OwnerAdminPortal() {
        Roles.add(whitelist, _investor);
    }
    function removeFromWhitelist(address _investor) external OwnerAdminPortal() {
        Roles.remove(whitelist, _investor);
    }
    function isInWhitelist(address _investor) private view returns (bool) {
        return Roles.has(whitelist, _investor);
    }
    
    // ------------------------------------------------------------------------
    // Private investors interractions
    // ------------------------------------------------------------------------
    function addPrivateInvestor(address _investor) external OwnerAdminPortal() {
        Roles.add(privateInvestors, _investor);
    }
    
    function removePrivateInvestor(address _investor) external OwnerAdminPortal() {
        Roles.remove(privateInvestors, _investor);
    }
    
    function isPrivateInvestor(address _investor) private view returns (bool) {
        return Roles.has(privateInvestors, _investor);
    }
    
    // ------------------------------------------------------------------------
    // Sales start-end control functions
    // ------------------------------------------------------------------------
    function startPrivateSale() external OwnerAdmin() {
        require(!privateSalesStarted && contractActivated);
        startPrivateSaleTime = now;
        privateSalesStarted = true;
    }
    
    function startPreSale() external OwnerAdmin() {
        require(!preSalesStarted && contractActivated);
        require(!icoStarted);
        preSalesStarted = true;
        startPreSaleTime = now;
    }
    
    function endPreSale() external OwnerAdmin() {
        require(preSalesStarted && contractActivated);
        preSalesStarted = false;
    }
    
    function startICO() external OwnerAdmin() {
        require(!icoStarted && contractActivated);
        preSalesStarted = false;
        startICOTime = now;
        icoStarted = true;
    }
    
    function endICO() external OwnerAdmin() {
        require(icoStarted);
        icoStarted = false;
        privateSalesStarted = false;
    }
    
    // ------------------------------------------------------------------------
    // Contract activation
    // ------------------------------------------------------------------------
    function activateContract() external onlyOwner() {
        require(!contractActivated);
        contractActivated = true;
    }
    function deactivateContract() external onlyOwner() {
        require(contractActivated);
        contractActivated = false;
    }
    
    function enableTokenTransfer() external onlyOwner() {
        require(!tokenTransfer);
        tokenTransfer = true;
    }
    
    
    // ------------------------------------------------------------------------
    // Setters for prices on each ico round
    // ------------------------------------------------------------------------ 
    function setPrivateSalePrice(uint _amount) external OwnerAdmin() {
        require(_amount > 0);
        pricePrivateSale = _amount;
    }
    
    function setPreSalePrice(uint _amount) external OwnerAdmin() {
        require(_amount > 0);
        pricePreSale = _amount;
    }
    
    function setICOPrice(uint _amount) external OwnerAdmin() {
        require(_amount > 0);
        priceICOSale = _amount;
    }
    
    
    // ------------------------------------------------------------------------
    // Functions to transfer ownership between some aspects
    // ------------------------------------------------------------------------ 
    function changeFundKeeper(address _newFund) external onlyOwner() {
        require(_newFund != address(0));
        fundKeeper = _newFund;
    }
    
    function changeAdminAddress(address _newAdmin) external onlyOwner() {
        require(_newAdmin != address(0));
        admin = _newAdmin;
    }
    
    function changePortalAddress(address _newPortal) external onlyOwner() {
        require(_newPortal != address(0));
        portal = _newPortal;
    }
    
    function changeFounderAddress(address _newFounder) external OwnerAdmin() {
        require(msg.sender == admin || msg.sender == owner);
        require(_newFounder != address(0));
        transferOwnership(_newFounder);
    }
    
    function changeTeamAddress(address _newTeam) external OwnerAdmin() {
        require(msg.sender == admin || msg.sender == owner);
        require(_newTeam != address(0));
        team = _newTeam;
    }
    
    function changeReservedAddress(address _newReserved) external OwnerAdmin() {
        require(msg.sender == admin || msg.sender == owner);
        require(_newReserved != address(0));
        reserved = _newReserved;
    }
    
    // ------------------------------------------------------------------------
    // Functions to issue tokens on differents sale states
    // ------------------------------------------------------------------------ 
    function issueToken(address _investor, uint _amount) private {
        if (privateSalesStarted) {
            issueTokenForPrivateInvestor(_investor, _amount);
        } else if (preSalesStarted) {
            issueTokenForPresale(_investor, _amount);
        } else if (icoStarted) {
            issueTokenForICO(_investor, _amount);
        }
    }
  
    // ------------------------------------------------------------------------
    // Private investor gets 60% bonus, so price is 3000 * 1.6 = 4800 tokens/ETH
    // ------------------------------------------------------------------------   
    function issueTokenForPrivateInvestor(address _investor, uint _amount) private {
        uint tokens = (_amount * pricePrivateSale) * (10 + PrivateSaleBonus) / 10;
        
        require(privateSalesStarted);
        require(isPrivateInvestor(_investor));
        require(safeAdd(_totalSupply, tokens) < maxSupply);
        
        balances[_investor] = safeAdd(balances[_investor], _amount);
        _totalSupply = safeAdd(_totalSupply, tokens);
        emit Transfer(address(0), msg.sender, tokens);
        owner.transfer(msg.value);
    }
    
    function issueTokenForPresale(address _investor, uint _amount) private {
        uint tokens = (_amount * pricePreSale) * (10 + PreSaleBonus) / 10;
        
        require(preSalesStarted);
        require(isInWhitelist(_investor));
        require(safeAdd(_totalSupply, tokens) < maxSupply);
        
        balances[_investor] = safeAdd(balances[_investor], _amount);
        _totalSupply = safeAdd(_totalSupply, tokens);
        emit Transfer(address(0), msg.sender, tokens);
        owner.transfer(msg.value);
    }
    
    function issueTokenForICO(address _investor, uint _amount) private {
        uint ICObonus = 2;
        uint tokens = (_amount * priceICOSale) * (10 + ICObonus) / 10;
        
        require(privateSalesStarted);
        require(isPrivateInvestor(_investor));
        require(safeAdd(_totalSupply, tokens) < maxSupply);
        
        balances[_investor] = safeAdd(balances[_investor], _amount);
        _totalSupply = safeAdd(_totalSupply, tokens);
        emit Transfer(address(0), msg.sender, tokens);
        owner.transfer(msg.value);
    }    

}