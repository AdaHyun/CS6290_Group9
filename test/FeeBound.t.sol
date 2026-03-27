// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Strings.sol";

import "account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import "account-abstraction/contracts/test/TestPaymasterAcceptAll.sol";
import "account-abstraction/contracts/test/TestPaymasterWithPostOp.sol";

import "./helpers/UserOpBuilder.sol";

contract FeeBoundTarget {
    uint256 public hits;
    event Hit(uint256 total);

    function bump() external {
        hits += 1;
        emit Hit(hits);
    }
}

contract FeeBoundTest is UserOpTestBase {
    using Strings for uint256;

    address payable internal constant BENEFICIARY =
        payable(address(0xBEEF));
    string internal constant RESULTS_PATH = "results/s7_fee_bound.csv";
    bytes32 internal constant USER_OPERATION_EVENT_SIG =
        keccak256(
            "UserOperationEvent(bytes32,address,address,uint256,bool,uint256,uint256)"
        );

    FeeBoundTarget internal feeTarget;
    TestPaymasterAcceptAll internal paymaster;
    TestPaymasterWithPostOp internal paymasterWithPostOp;

    struct UserOpMetrics {
        uint256 actualGasCost;
        uint256 actualGasUsed;
    }

    error UserOperationEventNotFound();

    constructor() {
        if (vm.isFile(RESULTS_PATH)) {
            vm.removeFile(RESULTS_PATH);
        }
    }

    function setUp() public override {
        super.setUp();
        feeTarget = new FeeBoundTarget();
        paymaster = new TestPaymasterAcceptAll(entryPoint);
        paymasterWithPostOp = new TestPaymasterWithPostOp(entryPoint);
        vm.deal(BENEFICIARY, 0);
    }

    function test_feeCharged_isWithinBound() public {
        _prepareResultsFile(
            RESULTS_PATH,
            "case_id,mode,gas_price,max_fee_per_gas,upper_bound,prefund,actual_gas_cost,beneficiary_delta,actual_gas_used,paymaster_deposit_before,paymaster_deposit_after,pass,notes"
        );

        uint256 gasPrice = 1 gwei;
        vm.txGasPrice(gasPrice);

        string memory accountRow = _runAccountSelfPayCase(gasPrice);
        _appendResults(RESULTS_PATH, accountRow);

        string memory pmRow = _runPaymasterSponsoredCase(gasPrice);
        _appendResults(RESULTS_PATH, pmRow);
    }

    function test_feeBounds_paymasterWithPostOp_bound() public {
        _prepareResultsFile(
            RESULTS_PATH,
            "case_id,mode,gas_price,max_fee_per_gas,upper_bound,prefund,actual_gas_cost,beneficiary_delta,actual_gas_used,paymaster_deposit_before,paymaster_deposit_after,pass,notes"
        );

        uint256 gasPrice = 1 gwei;
        vm.txGasPrice(gasPrice);

        string memory postOpRow = _runPaymasterWithPostOpCase(gasPrice);
        _appendResults(RESULTS_PATH, postOpRow);
    }

    function _runAccountSelfPayCase(
        uint256 gasPrice
    ) internal returns (string memory row) {
        UserOpParams memory params = UserOpParams({
            ownerKey: 0xDAD,
            signingKey: 0xDAD,
            salt: 3,
            freshDeployment: true,
            target: address(feeTarget),
            targetCallData: abi.encodeCall(FeeBoundTarget.bump, ()),
            callGasLimit: 200000,
            verificationGasLimit: 900000,
            preVerificationGas: 120000,
            maxFeePerGas: gasPrice,
            maxPriorityFeePerGas: gasPrice,
            paymasterAndData: ""
        });
        (PackedUserOperation memory op, address sender) = _buildUserOp(params);
        _depositFor(sender, 1 ether);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;

        emit log_string("S7-1 account-funded op executing");
        vm.recordLogs();
        uint256 beneficiaryBefore = BENEFICIARY.balance;
        _handleOps(ops, BENEFICIARY);
        uint256 beneficiaryIncrease = BENEFICIARY.balance - beneficiaryBefore;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        UserOpMetrics memory metrics = _getUserOpMetrics(logs, sender);

        uint256 upperBound = (
            params.callGasLimit +
            params.verificationGasLimit +
            params.preVerificationGas
        ) * params.maxFeePerGas;
        uint256 prefund = upperBound;

        emit log_named_uint("gasPrice", gasPrice);
        emit log_named_uint("maxFeePerGas", params.maxFeePerGas);
        emit log_named_uint("upperBound_account", upperBound);
        emit log_named_uint(
            "beneficiaryIncrease_account",
            beneficiaryIncrease
        );
        emit log_named_uint("beneficiaryDelta_account", beneficiaryIncrease);
        emit log_named_uint("actualGasCost_account", metrics.actualGasCost);
        emit log_named_uint("actualGasUsed_account", metrics.actualGasUsed);

        require(beneficiaryIncrease > 0, "beneficiary must gain fees");
        require(
            beneficiaryIncrease <= upperBound,
            "fees must stay within bound"
        );
        require(
            metrics.actualGasCost <= upperBound,
            "actual gas cost must stay within bound"
        );
        require(
            beneficiaryIncrease == metrics.actualGasCost,
            "beneficiary delta must equal actual gas cost"
        );

        row = _formatResultRow(
            "s7_case_account",
            "account",
            gasPrice,
            params.maxFeePerGas,
            upperBound,
            prefund,
            metrics.actualGasCost,
            beneficiaryIncrease,
            metrics.actualGasUsed,
            0,
            0,
            "account balance bounds respected"
        );
    }

    function _runPaymasterSponsoredCase(
        uint256 gasPrice
    ) internal returns (string memory row) {
        uint256 depositBefore = entryPoint.balanceOf(address(paymaster));
        if (depositBefore < 1 ether) {
            entryPoint.depositTo{value: 1 ether}(address(paymaster));
            depositBefore = entryPoint.balanceOf(address(paymaster));
        }

        UserOpParams memory params = UserOpParams({
            ownerKey: 0xCAFE,
            signingKey: 0xCAFE,
            salt: 4,
            freshDeployment: true,
            target: address(feeTarget),
            targetCallData: abi.encodeCall(FeeBoundTarget.bump, ()),
            callGasLimit: 200000,
            verificationGasLimit: 900000,
            preVerificationGas: 120000,
            maxFeePerGas: gasPrice,
            maxPriorityFeePerGas: gasPrice,
            paymasterAndData: _createPaymasterData(
                address(paymaster),
                150000,
                300000,
                ""
            )
        });
        (PackedUserOperation memory op, address sender) = _buildUserOp(params);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;

        emit log_string("S7-2 paymaster-funded op executing");
        vm.recordLogs();
        uint256 beneficiaryBefore = BENEFICIARY.balance;
        _handleOps(ops, BENEFICIARY);
        uint256 beneficiaryIncrease = BENEFICIARY.balance - beneficiaryBefore;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        UserOpMetrics memory metrics = _getUserOpMetrics(logs, sender);

        uint256 upperBound = (
            params.callGasLimit +
            params.verificationGasLimit +
            params.preVerificationGas
        ) * params.maxFeePerGas;
        uint256 prefund = upperBound;

        uint256 depositAfter = entryPoint.balanceOf(address(paymaster));
        uint256 depositDecrease = depositBefore - depositAfter;

        emit log_named_uint("upperBound_paymaster", upperBound);
        emit log_named_uint(
            "maxFeePerGas_paymaster",
            params.maxFeePerGas
        );
        emit log_named_uint(
            "beneficiaryIncrease_paymaster",
            beneficiaryIncrease
        );
        emit log_named_uint(
            "beneficiaryDelta_paymaster",
            beneficiaryIncrease
        );
        emit log_named_uint("paymaster_deposit_before", depositBefore);
        emit log_named_uint("paymaster_deposit_after", depositAfter);
        emit log_named_uint("paymasterDepositDecrease", depositDecrease);
        emit log_named_uint(
            "actualGasCost_paymaster",
            metrics.actualGasCost
        );
        emit log_named_uint(
            "actualGasUsed_paymaster",
            metrics.actualGasUsed
        );

        require(
            beneficiaryIncrease <= upperBound,
            "sponsored fees must stay within bound"
        );
        require(
            metrics.actualGasCost <= upperBound,
            "paymaster actual gas cost must stay within bound"
        );
        require(
            beneficiaryIncrease == metrics.actualGasCost,
            "paymaster beneficiary delta must equal actual gas cost"
        );
        require(
            depositDecrease >= beneficiaryIncrease,
            "paymaster deposit must cover beneficiary payment"
        );
        require(
            depositDecrease == beneficiaryIncrease,
            "paymaster deposit decrease must match beneficiary delta"
        );
        require(
            depositDecrease == metrics.actualGasCost,
            "paymaster deposit decrease must equal actual cost"
        );

        row = _formatResultRow(
            "s7_case_paymaster",
            "paymaster",
            gasPrice,
            params.maxFeePerGas,
            upperBound,
            prefund,
            metrics.actualGasCost,
            beneficiaryIncrease,
            metrics.actualGasUsed,
            depositBefore,
            depositAfter,
            "paymaster deposit bounded the payout"
        );
    }

    function _runPaymasterWithPostOpCase(
        uint256 gasPrice
    ) internal returns (string memory row) {
        uint256 depositBefore = entryPoint.balanceOf(address(paymasterWithPostOp));
        if (depositBefore < 1 ether) {
            entryPoint.depositTo{value: 1 ether}(address(paymasterWithPostOp));
            depositBefore = entryPoint.balanceOf(address(paymasterWithPostOp));
        }

        UserOpParams memory params = UserOpParams({
            ownerKey: 0x7777,
            signingKey: 0x7777,
            salt: 9,
            freshDeployment: true,
            target: address(feeTarget),
            targetCallData: abi.encodeCall(FeeBoundTarget.bump, ()),
            callGasLimit: 250000,
            verificationGasLimit: 950000,
            preVerificationGas: 150000,
            maxFeePerGas: gasPrice,
            maxPriorityFeePerGas: gasPrice,
            paymasterAndData: _createPaymasterData(
                address(paymasterWithPostOp),
                200000,
                350000,
                ""
            )
        });
        (PackedUserOperation memory op, address sender) = _buildUserOp(params);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;

        emit log_string("S7-3 paymaster-with-postOp sponsored op executing");
        vm.recordLogs();
        uint256 beneficiaryBefore = BENEFICIARY.balance;
        _handleOps(ops, BENEFICIARY);
        uint256 beneficiaryIncrease = BENEFICIARY.balance - beneficiaryBefore;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        UserOpMetrics memory metrics = _getUserOpMetrics(logs, sender);

        uint256 upperBound = (
            params.callGasLimit +
            params.verificationGasLimit +
            params.preVerificationGas
        ) * params.maxFeePerGas;
        uint256 prefund = upperBound;

        uint256 depositAfter = entryPoint.balanceOf(address(paymasterWithPostOp));
        uint256 depositDecrease = depositBefore - depositAfter;

        emit log_named_uint("upperBound_paymaster_postop", upperBound);
        emit log_named_uint(
            "beneficiaryIncrease_paymaster_postop",
            beneficiaryIncrease
        );
        emit log_named_uint(
            "actualGasCost_paymaster_postop",
            metrics.actualGasCost
        );
        emit log_named_uint(
            "actualGasUsed_paymaster_postop",
            metrics.actualGasUsed
        );
        emit log_named_uint("paymaster_postop_deposit_before", depositBefore);
        emit log_named_uint("paymaster_postop_deposit_after", depositAfter);
        emit log_named_uint(
            "beneficiaryDelta_paymaster_postop",
            beneficiaryIncrease
        );

        require(
            beneficiaryIncrease <= upperBound,
            "postOp sponsor fees must stay within bound"
        );
        require(
            metrics.actualGasCost <= upperBound,
            "postOp actual gas cost must stay within bound"
        );
        require(
            beneficiaryIncrease == metrics.actualGasCost,
            "postOp beneficiary delta must equal actual cost"
        );
        require(
            depositDecrease >= beneficiaryIncrease,
            "postOp paymaster must cover fees"
        );
        require(
            depositDecrease >= metrics.actualGasCost,
            "deposit decrease must pay actual cost"
        );
        require(
            depositDecrease == beneficiaryIncrease,
            "postOp deposit decrease must match beneficiary delta"
        );
        require(
            depositDecrease == metrics.actualGasCost,
            "postOp deposit decrease must equal actual cost"
        );

        row = _formatResultRow(
            "s7_case_paymaster_postop",
            "paymaster_postop",
            gasPrice,
            params.maxFeePerGas,
            upperBound,
            prefund,
            metrics.actualGasCost,
            beneficiaryIncrease,
            metrics.actualGasUsed,
            depositBefore,
            depositAfter,
            "paymaster with postOp bounded payout"
        );
    }

    function _getUserOpMetrics(
        Vm.Log[] memory logs,
        address sender
    ) internal pure returns (UserOpMetrics memory metrics) {
        uint256 logsLength = logs.length;
        for (uint256 i = 0; i < logsLength; i++) {
            Vm.Log memory entry = logs[i];
            if (
                entry.topics.length >= 3 &&
                entry.topics[0] == USER_OPERATION_EVENT_SIG &&
                address(uint160(uint256(entry.topics[2]))) == sender
            ) {
                (, , uint256 actualGasCost, uint256 actualGasUsed) = abi.decode(
                    entry.data,
                    (uint256, bool, uint256, uint256)
                );
                metrics.actualGasCost = actualGasCost;
                metrics.actualGasUsed = actualGasUsed;
                return metrics;
            }
        }
        revert UserOperationEventNotFound();
    }

    function _formatResultRow(
        string memory caseId,
        string memory mode,
        uint256 gasPrice,
        uint256 maxFeePerGas,
        uint256 upperBound,
        uint256 prefund,
        uint256 actualGasCost,
        uint256 beneficiaryIncrease,
        uint256 actualGasUsed,
        uint256 depositBefore,
        uint256 depositAfter,
        string memory notes
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                caseId,
                ",",
                mode,
                ",",
                gasPrice.toString(),
                ",",
                maxFeePerGas.toString(),
                ",",
                upperBound.toString(),
                ",",
                prefund.toString(),
                ",",
                actualGasCost.toString(),
                ",",
                beneficiaryIncrease.toString(),
                ",",
                actualGasUsed.toString(),
                ",",
                depositBefore.toString(),
                ",",
                depositAfter.toString(),
                ",true,",
                notes
            )
        );
    }
}
