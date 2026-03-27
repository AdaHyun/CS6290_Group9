// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "account-abstraction/contracts/core/EntryPoint.sol";
import "account-abstraction/contracts/accounts/SimpleAccount.sol";
import "account-abstraction/contracts/accounts/SimpleAccountFactory.sol";
import "account-abstraction/contracts/interfaces/PackedUserOperation.sol";

abstract contract UserOpTestBase is Test {
    EntryPoint internal entryPoint;
    SimpleAccountFactory internal accountFactory;
    address internal constant BUNDLER = address(0xB00B);

    struct UserOpParams {
        uint256 ownerKey;
        uint256 signingKey;
        uint256 salt;
        bool freshDeployment;
        address target;
        bytes targetCallData;
        uint256 callGasLimit;
        uint256 verificationGasLimit;
        uint256 preVerificationGas;
        uint256 maxFeePerGas;
        uint256 maxPriorityFeePerGas;
        bytes paymasterAndData;
    }

    function setUp() public virtual {
        entryPoint = new EntryPoint();
        accountFactory = new SimpleAccountFactory(entryPoint);
        vm.deal(address(this), 100 ether);
    }

    function _packAccountGasLimits(
        uint256 verificationGasLimit,
        uint256 callGasLimit
    ) internal pure returns (bytes32) {
        return bytes32((verificationGasLimit << 128) | callGasLimit);
    }

    function _packGasFees(
        uint256 maxPriorityFeePerGas,
        uint256 maxFeePerGas
    ) internal pure returns (bytes32) {
        return bytes32((maxPriorityFeePerGas << 128) | maxFeePerGas);
    }

    function _accountInitCode(
        address owner,
        uint256 salt
    ) internal view returns (bytes memory) {
        return abi.encodePacked(
            address(accountFactory),
            abi.encodeCall(SimpleAccountFactory.createAccount, (owner, salt))
        );
    }

    function _senderAddress(
        address owner,
        uint256 salt
    ) internal view returns (address) {
        return accountFactory.getAddress(owner, salt);
    }

    function _depositFor(address account, uint256 amount) internal {
        entryPoint.depositTo{value: amount}(account);
    }

    function _prepareResultsFile(
        string memory path,
        string memory header
    ) internal {
        if (!vm.isFile(path)) {
            vm.createDir("results", true);
            vm.writeFile(path, string.concat(header, "\n"));
        }
    }

    function _appendResults(string memory path, string memory row) internal {
        vm.writeLine(path, row);
    }

    function _handleOps(
        PackedUserOperation[] memory ops,
        address payable beneficiary
    ) internal {
        vm.prank(BUNDLER, BUNDLER);
        entryPoint.handleOps(ops, beneficiary);
    }

    function _createPaymasterData(
        address paymaster,
        uint256 verificationGasLimit,
        uint256 postOpGasLimit,
        bytes memory extraData
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            paymaster,
            bytes16(uint128(verificationGasLimit)),
            bytes16(uint128(postOpGasLimit)),
            extraData
        );
    }

    function _buildUserOp(
        UserOpParams memory params
    ) internal view returns (PackedUserOperation memory userOp, address sender) {
        address owner = vm.addr(params.ownerKey);
        sender = _senderAddress(owner, params.salt);

        bytes memory initCode = params.freshDeployment
            ? _accountInitCode(owner, params.salt)
            : bytes("");

        userOp = PackedUserOperation({
            sender: sender,
            nonce: entryPoint.getNonce(sender, 0),
            initCode: initCode,
            callData: abi.encodeWithSignature(
                "execute(address,uint256,bytes)",
                params.target,
                0,
                params.targetCallData
            ),
            accountGasLimits: _packAccountGasLimits(
                params.verificationGasLimit,
                params.callGasLimit
            ),
            preVerificationGas: params.preVerificationGas,
            gasFees: _packGasFees(
                params.maxPriorityFeePerGas,
                params.maxFeePerGas
            ),
            paymasterAndData: params.paymasterAndData,
            signature: ""
        });

        uint256 signingKey = params.signingKey == 0
            ? params.ownerKey
            : params.signingKey;
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signingKey, userOpHash);
        userOp.signature = abi.encodePacked(r, s, v);
    }
}
