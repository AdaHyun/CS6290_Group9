// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./helpers/EvidenceRecorder.sol";
import "account-abstraction/contracts/core/EntryPoint.sol";
import "account-abstraction/contracts/test/TestPaymasterAcceptAll.sol";
import "account-abstraction/contracts/interfaces/IEntryPoint.sol";
import "../src/MinimalAccount.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract S4_PaymasterInsufficientDepositTest is EvidenceRecorder {
    EntryPoint ep;
    TestPaymasterAcceptAll paymaster;
    MinimalAccount account;

    uint256 private ownerPk;
    address private owner;

    address payable public constant BUNDLER = payable(address(0x5B38Da6a701c568545dCfcB03FcB875f56beddC4));
    address public constant RECIPIENT = address(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2);
    string internal constant RESULTS_PATH = "results/s4_paymaster_deposit.csv";

    function setUp() public {
        ep = new EntryPoint();
        ownerPk = 0xA11CE;
        owner = vm.addr(ownerPk);
        paymaster = new TestPaymasterAcceptAll(ep);
        account = new MinimalAccount(ep, owner);
        vm.deal(address(account), 1 ether);
        // Intentionally do not deposit enough funds for the paymaster.
        _prepareResultsFile(
            RESULTS_PATH,
            "case_id,paymaster_deposit_before,paymaster_deposit_after,result,revert_reason,notes"
        );
    }

    // 关键：按你版本的 9 个字段顺序 + 类型传值
    function createBaseUserOp() internal view returns (PackedUserOperation memory op) {
        bytes memory callData = abi.encodeWithSignature(
            "execute(address,uint256,bytes)",
            RECIPIENT,
            0.1 ether,
            ""
        );

        // 严格按截图里的字段顺序 + 类型构造
        op = PackedUserOperation(
            address(account),
            uint256(0),
            bytes(""),
            callData,
            bytes32(
                (uint256(500000) << 128) | uint256(500000)
            ),
            uint256(21000),
            bytes32(
                (uint256(1 gwei) << 128) | uint256(1 gwei)
            ),
            abi.encodePacked(
                address(paymaster),
                uint128(150000),
                uint128(300000),
                bytes("")
            ),
            bytes("")
        );

        bytes32 userOpHash = ep.getUserOpHash(op);
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, ethSignedHash);
        op.signature = abi.encodePacked(r, s, v);
    }

    function test_S4_PaymasterInsufficientDepositMustFail() public {
        PackedUserOperation memory op = createBaseUserOp();

        uint256 accountBalanceBefore = address(account).balance;
        uint256 paymasterDepositBefore = ep.balanceOf(address(paymaster));
        uint256 nonceBefore = ep.getNonce(address(account), 0);

        string memory revertReason = "AA31 paymaster deposit too low";
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOp.selector,
                uint256(0),
                revertReason
            )
        );
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        vm.prank(BUNDLER, BUNDLER);
        ep.handleOps(ops, BUNDLER);

        assertEq(address(account).balance, accountBalanceBefore, "Account balance changed");
        assertEq(ep.balanceOf(address(paymaster)), paymasterDepositBefore, "Paymaster deposit changed");
        assertEq(ep.getNonce(address(account), 0), nonceBefore, "Nonce incremented");
        emit log_named_uint("s4_paymaster_deposit_before", paymasterDepositBefore);
        emit log_named_uint("s4_paymaster_deposit_after", ep.balanceOf(address(paymaster)));
        emit log_string("S4 failure reason: AA31 paymaster deposit too low");
        _appendResult(
            RESULTS_PATH,
            string.concat(
                "s4_paymaster_insufficient,",
                _toUintString(paymasterDepositBefore),
                ",",
                _toUintString(ep.balanceOf(address(paymaster))),
                ",revert,",
                revertReason,
                ",deposit too low halted sponsored op"
            )
        );
    }
}
