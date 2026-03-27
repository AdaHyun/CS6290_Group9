// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "./helpers/EvidenceRecorder.sol";

import "account-abstraction/contracts/core/EntryPoint.sol";
import "account-abstraction/contracts/interfaces/IEntryPoint.sol";
import "account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import "../src/MinimalAccount.sol";
import "./Counter.sol";

contract BadSignatureTest is EvidenceRecorder {
    EntryPoint ep;
    MinimalAccount account;
    Counter counter;

    uint256 ownerPk;
    address owner;
    address beneficiary;
    address bundler;

    string internal constant RESULTS_PATH = "results/s3_bad_signature.csv";

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
            "case_id,nonce,signing_key,result,counter,notes"
        );
    }

    function test_invalidSignature_shouldFail() public {
        bytes memory callData = abi.encodeCall(
            MinimalAccount.execute,
            (address(counter), 0, abi.encodeCall(Counter.increment, ()))
        );

        uint256 wrongPk = 0xB0B;
        PackedUserOperation memory op = _buildSignedUserOp(0, callData, wrongPk);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;

        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOp.selector,
                uint256(0),
                "AA24 signature error"
            )
        );
        vm.prank(bundler, bundler);
        ep.handleOps(ops, payable(beneficiary));

        assertEq(counter.number(), 0);
        emit log_string("S3 bad signature failure reason: AA24 signature error");
        _appendResult(
            RESULTS_PATH,
            string.concat(
                "s3_bad_signature,",
                _toUintString(op.nonce),
                ",",
                _toUintString(wrongPk),
                ",revert,",
                _toUintString(counter.number()),
                ",invalid signature rejected"
            )
        );
    }

    function _buildSignedUserOp(
        uint256 nonce,
        bytes memory callData,
        uint256 signingPk
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

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signingPk, ethSignedHash);
        op.signature = abi.encodePacked(r, s, v);
    }
}
