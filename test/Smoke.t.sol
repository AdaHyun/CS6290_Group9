// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "account-abstraction/contracts/core/EntryPoint.sol";

contract SmokeTest is Test {
    function test_deploy_entrypoint() public {
        EntryPoint ep = new EntryPoint();
        assertTrue(address(ep) != address(0));
    }
}