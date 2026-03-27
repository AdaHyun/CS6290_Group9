// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "./helpers/EvidenceRecorder.sol";

import "account-abstraction/contracts/core/EntryPoint.sol";
import "account-abstraction/contracts/interfaces/IEntryPoint.sol";
import "account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import "../src/MinimalAccount.sol";
import "./Counter.sol";

contract NonceReplayTest is EvidenceRecorder {
    EntryPoint ep;
    MinimalAccount account;
    Counter counter;

    uint256 ownerPk;
    address owner;
    address beneficiary;
    address bundler;

    string internal constant RESULTS_PATH = "results/s2_nonce_replay.csv";

    function setUp() public {
        ep = new EntryPoint();

        ownerPk = 0xA11CE;
        owner = vm.addr(ownerPk);
        beneficiary = makeAddr("beneficiary");
        bundler = makeAddr("bundler");

        account = new MinimalAccount(ep, owner);
        counter = new Counter();

        vm.deal(address(account), 10 ether);
        _prepareResultsFile(
            RESULTS_PATH,
            "case_id,nonce,expected,result,counter,notes"
        );
    }

    function test_replayNonce_shouldFail() public {
        bytes memory callData = abi.encodeCall(
            MinimalAccount.execute,
            (address(counter), 0, abi.encodeCall(Counter.increment, ()))
        );

        PackedUserOperation memory op1 = _buildSignedUserOp(0, callData);

        PackedUserOperation[] memory ops1 = new PackedUserOperation[](1);
        ops1[0] = op1;

        vm.prank(bundler, bundler);
        ep.handleOps(ops1, payable(beneficiary));

        assertEq(counter.number(), 1);
        emit log_named_uint("s2_first_nonce", op1.nonce);
        emit log_named_uint("s2_counter_after_first", counter.number());
        _appendResult(
            RESULTS_PATH,
            string.concat(
                "s2_first_execution,",
                _toUintString(op1.nonce),
                ",success,success,",
                _toUintString(counter.number()),
                ",initial execution accepted"
            )
        );

        PackedUserOperation memory op2 = _buildSignedUserOp(0, callData);

        PackedUserOperation[] memory ops2 = new PackedUserOperation[](1);
        ops2[0] = op2;

        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOp.selector,
                uint256(0),
                "AA25 invalid account nonce"
            )
        );
        vm.prank(bundler, bundler);
        ep.handleOps(ops2, payable(beneficiary));

        assertEq(counter.number(), 1);
        emit log_named_uint("s2_replay_nonce", op2.nonce);
        emit log_string("s2_replay_failure_reason: AA25 invalid account nonce");
        _appendResult(
            RESULTS_PATH,
            string.concat(
                "s2_replay_execution,",
                _toUintString(op2.nonce),
                ",fail,revert,",
                _toUintString(counter.number()),
                ",AA25 invalid account nonce"
            )
        );
    }

    function _buildSignedUserOp(
        uint256 nonce,
        bytes memory callData
    ) internal returns (PackedUserOperation memory op) {
        op.sender = address(account);
        op.nonce = nonce;
        op.callData = callData;
        op.accountGasLimits = bytes32(
            (uint256(500000) << 128) | uint256(500000)
        );
        op.preVerificationGas = 50000;
        op.gasFees = bytes32((uint256(1 gwei) << 128) | uint256(1 gwei));
        op.paymasterAndData = hex"";

        bytes32 userOpHash = ep.getUserOpHash(op);
        bytes32 ethSignedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, ethSignedHash);
        op.signature = abi.encodePacked(r, s, v);
    }
}
