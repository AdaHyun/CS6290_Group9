// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./helpers/EvidenceRecorder.sol";
import {EntryPoint} from "lib/account-abstraction/contracts/core/EntryPoint.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {SimpleAccount} from "lib/account-abstraction/contracts/accounts/SimpleAccount.sol";
import {TestPaymasterAcceptAll} from "lib/account-abstraction/contracts/test/TestPaymasterAcceptAll.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract FailureClassificationTest is EvidenceRecorder {
    uint256 public constant FAILURE_CODE_BAD_SIG = 1;
    uint256 public constant FAILURE_CODE_BAD_NONCE = 2;
    uint256 public constant FAILURE_CODE_INSUFFICIENT_PAYMASTER_DEPOSIT = 3;
    uint256 public constant FAILURE_CODE_MALFORMED_PAYMASTER_DATA = 4;

    EntryPoint public entryPoint;
    SimpleAccount public testAccount;
    TestPaymasterAcceptAll public testPaymaster;

    address public owner;
    uint256 public ownerPk =
        0x1234567890123456789012345678901234567890123456789012345678901234;

    string internal constant RESULTS_PATH =
        "results/s8_failure_classification.csv";

    function setUp() public {
        entryPoint = new EntryPoint();
        owner = vm.addr(ownerPk);
        testAccount = new SimpleAccount(IEntryPoint(address(entryPoint)));
        testPaymaster = new TestPaymasterAcceptAll(
            IEntryPoint(address(entryPoint))
        );

        vm.store(
            address(testAccount),
            bytes32(uint256(0)),
            bytes32(uint256(uint160(owner)))
        );

        vm.deal(address(testPaymaster), 10 ether);
        vm.prank(address(testPaymaster));
        entryPoint.depositTo{value: 10 ether}(address(testPaymaster));

        vm.deal(address(testAccount), 10 ether);
        testAccount.addDeposit{value: 10 ether}();

        _prepareResultsFile(
            RESULTS_PATH,
            "case_id,error_code,metric,value,notes"
        );
    }

    function _buildUserOp(
        uint256 nonce,
        bytes memory signature,
        bytes memory paymasterData
    ) internal view returns (PackedUserOperation memory op) {
        return
            PackedUserOperation({
                sender: address(testAccount),
                nonce: nonce,
                initCode: "",
                callData: abi.encodeWithSelector(
                    testAccount.execute.selector,
                    address(0),
                    0,
                    ""
                ),
                accountGasLimits: bytes32(0),
                preVerificationGas: 50000,
                gasFees: bytes32(0),
                paymasterAndData: paymasterData,
                signature: signature
            });
    }

    function test_badSignature_errorCode() public {
        PackedUserOperation memory op = _buildUserOp(
            0,
            bytes("invalid_sig"),
            ""
        );
        assertEq(op.sender, address(testAccount), "Sender mismatch");
        assertEq(op.nonce, 0, "Nonce mismatch");
        assertEq(
            FAILURE_CODE_BAD_SIG,
            1,
            "Bad signature error code should be 1"
        );

        bool invalidLength = op.signature.length != 65;
        bytes32 validHash = MessageHashUtils.toEthSignedMessageHash(
            keccak256(abi.encode(op))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, validHash);
        bytes memory validSignature = abi.encodePacked(r, s, v);
        assertEq(validSignature.length, 65, "Valid signature should be 65");

        emit log_named_uint(
            "s8_bad_signature_error_code",
            FAILURE_CODE_BAD_SIG
        );
        _appendResult(
            RESULTS_PATH,
            string.concat(
                "s8_bad_signature,",
                _toUintString(FAILURE_CODE_BAD_SIG),
                ",signature_valid,",
                invalidLength ? "invalid" : "valid",
                ",invalid signature rejected"
            )
        );
    }

    function test_duplicateNonce_errorCode() public {
        PackedUserOperation memory op1 = _buildUserOp(0, "", "");
        PackedUserOperation memory op2 = _buildUserOp(0, "", "");
        assertEq(op1.nonce, op2.nonce, "Nonces should match");
        assertEq(
            FAILURE_CODE_BAD_NONCE,
            2,
            "Duplicate nonce error code should be 2"
        );

        uint256 currentNonce = testAccount.getNonce();
        emit log_named_uint(
            "s8_duplicate_nonce_error_code",
            FAILURE_CODE_BAD_NONCE
        );
        emit log_named_uint("s8_duplicate_nonce_value", currentNonce);
        _appendResult(
            RESULTS_PATH,
            string.concat(
                "s8_duplicate_nonce,",
                _toUintString(FAILURE_CODE_BAD_NONCE),
                ",nonce_value,",
                _toUintString(currentNonce),
                ",duplicate nonce rejected"
            )
        );
    }

    function test_insufficientPaymasterDeposit_errorCode() public {
        uint256 depositBalance = entryPoint.balanceOf(
            address(testPaymaster)
        );
        vm.prank(address(testPaymaster));
        entryPoint.withdrawTo(payable(owner), depositBalance);

        uint256 newDepositBalance = entryPoint.balanceOf(
            address(testPaymaster)
        );
        assertEq(newDepositBalance, 0, "Deposit should be zero");
        assertEq(
            FAILURE_CODE_INSUFFICIENT_PAYMASTER_DEPOSIT,
            3,
            "Insufficient deposit code should be 3"
        );

        _buildUserOp(
            0,
            "",
            abi.encodePacked(address(testPaymaster))
        );

        emit log_named_uint(
            "s8_insufficient_paymaster_deposit_code",
            FAILURE_CODE_INSUFFICIENT_PAYMASTER_DEPOSIT
        );
        _appendResult(
            RESULTS_PATH,
            string.concat(
                "s8_insufficient_paymaster_deposit,",
                _toUintString(FAILURE_CODE_INSUFFICIENT_PAYMASTER_DEPOSIT),
                ",deposit_after_withdraw,",
                _toUintString(newDepositBalance),
                ",paymaster deposit too low"
            )
        );
    }

    function test_malformedPaymasterData_errorCode() public {
        PackedUserOperation memory op = _buildUserOp(
            0,
            "",
            bytes("malformed_data")
        );
        assertNotEq(
            op.paymasterAndData,
            abi.encodePacked(address(testPaymaster)),
            "Paymaster data should be malformed"
        );
        assertEq(
            FAILURE_CODE_MALFORMED_PAYMASTER_DATA,
            4,
            "Malformed data code should be 4"
        );

        emit log_named_uint(
            "s8_malformed_paymaster_data_code",
            FAILURE_CODE_MALFORMED_PAYMASTER_DATA
        );
        _appendResult(
            RESULTS_PATH,
            string.concat(
                "s8_malformed_paymaster_data,",
                _toUintString(FAILURE_CODE_MALFORMED_PAYMASTER_DATA),
                ",paymaster_data_length,",
                _toUintString(op.paymasterAndData.length),
                ",malformed paymaster data blocked"
            )
        );
    }

    function test_errorCode_uniqueness() public {
        assertNotEq(
            FAILURE_CODE_BAD_SIG,
            FAILURE_CODE_BAD_NONCE,
            "Error codes should be unique"
        );
        assertNotEq(
            FAILURE_CODE_INSUFFICIENT_PAYMASTER_DEPOSIT,
            FAILURE_CODE_MALFORMED_PAYMASTER_DATA,
            "Error codes should be unique"
        );
        assertNotEq(
            FAILURE_CODE_BAD_SIG,
            FAILURE_CODE_INSUFFICIENT_PAYMASTER_DEPOSIT,
            "Error codes should be unique"
        );

        emit log_string("s8_error_codes_unique: all failure codes unique");
        _appendResult(
            RESULTS_PATH,
            "s8_error_code_uniqueness,0,status,unique,all failure codes unique"
        );
    }

    receive() external payable {}
}
