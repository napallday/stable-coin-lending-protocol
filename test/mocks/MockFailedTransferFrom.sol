// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

// Helper contract that always returns false for transferFrom
contract MockFailedTransferFrom is ERC20Mock {
    constructor() ERC20Mock() {}

    function transferFrom(address, address, uint256) public pure override returns (bool) {
        return false;
    }
}