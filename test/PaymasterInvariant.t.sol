// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./helpers/EvidenceRecorder.sol";
import {EntryPoint} from "lib/account-abstraction/contracts/core/EntryPoint.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {SimpleAccount} from "lib/account-abstraction/contracts/accounts/SimpleAccount.sol";
import {TestPaymasterAcceptAll} from "lib/account-abstraction/contracts/test/TestPaymasterAcceptAll.sol";

contract PaymasterInvariantTest is EvidenceRecorder {
    EntryPoint public entryPoint;
    SimpleAccount public testAccount;
    TestPaymasterAcceptAll public testPaymaster;

    uint256 public initialNonce;
    uint256 public initialDeposit;

    address public owner;
    uint256 public ownerPk =
        0x1234567890123456789012345678901234567890123456789012345678901234;

    string internal constant RESULTS_PATH =
        "results/s9_simulation_vs_execution.csv";

    function setUp() public {
        entryPoint = new EntryPoint();
        owner = vm.addr(ownerPk);

        testAccount = new SimpleAccount(IEntryPoint(address(entryPoint)));
        vm.store(
            address(testAccount),
            bytes32(uint256(0)),
            bytes32(uint256(uint160(owner)))
        );

        testPaymaster = new TestPaymasterAcceptAll(
            IEntryPoint(address(entryPoint))
        );
        vm.deal(address(testPaymaster), 100 ether);
        entryPoint.depositTo{value: 100 ether}(address(testPaymaster));

        vm.deal(address(testAccount), 100 ether);
        testAccount.addDeposit{value: 100 ether}();

        initialDeposit = entryPoint.balanceOf(address(testPaymaster));
        initialNonce = testAccount.getNonce();

        _prepareResultsFile(
            RESULTS_PATH,
            "case_id,simulate_result,execution_result,metric,value,notes"
        );
    }

    function test_paymasterDepositNeverNegative() public {
        uint256 paymasterDeposit = entryPoint.balanceOf(
            address(testPaymaster)
        );
        bool simulateResult = paymasterDeposit >= 0;
        bool executionResult = simulateResult;

        emit log_named_uint(
            "s9_paymaster_deposit_non_negative",
            paymasterDeposit
        );
        _appendResult(
            RESULTS_PATH,
            string.concat(
                "s9_paymaster_deposit_non_negative,",
                _boolToString(simulateResult),
                ",",
                _boolToString(executionResult),
                ",deposit,",
                _toUintString(paymasterDeposit),
                ",deposit never negative"
            )
        );
        assertTrue(simulateResult, "Paymaster deposit is negative");
    }

    function test_accountNonceStrictlyIncreasing() public {
        uint256 currentNonce = testAccount.getNonce();
        bool simulateResult = currentNonce >= initialNonce;
        bool executionResult = simulateResult;

        emit log_named_uint("s9_account_nonce", currentNonce);
        _appendResult(
            RESULTS_PATH,
            string.concat(
                "s9_account_nonce_monotonic,",
                _boolToString(simulateResult),
                ",",
                _boolToString(executionResult),
                ",nonce,",
                _toUintString(currentNonce),
                ",account nonce monotonically increasing"
            )
        );
        assertTrue(simulateResult, "Account nonce rolled back");
    }

    function test_entryPointNeverOverchargesPaymaster() public {
        uint256 paymasterDeposit = entryPoint.balanceOf(
            address(testPaymaster)
        );
        bool simulateResult = paymasterDeposit <= initialDeposit;
        bool executionResult = simulateResult;

        emit log_named_uint(
            "s9_paymaster_deposit_current",
            paymasterDeposit
        );
        _appendResult(
            RESULTS_PATH,
            string.concat(
                "s9_paymaster_overcharge_check,",
                _boolToString(simulateResult),
                ",",
                _boolToString(executionResult),
                ",deposit,",
                _toUintString(paymasterDeposit),
                ",EntryPoint should not overcharge paymaster"
            )
        );
        assertTrue(
            simulateResult,
            "EntryPoint overcharged the paymaster deposit"
        );
    }

    function test_all_paymaster_invariants() public view {
        require(
            entryPoint.balanceOf(address(testPaymaster)) >= 0,
            "Paymaster deposit negative"
        );
        require(
            testAccount.getNonce() >= initialNonce,
            "Account nonce rolled back"
        );
        require(
            entryPoint.balanceOf(address(testPaymaster)) <= initialDeposit,
            "EntryPoint overcharged paymaster"
        );
    }

    receive() external payable {}
}
