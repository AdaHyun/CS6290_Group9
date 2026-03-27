// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./helpers/EvidenceRecorder.sol";
import "account-abstraction/contracts/core/EntryPoint.sol";
import "account-abstraction/contracts/test/TestPaymasterAcceptAll.sol";
import "account-abstraction/contracts/accounts/SimpleAccount.sol";
import "account-abstraction/contracts/interfaces/IEntryPoint.sol";

contract S5_MalformedPaymasterAndDataTest is EvidenceRecorder {
    EntryPoint ep;
    TestPaymasterAcceptAll paymaster;
    SimpleAccount account;

    address payable public constant BUNDLER = payable(address(0x5B38Da6a701c568545dCfcB03FcB875f56beddC4));
    address public constant RECIPIENT = address(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2);
    string internal constant RESULTS_PATH = "results/s5_paymaster_malformed.csv";

    function setUp() public {
        ep = new EntryPoint();
        paymaster = new TestPaymasterAcceptAll(ep);
        account = new SimpleAccount(ep);
        vm.deal(address(account), 1 ether);
        ep.depositTo{value: 1 ether}(address(paymaster));
        _prepareResultsFile(
            RESULTS_PATH,
            "case_id,paymaster_data_length,result,revert_reason,notes"
        );
    }

    function createBaseUserOp() internal view returns (PackedUserOperation memory op) {
        bytes memory callData = abi.encodeWithSignature(
            "execute(address,uint256,bytes)",
            RECIPIENT,
            0.1 ether,
            ""
        );

        // 严格按截图里的字段顺序 + 类型构造
        op = PackedUserOperation(
            address(account),    // 1. sender (address)
            uint256(0),          // 2. nonce (uint256)
            bytes(""),           // 3. initCode (bytes)
            callData,            // 4. callData (bytes)
            bytes32(
                (uint256(500000) << 128) | uint256(500000)
            ),                   // 5. accountGasLimits (bytes32)
            uint256(21000),      // 6. preVerificationGas (uint256)
            bytes32(
                (uint256(1 gwei) << 128) | uint256(1 gwei)
            ),                   // 7. gasFees (bytes32)
            bytes(""),           // 8. paymasterAndData (bytes)
            bytes("")            // 9. signature (bytes)
        );
    }

    function test_S5_MalformedPaymasterAndDataMustFail() public {
        PackedUserOperation memory op = createBaseUserOp();
        // 畸形 paymasterAndData：长度仅 1 字节
        op.paymasterAndData = new bytes(1);

        uint256 accountBalanceBefore = address(account).balance;
        uint256 nonceBefore = ep.getNonce(address(account), 0);

        string memory revertReason = "InvalidPaymasterData";
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.InvalidPaymasterData.selector,
                op.paymasterAndData.length
            )
        );
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        vm.prank(BUNDLER, BUNDLER);
        ep.handleOps(ops, BUNDLER);

        assertEq(address(account).balance, accountBalanceBefore, "Account balance changed");
        assertEq(ep.getNonce(address(account), 0), nonceBefore, "Nonce incremented");
        emit log_named_uint(
            "s5_malformed_paymaster_data_length",
            op.paymasterAndData.length
        );
        emit log_string("S5 failure reason: malformed paymasterAndData rejected");
        _appendResult(
            RESULTS_PATH,
            string.concat(
                "s5_malformed_paymaster_data,",
                _toUintString(op.paymasterAndData.length),
                ",revert,",
                revertReason,
                ",malformed paymaster data blocked"
            )
        );
    }
}
