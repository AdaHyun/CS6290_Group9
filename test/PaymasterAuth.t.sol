// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "account-abstraction/contracts/core/EntryPoint.sol";
import "account-abstraction/contracts/interfaces/IPaymaster.sol";
import "account-abstraction/contracts/test/TestPaymasterAcceptAll.sol";
import "./helpers/EvidenceRecorder.sol";

contract PaymasterAuthTest is EvidenceRecorder {
    EntryPoint ep;
    TestPaymasterAcceptAll paymaster;
    string internal constant RESULTS_PATH = "results/s1_paymaster_access.csv";

    function setUp() public {
        ep = new EntryPoint();
        paymaster = new TestPaymasterAcceptAll(ep);
        _prepareResultsFile(
            RESULTS_PATH,
            "case_id,method,caller,result,notes"
        );
    }

    function test_validatePaymasterUserOp_onlyEntryPoint_canCall() public {
        PackedUserOperation memory userOp;
        bytes32 userOpHash = bytes32(0);
        uint256 maxCost = 0;

        vm.expectRevert();
        paymaster.validatePaymasterUserOp(userOp, userOpHash, maxCost);

        emit log_string(
            "S1 validatePaymasterUserOp reverted for non-entrypoint caller"
        );
        _appendResult(
            RESULTS_PATH,
            string.concat(
                "s1_validate_non_entrypoint,validatePaymasterUserOp,",
                _toAddressString(address(this)),
                ",revert,non-entrypoint caller blocked"
            )
        );
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

        emit log_string(
            "S1 postOp reverted for non-entrypoint caller"
        );
        _appendResult(
            RESULTS_PATH,
            string.concat(
                "s1_postop_non_entrypoint,postOp,",
                _toAddressString(address(this)),
                ",revert,non-entrypoint caller blocked"
            )
        );
    }
}
