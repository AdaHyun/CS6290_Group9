// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Strings.sol";
import "account-abstraction/contracts/interfaces/IEntryPoint.sol";
import "account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import "account-abstraction/contracts/test/TestPaymasterAcceptAll.sol";
import "./helpers/UserOpBuilder.sol";

contract CountingTarget {
    uint256 public counter;
    event CounterIncremented(uint256 newValue);

    function increment() external {
        counter += 1;
        emit CounterIncremented(counter);
    }
}

contract RevertingTarget {
    error ForcedFailure();

    function alwaysFail() external pure {
        revert ForcedFailure();
    }
}

contract BatchIsolationTest is UserOpTestBase {
    using Strings for uint256;

    CountingTarget internal counterTarget;
    RevertingTarget internal revertingTarget;
    TestPaymasterAcceptAll internal paymaster;

    address payable internal constant BENEFICIARY =
        payable(address(0xBEEF));
    string internal constant RESULTS_PATH = "results/s6_batch_outcome.csv";

    constructor() {
        if (vm.isFile(RESULTS_PATH)) {
            vm.removeFile(RESULTS_PATH);
        }
    }

    function setUp() public override {
        super.setUp();
        counterTarget = new CountingTarget();
        revertingTarget = new RevertingTarget();
        paymaster = new TestPaymasterAcceptAll(entryPoint);
        _prepareResultsFile(
            RESULTS_PATH,
            "case_id,op1_expected,op2_expected,op2_observed,op2_effect,result_type,notes"
        );
    }

    function test_batchIsolation_keeps_successful_ops_running() public {
        UserOpParams memory failParams = UserOpParams({
            ownerKey: 0xA11CE,
            signingKey: 0xA11CE,
            salt: 1,
            freshDeployment: true,
            target: address(revertingTarget),
            targetCallData: abi.encodeCall(
                RevertingTarget.alwaysFail,
                ()
            ),
            callGasLimit: 200000,
            verificationGasLimit: 900000,
            preVerificationGas: 120000,
            maxFeePerGas: 1 gwei,
            maxPriorityFeePerGas: 1 gwei,
            paymasterAndData: ""
        });
        (
            PackedUserOperation memory failingOp,
            address failingSender
        ) = _buildUserOp(failParams);
        _depositFor(failingSender, 1 ether);

        UserOpParams memory successParams = UserOpParams({
            ownerKey: 0xB0B,
            signingKey: 0xB0B,
            salt: 2,
            freshDeployment: true,
            target: address(counterTarget),
            targetCallData: abi.encodeCall(CountingTarget.increment, ()),
            callGasLimit: 200000,
            verificationGasLimit: 900000,
            preVerificationGas: 120000,
            maxFeePerGas: 1 gwei,
            maxPriorityFeePerGas: 1 gwei,
            paymasterAndData: ""
        });
        (
            PackedUserOperation memory successOp,
            address successSender
        ) = _buildUserOp(successParams);
        _depositFor(successSender, 1 ether);

        PackedUserOperation[] memory ops = new PackedUserOperation[](2);
        ops[0] = failingOp;
        ops[1] = successOp;

        emit log_string("Expecting op1 to fail inside execution while op2 succeeds");
        _handleOps(ops, BENEFICIARY);

        uint256 counterAfter = counterTarget.counter();
        bool op2ObservedSuccess = counterAfter == 1;

        emit log_string("op1 failure reason: ForcedFailure()");
        emit log_named_uint("op2_counter_after", counterAfter);

        string memory row = string.concat(
            "s6_batch_case1,fail_execution,success,",
            op2ObservedSuccess ? "success" : "fail",
            ",",
            counterAfter.toString(),
            ",continued,op1 forced revert in execution stage"
        );
        _appendResults(RESULTS_PATH, row);

        assertEq(
            counterAfter,
            1,
            "op2 should increment the counter even if op1 fails"
        );
    }

    function test_batchIsolation_invalidSignature_revertsEntireBatch() public {
        UserOpParams memory invalidParams = UserOpParams({
            ownerKey: 0x1110,
            signingKey: 0x2220,
            salt: 5,
            freshDeployment: true,
            target: address(counterTarget),
            targetCallData: abi.encodeCall(CountingTarget.increment, ()),
            callGasLimit: 200000,
            verificationGasLimit: 900000,
            preVerificationGas: 120000,
            maxFeePerGas: 1 gwei,
            maxPriorityFeePerGas: 1 gwei,
            paymasterAndData: ""
        });
        (PackedUserOperation memory invalidOp, address invalidSender) = _buildUserOp(invalidParams);
        _depositFor(invalidSender, 1 ether);

        UserOpParams memory successParams = UserOpParams({
            ownerKey: 0x3333,
            signingKey: 0x3333,
            salt: 6,
            freshDeployment: true,
            target: address(counterTarget),
            targetCallData: abi.encodeCall(CountingTarget.increment, ()),
            callGasLimit: 200000,
            verificationGasLimit: 900000,
            preVerificationGas: 120000,
            maxFeePerGas: 1 gwei,
            maxPriorityFeePerGas: 1 gwei,
            paymasterAndData: ""
        });
        (PackedUserOperation memory successOp, address successSender) = _buildUserOp(successParams);
        _depositFor(successSender, 1 ether);

        PackedUserOperation[] memory ops = new PackedUserOperation[](2);
        ops[0] = invalidOp;
        ops[1] = successOp;

        emit log_string("Expecting FailedOp AA24 due to invalid signature; batch should revert");
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOp.selector,
                0,
                "AA24 signature error"
            )
        );
        _handleOps(ops, BENEFICIARY);

        uint256 counterValue = counterTarget.counter();
        emit log_named_uint("op2_counter_after_failed_batch", counterValue);

        string memory row = string.concat(
            "s6_batch_case2,invalid_signature,success,skipped,",
            counterValue.toString(),
            ",batch_reverted,AA24 signature error halted batch"
        );
        _appendResults(RESULTS_PATH, row);

        assertEq(counterValue, 0, "counter should remain zero when batch reverts");
    }

    function test_batchIsolation_paymasterDepositTooLow_revertsBatch() public {
        UserOpParams memory pmParams = UserOpParams({
            ownerKey: 0x4444,
            signingKey: 0x4444,
            salt: 7,
            freshDeployment: true,
            target: address(counterTarget),
            targetCallData: abi.encodeCall(CountingTarget.increment, ()),
            callGasLimit: 200000,
            verificationGasLimit: 900000,
            preVerificationGas: 120000,
            maxFeePerGas: 1 gwei,
            maxPriorityFeePerGas: 1 gwei,
            paymasterAndData: _createPaymasterData(
                address(paymaster),
                150000,
                300000,
                ""
            )
        });
        (PackedUserOperation memory sponsoredOp, ) = _buildUserOp(pmParams);

        UserOpParams memory successParams = UserOpParams({
            ownerKey: 0x5555,
            signingKey: 0x5555,
            salt: 8,
            freshDeployment: true,
            target: address(counterTarget),
            targetCallData: abi.encodeCall(CountingTarget.increment, ()),
            callGasLimit: 200000,
            verificationGasLimit: 900000,
            preVerificationGas: 120000,
            maxFeePerGas: 1 gwei,
            maxPriorityFeePerGas: 1 gwei,
            paymasterAndData: ""
        });
        (PackedUserOperation memory successOp, address successSender) = _buildUserOp(successParams);
        _depositFor(successSender, 1 ether);

        PackedUserOperation[] memory ops = new PackedUserOperation[](2);
        ops[0] = sponsoredOp;
        ops[1] = successOp;

        emit log_string("Expecting FailedOp AA31 due to paymaster deposit too low; entire batch reverts");
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOp.selector,
                0,
                "AA31 paymaster deposit too low"
            )
        );
        _handleOps(ops, BENEFICIARY);

        uint256 counterValue = counterTarget.counter();
        emit log_named_uint("counter_after_paymaster_failure", counterValue);

        string memory row = string.concat(
            "s6_batch_case3,paymaster_deposit_low,success,skipped,",
            counterValue.toString(),
            ",batch_reverted,AA31 paymaster deposit too low halted batch"
        );
        _appendResults(RESULTS_PATH, row);

        assertEq(
            counterValue,
            0,
            "op2 should not execute when paymaster validation reverts entire batch"
        );
    }
}
