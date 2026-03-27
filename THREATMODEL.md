# Threat Model

ERC-4337 Account Abstraction Security Testing (0.ver)

## 1. System Overview
This project focuses on security testing for ERC-4337 Account Abstraction (AA), primarily around the on-chain components:
- **EntryPoint**: the central contract that validates and executes UserOperations in batches.
- **Smart Account (Account)**: validates a UserOperation (e.g., signature/nonce) and performs the requested call(s).
- **Paymaster (optional)**: sponsors gas fees for UserOperations and is called back for settlement.

High-level flow (simplified):
1. A user creates a **UserOperation (UserOp)**.
2. A bundler collects UserOps and submits a transaction to **EntryPoint.handleOps(...)**.
3. EntryPoint performs validation via **Account.validateUserOp(...)** and (if used) **Paymaster.validatePaymasterUserOp(...)**.
4. EntryPoint executes the operation and finalizes gas accounting, calling **Paymaster.postOp(...)** when applicable.

## 2. In-Scope Components
### In-scope
- EntryPoint contract (official reference implementation)
- Paymaster contracts (reference/test implementations)
- Account logic needed to exercise validation/execution behavior (reference/test implementations)
- The UserOperation data fields relevant to validation, gas limits, and paymaster data

### Out-of-scope (for v0; may be discussed as assumptions)
- Real public mempool behavior and network-level MEV/latency effects
- Production bundler infrastructure correctness (we model bundler behavior and call EntryPoint directly in tests)
- External third-party Paymaster services (off-chain policies)

## 3. Assets (What We Protect)
1. **Funds / Deposits**
   - Paymaster deposit/stake in EntryPoint
   - Account deposit and account-controlled value
2. **Authorization Correctness**
   - Signature verification correctness
   - Nonce correctness (no replay)
3. **Integrity of Gas Accounting**
   - No overcharging beyond specified bounds
   - Correct charging/refunding behavior in success and failure cases
4. **Availability**
   - Batch processing should not be trivially DoS’ed by a single malicious UserOp
   - Bundler gas griefing cost should be bounded as much as the protocol intends
5. **State Safety**
   - Malformed inputs should not cause unintended state transitions

## 4. Adversary Model (Who Attacks)
### A1. Malicious User (primary)
Capabilities:
- Crafts arbitrary UserOperations, including malformed fields and extreme gas parameters.
Goals:
- Bypass validation, replay operations, cause unexpected state transitions,
- Trigger high-cost execution paths to grief bundlers or drain paymaster resources.

### A2. Malicious or Self-Interested Bundler
Capabilities:
- Chooses which UserOps to include, orders them, and sets transaction context.
Goals:
- Exploit accounting edge cases, cause selective inclusion, or amplify griefing.

### A3. Malicious Paymaster
Capabilities:
- Implements custom validation and postOp logic.
Goals:
- Refuse payment strategically, manipulate settlement behavior, or create unexpected failure modes.

### A4. External Contract / Callee Adversary
Capabilities:
- Target contracts called by the Smart Account may revert, consume gas, or attempt reentrancy-like patterns.
Goals:
- Induce inconsistent execution/settlement outcomes or unexpected failures.

## 5. Trust Assumptions
- EVM execution and consensus are correct.
- The official reference implementation is the baseline under test (we do not assume it is bug-free).
- Cryptographic primitives (e.g., ECDSA) behave as intended.
- When we do not run a full bundler, we assume our test harness can approximate bundler submission by calling EntryPoint directly.

## 6. Attack Surfaces (Where Bugs May Exist)
1. **EntryPoint batch execution**
   - `handleOps(...)` validation and execution pipeline
   - gas accounting/settlement logic
2. **Account validation**
   - `validateUserOp(...)`: signature/nonce rules, timing checks, paymaster-related logic
3. **Paymaster hooks**
   - `validatePaymasterUserOp(...)`: sponsor decision, data parsing, cost bounding
   - `postOp(...)`: settlement, refunds, bookkeeping, and failure handling
4. **UserOperation input fields**
   - `nonce`, `callData`, `initCode` (if used)
   - gas parameters (verification/call/preVerification) and fee parameters
   - `paymasterAndData` encoding and length/format edge cases

## 7. Threats
Below are the concrete threat hypotheses we aim to test and/or mitigate.

### T1. Direct Invocation of Paymaster Hooks (Access Control)

- `validatePaymasterUserOp` and `postOp` must only be callable by EntryPoint.
  Impact: attackers can spoof settlement flows or manipulate paymaster bookkeeping.

- Attack steps: attacker invokes paymaster hooks directly to spoof verification or settle fake operations.
- Preconditions: paymaster exposes public methods; EntryPoint may not mediate the call.
- Impact: accounting inconsistencies, spoofed sponsorship.
- Mitigation/Tests: paymaster hooks are `onlyEntryPoint`; S1 tests prove unauthorized callers are blocked.

### T2. Replay Attacks (Nonce misuse)
- Reusing a previously accepted nonce should not succeed.
  Impact: unauthorized repeated actions, loss of funds/state integrity.
  Status: Implemented and verified.
  Evidence:
- `test/NonceReplay.t.sol::test_replayNonce_shouldFail`
- First `handleOps` with nonce `0` succeeds; replay with nonce `0` reverts with `FailedOp(0, "AA25 invalid account nonce")`.

### T3. Signature / Authorization Bypass
- Invalid signatures must not be accepted; signature validation must be strict.
  Impact: account takeover, unauthorized operations.
  Status: Implemented and verified.
  
- Evidence:

  `test/BadSignature.t.sol::test_invalidSignature_shouldFail`

- UserOp signed by a non-owner key reverts with `FailedOp(0, "AA24 signature error")`, and target state remains unchanged.

### T4. Paymaster Deposit Drain / Economic Griefing
- Attackers craft UserOps that force a paymaster with zero (or otherwise insufficient) deposit to sponsor execution. In our tests the paymaster withdraws its entire deposit before `handleOps`, so any sponsored call must revert prior to state changes.
- Impact: depletion of paymaster deposit, denial of service for legitimate users, unintended state changes (e.g., nonce increment, balance deduction) even after failure.
- Status: Implemented and verified.
- Evidence:
  - `test/PaymasterInsufficientDepositTest.t.sol::test_S4_PaymasterInsufficientDepositMustFail`
  - `results/s4_paymaster_deposit.csv` shows deposit before/after equal to zero with `result=revert (AA31)`.
  - User account balance and nonce remain unchanged when EntryPoint halts the sponsored operation.

### T5. Malformed Data / Parsing Edge Cases

- Malformed `paymasterAndData` (e.g., 1-byte length) should fail safely without unintended state changes — even when the paymaster has sufficient deposit.
- Impact: unexpected reverts, accounting bugs, state corruption (e.g., balance/nonce changes) from malformed input parsing.
- Status: Implemented and verified.
- Evidence:
  - `test/PaymasterMalformedDataTest.t.sol:test_S5_MalformedPaymasterAndDataMustFail`
  - UserOp with 1-byte `paymasterAndData` (paymaster has 1 ETH sufficient deposit); `handleOps` reverts, and:
    - User account balance remains 1 ETH (unchanged)
    - User nonce remains 0 (unchanged)

### T6. Batch DoS / Failure Isolation Issues
- **Attack steps**: A malicious account constructs a UserOp that reverts or has malformed validation data, and includes it at the beginning of a batch so that subsequent transactions might be blocked.
- **Preconditions**: Bundler accepts mixed batches; EntryPoint must enforce nonReentrant bundler rule but all ops share the same handleOps call.
- **Impact**: If failure isolation breaks, later UserOps (potentially unrelated users) can be griefed or held hostage, reducing throughput or enabling targeted DoS.
- **Mitigation**: EntryPoint must isolate execution-only failures and only halt batches for validation-level faults; `test/BatchIsolation.t.sol` enforces this and writes to `results/s6_batch_outcome.csv`.
- **Testability**: Verified via the three cases described above (execution failure, invalid signature, paymaster deposit low) with explicit assertions/logs/CSV entries.

### T7. Overcharging / Incorrect Gas Accounting

- **Attack steps**: A malicious or buggy EntryPoint implementation might charge users more than the prefund by miscalculating gas or doing extra deductions in postOp. Alternatively, paymaster settlements might diverge from the actualGasCost reported.
- **Preconditions**: UserOps rely on EntryPoint to enforce prefunds and refund logic; bundlers may set basefee / priority fee arbitrarily.
- **Impact**: Accounts or paymasters lose funds beyond what they signed for, breaking economic safety guarantees.
- **Mitigation**: Compute a conservative bound from UserOp gas fields and ensure actual charges (beneficiary balance increase, paymaster deposit decrease) equal the reported actualGasCost. `test/FeeBound.t.sol` implements these checks and records outcomes in `results/s7_fee_bound.csv`.
- **Testability**: Account case + two paymaster cases (with/without postOp) verify both bounding and accounting consistency via logs, assertions, and CSV evidence.

### T8. Simulation vs Execution Consistency
- Attack steps: a bundler relies on off-chain simulation and includes a UserOp that later reverts on-chain, forcing the bundler (or paymaster) to eat the gas cost.
- Impact: economic griefing and reduced availability if bundlers lose trust in simulation.
- Current coverage: we log and compare simple invariants (paymaster deposit non-negative and non-increasing, account nonce monotonic) in `test/PaymasterInvariant.t.sol`, with results stored in `results/s9_simulation_vs_execution.csv`. These checks ensure observable state matches expectations, but they do not yet emulate full `simulateValidation` vs `handleOps` parity.
- Future work: extend the threat to true simulation-context fuzzing once a bundler harness is available.

### T9. Failure Classification (Observability & Griefing)
- Attack steps: ambiguous error reporting allows attackers to blur the line between recoverable and unrecoverable failures, wasting bundler gas.
- Impact: bundlers retry hopeless UserOps or drop valid ones, and protocol bugs may go unnoticed.
- Current coverage: `test/FailureClassification.t.sol` enumerates common failure classes (bad signature, duplicate nonce, insufficient deposit, malformed paymaster data) and asserts unique codes/metrics, recorded in `results/s8_failure_classification.csv`. This gives bundlers a concrete mapping for the most common errors.
- Future work: extend the tests to parse real `FailedOp` events from EntryPoint and to fuzz additional malformed inputs.

## 8. Mapping to Tests (Current Status)
- **T1 → S1**: `test/PaymasterAuth.t.sol` (`results/s1_paymaster_access.csv`)
- **T2 → S2**: `test/NonceReplay.t.sol` (`results/s2_nonce_replay.csv`)
- **T3 → S3**: `test/BadSignature.t.sol` (`results/s3_bad_signature.csv`)
- **T4 → S4**: `test/PaymasterInsufficientDepositTest.t.sol` (`results/s4_paymaster_deposit.csv`)
- **T5 → S5**: `test/PaymasterMalformedDataTest.t.sol` (`results/s5_paymaster_malformed.csv`)
- **T6 → S6**: `test/BatchIsolation.t.sol` (three cases, `results/s6_batch_outcome.csv`)
- **T7 → S7**: `test/FeeBound.t.sol` (`results/s7_fee_bound.csv`)
- **T8 → S9**: `test/PaymasterInvariant.t.sol` (`results/s9_simulation_vs_execution.csv`)
- **T9 → S8**: `test/FailureClassification.t.sol` (`results/s8_failure_classification.csv`)

## 9. Notes / Future Extensions
- Expand S8 by parsing EntryPoint `FailedOp` events and covering additional malformed inputs via fuzz.
- Upgrade S9 from simple invariants to a true `simulateValidation` vs `handleOps` differential test (potentially via a mini bundler harness).
- Add differential testing across multiple paymaster/account variants and optional end-to-end demos.
