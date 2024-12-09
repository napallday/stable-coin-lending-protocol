// SPDX-Licence-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SCoin is ERC20 {
    constructor() ERC20("SCoin", "SC") {}

    function mint(address _to, uint256 _amount) external {
        if (_amount == 0) {
            return;
        }
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external {
        if (_amount == 0) {
            return;
        }
        _burn(_from, _amount);
    }
}
