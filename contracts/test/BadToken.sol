// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

contract BadToken {
    string internal _name;
    string internal _symbol;
    uint8   internal _decimals;

    address internal _owner;

    uint internal _totalSupply;

    mapping(address => uint)                   internal _balance;
    mapping(address => mapping(address=>uint)) internal _allowance;

    event Approval(address indexed src, address indexed dst, uint amt);
    event Transfer(address indexed src, address indexed dst, uint amt);

    modifier _onlyOwner_() {
        require(msg.sender == _owner, "ERR_NOT_OWNER");
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        _owner = msg.sender;
    }

    /* solhint-disable ordering */

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns(uint8) {
        return _decimals;
    }

    function _move(address src, address dst, uint amt) internal virtual {
        // Fail if trying to transfer 0
        //require(amt > 0, "ERR_NO_ZERO_XFER");

        require(_balance[src] >= amt, "ERR_INSUFFICIENT_BAL");
        _balance[src] = _balance[src] - amt;
        _balance[dst] = _balance[dst] + amt;
        emit Transfer(src, dst, amt);
    }

    function _push(address to, uint amt) internal {
        _move(address(this), to, amt);
    }

    function _pull(address from, uint amt) internal {
        _move(from, address(this), amt);
    }

    function _mint(address dst, uint amt) internal {
        _balance[dst] = _balance[dst] + amt;
        _totalSupply = _totalSupply + amt;
        emit Transfer(address(0), dst, amt);
    }

    function allowance(address src, address dst) external view returns (uint) {
        return _allowance[src][dst];
    }

    function balanceOf(address whom) external view returns (uint) {
        return _balance[whom];
    }

    function totalSupply() public view returns (uint) {
        return _totalSupply;
    }

    function approve(address dst, uint amt) external virtual returns (bool) {
        // Fail if prior approval is not zero
        //require(_allowance[msg.sender][dst] == 0, "ERR_PRIOR_ZERO_APPROVE");

        _allowance[msg.sender][dst] = amt;
        emit Approval(msg.sender, dst, amt);
        return true;
    }

    function mint(address dst, uint256 amt) public _onlyOwner_ returns (bool) {
        _mint(dst, amt);
        return true;
    }

    function burn(uint amt) public returns (bool) {
        require(_balance[address(this)] >= amt, "ERR_INSUFFICIENT_BAL");
        _balance[address(this)] = _balance[address(this)] - amt;
        _totalSupply = _totalSupply - amt;
        emit Transfer(address(this), address(0), amt);
        return true;
    }

    function transfer(address dst, uint amt) external virtual returns (bool) {
        _move(msg.sender, dst, amt);
        return true;
    }

    function transferFrom(address src, address dst, uint amt) external virtual returns (bool) {
        require(msg.sender == src || amt <= _allowance[src][msg.sender], "ERR_TOKEN_BAD_CALLER");
        _move(src, dst, amt);
        if (msg.sender != src && _allowance[src][msg.sender] != type(uint256).max) {
            _allowance[src][msg.sender] = _allowance[src][msg.sender] - amt;
            emit Approval(msg.sender, dst, _allowance[src][msg.sender]);
        }
        return true;
    }
    /* solhint-enable ordering */
}

/* solhint-disable no-empty-blocks */

contract NoZeroXferToken is BadToken {
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    )
        BadToken(name, symbol, decimals)
    {
    }

    function _move(address src, address dst, uint amt) internal override {
        // Fail if trying to transfer 0
        require(amt > 0, "ERR_NO_ZERO_XFER");

        require(_balance[src] >= amt, "ERR_INSUFFICIENT_BAL");
        _balance[src] = _balance[src] - amt;
        _balance[dst] = _balance[dst] + amt;
        emit Transfer(src, dst, amt);
    }
}

contract NoPriorApprovalToken is BadToken {
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    )
        BadToken(name, symbol, decimals)
    {
    }

    function approve(address dst, uint amt) external override returns (bool) {
        // Fail if prior approval is not zero
        require(_allowance[msg.sender][dst] == 0, "ERR_PRIOR_ZERO_APPROVE");

        _allowance[msg.sender][dst] = amt;
        emit Approval(msg.sender, dst, amt);
        return true;
    }
}

contract FalseReturningToken is BadToken {
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    )
        BadToken(name, symbol, decimals)
    {
    }

    function transfer(address dst, uint amt) external override returns (bool) {
        _move(msg.sender, dst, amt);
        return false;
    }

    function transferFrom(address src, address dst, uint amt) external override returns (bool) {
        require(msg.sender == src || amt <= _allowance[src][msg.sender], "ERR_TOKEN_BAD_CALLER");
        _move(src, dst, amt);
        if (msg.sender != src && _allowance[src][msg.sender] != type(uint256).max) {
            _allowance[src][msg.sender] = _allowance[src][msg.sender] - amt;
            emit Approval(msg.sender, dst, _allowance[src][msg.sender]);
        }

        return false;
    }
}

contract TaxingToken is BadToken {
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals
    )
        BadToken(name, symbol, decimals)
    {
    }

    function transfer(address dst, uint amt) external override returns (bool) {
        _move(msg.sender, dst, amt - 1);
        return true;
    }

    function transferFrom(address src, address dst, uint amt) external override returns (bool) {
        require(msg.sender == src || amt <= _allowance[src][msg.sender], "ERR_TOKEN_BAD_CALLER");
        _move(src, dst, amt - 1);
        if (msg.sender != src && _allowance[src][msg.sender] != type(uint256).max) {
            _allowance[src][msg.sender] = _allowance[src][msg.sender] - amt - 1;
            emit Approval(msg.sender, dst, _allowance[src][msg.sender]);
        }
        return true;
    }
}