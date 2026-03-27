// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

abstract contract EvidenceRecorder is Test {
    using Strings for uint256;

    function _prepareResultsFile(
        string memory path,
        string memory header
    ) internal {
        if (!vm.isFile(path)) {
            vm.createDir("results", true);
            vm.writeFile(path, string.concat(header, "\n"));
        }
    }

    function _appendResult(
        string memory path,
        string memory row
    ) internal {
        vm.writeLine(path, row);
    }

    function _toAddressString(address account) internal pure returns (string memory) {
        return Strings.toHexString(uint256(uint160(account)), 20);
    }

    function _toUintString(uint256 value) internal pure returns (string memory) {
        return Strings.toString(value);
    }

    function _boolToString(bool value) internal pure returns (string memory) {
        return value ? "pass" : "fail";
    }
}
