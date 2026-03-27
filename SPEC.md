# SPEC / Test Model

ERC-4337 Account Abstraction Security Testing 

This document defines the security properties (testable requirements) for our ERC-4337 security testing project.
Each property is mapped to one or more test suites under `test/`.

## Scope
- EntryPoint (official reference implementation)
- Paymaster (reference/test implementations from the official repo)
- Account logic required to exercise validation/execution paths (reference/test implementations)

## Conventions
- **Requirement IDs**: S1, S2, ...
- **Evidence**: each requirement must have at least one deterministic test; some requirements also have fuzz/invariant tests.
- **Pass criteria**: the test(s) mapped to a requirement must pass in CI (`forge test`).

---

## S1. Paymaster hooks must only be callable by EntryPoint
**Statement**

- `validatePaymasterUserOp` and `postOp` must only be callable via EntryPoint; any direct invocation by other addresses must revert without mutating state.

**Why**

- Prevents spoofed settlement/validation calls that could bypass EntryPoint’s accounting and safety checks.

**Pass Criteria**

1. Non-EntryPoint call to `validatePaymasterUserOp` reverts immediately.
2. Non-EntryPoint call to `postOp` reverts immediately.
3. Optional (not required now): EntryPoint-originated calls succeed.

**Given / When / Then**

- **Given**: a fresh `EntryPoint` and `TestPaymasterAcceptAll` deployed in `test/PaymasterAuth.t.sol`.
- **When**: the test contract (not the entrypoint) calls the hooks directly:
  - `test_validatePaymasterUserOp_onlyEntryPoint_canCall`
  - `test_postOp_onlyEntryPoint_canCall`
- **Then**: both calls revert and `results/s1_paymaster_access.csv` records `result=revert` with caller address.

---

## S2. Nonce replay must fail
**Statement:** reusing a nonce for the same account must not succeed; replayed UserOps must be rejected. 
**Why:** prevents repeated unauthorized execution.  
**Tests:**

- `test/NonceReplay.t.sol`
  - `test_replayNonce_shouldFail`
    **Pass Criteria:**
- Running `forge test --match-test test_replayNonce_shouldFail -vv` passes.
- The first UserOp with nonce `0` is accepted and executes once.
- Replaying a second UserOp with the same nonce `0` is rejected with `FailedOp(0, "AA25 invalid account nonce")`.
  **Given / When / Then:**
- Given a deployed `EntryPoint`, `MinimalAccount` (owner key known), and a target `Counter` contract.
- Given a valid signed UserOp that calls `MinimalAccount.execute(...Counter.increment...)` with nonce `0`.
- When the bundler submits that UserOp via `handleOps`, and then submits a replayed UserOp with the same nonce `0`.
- Then the first operation succeeds, the replay is rejected for invalid nonce, and `Counter.number()` remains `1`.

---

## S3. Invalid signatures must be rejected
**Statement:** UserOps with invalid signatures must fail validation.  
**Why:** prevents account takeover / unauthorized ops.  
**Tests:**

- `test/BadSignature.t.sol`
  - `test_invalidSignature_shouldFail`
    **Pass Criteria:**
- Running `forge test --match-test test_invalidSignature_shouldFail -vv` passes.
- A UserOp signed by a non-owner key is rejected with `FailedOp(0, "AA24 signature error")`.
- No protected state-changing action is executed when the signature is invalid.
  **Given / When / Then:**
- Given a deployed `EntryPoint`, `MinimalAccount` with owner `ownerPk`, and a target `Counter` contract.
- Given a UserOp that requests `Counter.increment()` but is signed with `wrongPk` (not the account owner key).
- When the bundler submits the UserOp via `handleOps`.
- Then validation fails with signature error and `Counter.number()` stays `0`.

---

## S4. Paymaster deposit constraints must be enforced
**Statement**: When a Paymaster's deposit in EntryPoint is insufficient to cover the gas fees of a UserOp, the Paymaster-sponsored UserOp must revert and fail, with no unintended changes to the user's account balance, Paymaster's deposit, or user's nonce.  
**Why**: Prevent negative balances/accounting inconsistencies and avoid economic losses for Paymasters or user accounts due to insufficient deposits.  
**Associated Tests**: `test/PaymasterInsufficientDeposit.t.sol`

  - `test_S4_PaymasterInsufficientDepositMustFail`
    **Pass Criteria**:

    1. Test passes when executing `forge test --match-test test_S4_PaymasterInsufficientDepositMustFail -vv`;
    2. EntryPoint.handleOps call reverts due to insufficient Paymaster deposit;
    3. Before and after the operation:
       - The balance of the user account (SimpleAccount) remains unchanged at 1 ETH;
       - The Paymaster's deposit in EntryPoint remains unchanged at 0.01 ETH;
       - The user account's nonce remains unchanged at 0.
         **Scenario Flow (Given/When/Then)**:

    - Given:
      EntryPoint, TestPaymasterAcceptAll (0.01 ETH deposit), and SimpleAccount (1 ETH balance) are deployed;
      A valid UserOp is constructed: calls SimpleAccount.execute to transfer 0.1 ETH to RECIPIENT, with paymasterAndData pointing to this Paymaster;
    - When:
      Bundler (BUNDLER address) submits the UserOp via EntryPoint.handleOps;
    - Then:
      The call reverts and fails;
      User account balance = 1 ETH, Paymaster deposit = 0.01 ETH, user nonce = 0 (all consistent with pre-operation state).

---

## S5. Malformed paymasterAndData must fail safely
**Statement**: When a UserOp's paymasterAndData field contains malformed data (e.g., 1-byte length), the UserOp must revert and fail, with no unintended changes to the user's account balance or nonce (Paymaster has sufficient deposit to eliminate fund-related interference).  
**Why**: Improve the protocol's robustness against edge cases in paymasterAndData parsing and avoid state anomalies caused by malformed data.  
**Associated Tests**: `test/PaymasterMalformedDataTest.t.sol`

  - `test_S5_MalformedPaymasterAndDataMustFail`
    **Pass Criteria**:

    1. Test passes when executing `forge test --match-test test_S5_MalformedPaymasterAndDataMustFail -vv`;
    2. EntryPoint.handleOps call reverts due to invalid paymasterAndData format;
    3. Before and after the operation:
       - The balance of the user account (SimpleAccount) remains unchanged at 1 ETH;
       - The user account's nonce remains unchanged at 0.
         **Scenario Flow (Given/When/Then)**:

    - Given:
      EntryPoint, TestPaymasterAcceptAll (1 ETH deposit, sufficient), and SimpleAccount (1 ETH balance) are deployed;
      A UserOp is constructed: all other fields are compliant, only paymasterAndData is set to 1-byte malformed data;
    - When:
      Bundler (BUNDLER address) submits the UserOp via EntryPoint.handleOps;
    - Then:
      The call reverts and fails;
      User account balance = 1 ETH, user nonce = 0 (all consistent with pre-operation state).

---

## S6. Batch processing must isolate failures as intended
**Statement**

- EntryPoint `handleOps` must allow execution-stage failures (e.g. revert in `callData`) to affect only the failing UserOp.
- Validation-level failures (invalid signature, insufficient paymaster deposit, malformed validation data) may halt the entire batch, as defined by the protocol, without corrupting unrelated UserOps.

**Why**

- Preserves availability and DoS resistance; malicious or buggy ops cannot grief honest users by simply sharing a batch.

**Pass Criteria**

1. *Execution failure scenario*: `op1` reverts, `op2` continues (`op2_counter_after = 1`).
2. *Invalid signature scenario*: batch halts with `AA24 signature error`; `op2` must remain unexecuted.
3. *Paymaster deposit low scenario*: batch halts with `AA31`; `op2` must remain unexecuted.
4. No unrelated state (nonce, counter) changes in halted cases.

**Given / When / Then**

- **Given** a `[op1, op2]` pair built from `SimpleAccount` instances, executed by a pranked bundler (address `0xB00B`) with beneficiary `0xBEEF` and `gasPrice = 1 gwei`.
- **When** `test/BatchIsolation.t.sol` runs:
  - `test_batchIsolation_keeps_successful_ops_running`
  - `test_batchIsolation_invalidSignature_revertsEntireBatch`
  - `test_batchIsolation_paymasterDepositTooLow_revertsBatch`
- **Then** `results/s6_batch_outcome.csv` records `op2_effect = 1` for the execution-only failure and `0` for the validation/paymaster failures, with notes identifying `AA24/AA31`

---

## S7. Gas charging must be bounded (no overcharging beyond defined limits)
**Statement**

- For every UserOp (self-funded or paymaster-sponsored), `actualGasCost` reported by EntryPoint must never exceed the prefund/upper bound derived from the UserOp’s gas limit fields, and must exactly match the observable ETH transfer (beneficiary delta or paymaster deposit decrease).

**Why**

- Guarantees economic safety; prevents overcharging and keeps incentives consistent.

**Pass Criteria**

1. *Account-funded case*: `actual_gas_cost == beneficiary_delta > 0`, and `actual_gas_cost <= upper_bound`.
2. *Paymaster-sponsored case*: same inequalities plus `paymaster_deposit_before - paymaster_deposit_after == actual_gas_cost`.
3. *Paymaster with postOp*: same as (2), covering large verification/postOp gas limits.
4. All values must be logged and recorded in `results/s7_fee_bound.csv`.

**Given / When / Then**

- **Given** `vm.txGasPrice = 1 gwei`, beneficiary `0xBEEF`, and `upper_bound = (callGas + verificationGas + preVerificationGas) * maxFeePerGas`.
- **When** `test/FeeBound.t.sol` runs:
  - `test_feeCharged_isWithinBound` (account + standard paymaster)
  - `test_feeBounds_paymasterWithPostOp_bound`
- **Then** each CSV row shows `upper_bound >= actual_gas_cost` and `beneficiary_delta == actual_gas_cost`; for paymaster cases the deposit delta also equals these values.

---

## S8. Failure-mode behavior must be consistent and observable
**Statement**

- Common failure modes—including bad signature, bad nonce, insufficient paymaster deposit, invalid `paymasterAndData`, or rejected paymaster—must produce **unique, machine-readable revert reasons** and emit a **standardized `FailedOp` event** from `EntryPoint` containing a human- and machine-parsable `failureCode`. All failure outcomes must be deterministic (same input → same failure), and no failure mode produces a generic or ambiguous revert (e.g., `"revert"` with no message).

**Why**

- Ensures economic and protocol safety by reducing griefing caused by ambiguous failures.
- Enables bundlers to reliably filter, retry, or drop UserOps.
- Improves observability, debugging, and automated tooling for ERC‑4337 UserOperations.

**Pass Criteria**

1. Each core failure mode triggers a **unique revert reason** (e.g., `"EntryPoint: invalid signature"`, `"EntryPoint: nonce already used"`, `"Paymaster: insufficient deposit"`).
2. `EntryPoint` emits a **`FailedOp` event** for all rejected UserOps, with event parameters including a `failureCode` (`uint256`) mapping to the specific failure mode.
3. The same failure mode (same input) produces the **same revert reason + failureCode** consistently (deterministic).
4. No core failure mode results in a generic revert (no message) or an unhandled panic (e.g., divide by zero).

**Given / When / Then Test Scenarios**

- **Scenario 1: Bad Signature**
  - **Given** a valid Account and a UserOp with an invalid ECDSA signature
  - **When** the UserOp is submitted to `EntryPoint.handleOps`
  - **Then** the call reverts with `"EntryPoint: invalid signature"` and `EntryPoint` emits `FailedOp(failureCode=1, …)`
- **Scenario 2: Bad Nonce**
  - **Given** a valid Account with `nonce=0` that has already been used
  - **When** a UserOp with `nonce=0` is submitted to `EntryPoint.handleOps`
  - **Then** the call reverts with `"EntryPoint: nonce already used"` and emits `FailedOp(failureCode=2, …)`
- **Scenario 3: Insufficient Paymaster Deposit**
  - **Given** a Paymaster with zero deposit in `EntryPoint` and a sponsored UserOp
  - **When** the UserOp is submitted to `EntryPoint.handleOps`
  - **Then** the call reverts with `"Paymaster: insufficient deposit"` and emits `FailedOp(failureCode=3, …)`
- **Scenario 4: Malformed `PaymasterAndData`**
  - **Given** a valid Paymaster and a UserOp with malformed `paymasterAndData` (wrong length, invalid encoding, etc.)
  - **When** the UserOp is submitted to `EntryPoint.handleOps`
  - **Then** the call reverts with `"Paymaster: malformed paymasterAndData"` and emits `FailedOp(failureCode=4, …)`

**Tests**

- `test/FailureClassification.t.sol`
  - `test_failureReason_badSignature_isConsistent`
  - `test_failureReason_badNonce_isConsistent`
  - `test_failureReason_insufficientPaymasterDeposit_isConsistent`
  - `test_failureReason_malformedPaymasterData_isConsistent`
  - `test_failedOpEvent_includesCorrectFailureCode`



---

## S9. Simulation vs execution consistency (griefing resistance)
**Statement**

- UserOps that pass a **standardized off-chain simulation** (mimicking bundler behavior) must **not fail on-chain** under equivalent execution conditions (same block context, gas limits, state).
- For unavoidable mismatches (e.g., external state changes), the on-chain failure **must be bounded** and **must not cause unintended state changes**.
- If simulation consistency cannot be tested, an **invariant test** for core protocol properties (e.g., `"Paymaster deposit never goes negative"`, `"EntryPoint never overcharges gas"`) is an acceptable substitute.

**Why**

- Mitigates bundler griefing vectors.
- Ensures predictable protocol behavior across off-chain and on-chain contexts.
- Invariant tests enforce core safety properties even when full simulation consistency cannot be tested.

**Pass Criteria (Simulation Consistency)**

1. A UserOp that passes the mock bundler simulation (in test harness) **succeeds on-chain** when submitted with the same gas limits/block context.
2. If a simulated UserOp fails on-chain, the failure is caused **only by external state changes** and **does not modify Account/Paymaster/EntryPoint state**.
3. The number of simulation-to-execution mismatches is **bounded** (≤ 0% for controlled test conditions).

**Pass Criteria (Invariant Test Substitute, RECOMMENDED)**

1. The invariant test runs for **≥ 1000 fuzz runs** without violating the core property.
2. The core property (e.g., `"Paymaster deposit in EntryPoint is always ≥ 0"`, `"Account nonce is strictly increasing"`) holds for all valid/invalid UserOps.
3. Any invariant violation triggers a **clear revert reason** and **does not corrupt state**.

**Given / When / Then Test Scenarios (Simulation Consistency)**

- **Scenario 1 (Valid UserOp)**
  - **Given** a valid UserOp that passes mock bundler simulation (signature, nonce, deposit all valid)
  - **When** the UserOp is submitted on-chain with the same gas limits/block context
  - **Then** the UserOp succeeds, and Account/Paymaster state updates as expected
- **Scenario 2 (Simulated Success, External State Change)**
  - **Given** a UserOp that passes simulation, but the Paymaster deposit is drained by a separate transaction before on-chain submission
  - **When** the UserOp is submitted on-chain
  - **Then** the UserOp fails with `"Paymaster: insufficient deposit"` (consistent failure classification), and no unintended state changes occur

**Given / When / Then Test Scenarios (Invariant Test)**

- **Scenario 1 (Paymaster Deposit Invariant)**
  - **Given** a Paymaster with 1 ETH deposit in EntryPoint
  - **When** fuzzed UserOps (valid/invalid) are submitted to `EntryPoint.handleOps`
  - **Then** the Paymaster deposit in EntryPoint is **never negative**
- **Scenario 2 (Account Nonce Invariant)**
  - **Given** a valid Account with initial nonce 0
  - **When** fuzzed UserOps are submitted to `EntryPoint.handleOps`
  - **Then** the Account nonce is **always strictly increasing** (no reuse)

**Tests**

- **Option 1 (Simulation Consistency)**: `test/SimulateConsistency.t.sol`
  - `test_simulatedValidUserOp_succeedsOnChain`
  - `test_simulatedUserOp_failure_onlyOnExternalStateChange`
- **Option 2 (Invariant Test, RECOMMENDED)**: `test/invariant/FeeInvariant.t.sol` or `test/invariant/PaymasterInvariant.t.sol`
  - `invariant_paymasterDepositNeverNegative`
  - `invariant_accountNonceStrictlyIncreasing`
  - `invariant_entryPointNeverOverchargesGas`

