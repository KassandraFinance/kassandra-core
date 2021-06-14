import "../crytic-export/flattening/Pool.sol";
import "./CryticInterface.sol";

contract MyToken is Token, CryticInterface{

    constructor(uint balance, address allowed) public {
        // balance is the new totalSupply
        _totalSupply = balance;
        // each user receives 1/3 of the balance and sets 
        // the allowance of the allowed address.
        uint initialTotalSupply = balance;
        _balance[crytic_owner] = initialTotalSupply/3;
        _allowance[crytic_owner][allowed] = balance;
        _balance[crytic_user] = initialTotalSupply/3;
        _allowance[crytic_user][allowed] = balance;
        _balance[crytic_attacker] = initialTotalSupply/3;
        _allowance[crytic_attacker][allowed] = balance;
    }
}
