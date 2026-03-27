// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "account-abstraction/contracts/core/BaseAccount.sol";
import "account-abstraction/contracts/interfaces/IEntryPoint.sol";
import "account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract MinimalAccount is BaseAccount {
    address public owner;
    IEntryPoint private immutable _entryPoint;

    constructor(IEntryPoint anEntryPoint, address anOwner) {
        _entryPoint = anEntryPoint;
        owner = anOwner;
    }

    function entryPoint() public view override returns (IEntryPoint) {
        return _entryPoint;
    }

    function execute(
        address dest,
        uint256 value,
        bytes calldata func
    ) external override {
        _requireFromEntryPointOrOwner();
        (bool success, ) = dest.call{value: value}(func);
        require(success, "call failed");
    }

    function _validateSignature(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) internal view override returns (uint256 validationData) {
        bytes32 hash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        address recovered = ECDSA.recover(hash, userOp.signature);

        if (recovered != owner) {
            return SIG_VALIDATION_FAILED;
        }

        return 0;
    }

    function _requireFromEntryPointOrOwner() internal view {
        require(
            msg.sender == address(entryPoint()) || msg.sender == owner,
            "not owner or entrypoint"
        );
    }

    receive() external payable {}
}
