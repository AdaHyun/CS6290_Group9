// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "account-abstraction/contracts/core/EntryPoint.sol";
import "account-abstraction/contracts/interfaces/IPaymaster.sol";
import "account-abstraction/contracts/test/TestPaymasterAcceptAll.sol";

contract PaymasterAuthTest is Test {
    EntryPoint ep;
    TestPaymasterAcceptAll paymaster;

    function setUp() public {
        ep = new EntryPoint();
        paymaster = new TestPaymasterAcceptAll(ep);
    }

    function test_validatePaymasterUserOp_onlyEntryPoint_canCall() public {
        PackedUserOperation memory userOp;
        bytes32 userOpHash = bytes32(0);
        uint256 maxCost = 0;

        vm.expectRevert();
        paymaster.validatePaymasterUserOp(userOp, userOpHash, maxCost);
    }

    function test_postOp_onlyEntryPoint_canCall() public {
        bytes memory context = "";
        uint256 actualGasCost = 0;
        uint256 actualUserOpFeePerGas = 0;

        vm.expectRevert();
        paymaster.postOp(
            IPaymaster.PostOpMode.opSucceeded,
            context,
            actualGasCost,
            actualUserOpFeePerGas
        );
    }
}