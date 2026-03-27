# Evidence Results

## Rule: S1  
**Threat:** T1 (Paymaster hook access control)  
**What we tested:** `test/PaymasterAuth.t.sol` directly called `validatePaymasterUserOp` and `postOp` from a non-EntryPoint address to make sure both hooks reject unauthorized callers.  
**Setup:** Each test deploys a fresh `EntryPoint` and `TestPaymasterAcceptAll`; calls are sent from the test contract without any EntryPoint context.  
**Observations:** `results/s1_paymaster_access.csv` lists both cases with `result=revert` and the exact caller address. Logs mirror the same message (“non-entrypoint caller blocked”).  
**Conclusion:** Paymaster hooks revert unless EntryPoint invokes them, satisfying S1/T1.

## Rule: S2  
**Threat:** T2 (Nonce replay)  
**What we tested:** `test/NonceReplay.t.sol::test_replayNonce_shouldFail` executed nonce `0` twice against `MinimalAccount`. The first operation should succeed, while the replay must revert with `AA25`.  
**Setup:** MinimalAccount is funded and signs a call to `Counter.increment()`. EntryPoint is invoked from a pranked bundler to satisfy its `nonReentrant` check.  
**Observations:** `results/s2_nonce_replay.csv` has two rows. The first row reports `result=success` and `counter=1`. The second row reports `result=revert` with the note `AA25 invalid account nonce`, and the counter remains `1`.  
**Conclusion:** Nonce reuse is rejected exactly once the first operation is accepted, fulfilling S2/T2.

## Rule: S3  
**Threat:** T3 (Invalid signature rejection)  
**What we tested:** `test/BadSignature.t.sol::test_invalidSignature_shouldFail` signed a UserOp with the wrong private key and attempted to execute the same counter increment.  
**Setup:** Identical to S2, but the signature uses `0xB0B` instead of the owner key.  
**Observations:** `results/s3_bad_signature.csv` contains one row with the wrong signing key, `result=revert`, and `counter=0`. Logs note the `AA24 signature error`.  
**Conclusion:** Mis-signed UserOps are rejected without touching state, covering S3/T3.

## Rule: S4  
**Threat:** T4 (Paymaster deposit drain / insufficient deposit)  
**What we tested:** `test/PaymasterInsufficientDepositTest.t.sol::test_S4_PaymasterInsufficientDepositMustFail` attempted a sponsored transfer when the paymaster’s deposit was below the required prefund.  
**Setup:** `TestPaymasterAcceptAll` only deposits `0.01 ether` yet the UserOp tries to forward `0.1 ether`. Bundler calls are pranked so EntryPoint runs normally.  
**Observations:** `results/s4_paymaster_deposit.csv` shows identical deposit values before/after with `result=revert` and the note `AA31 paymaster deposit too low`. Logs also print the deposit numbers.  
**Conclusion:** The sponsored call stops before execution because the deposit is insufficient, satisfying S4/T4.

## Rule: S5  
**Threat:** T5 (Malformed paymasterAndData must fail safely)  
**What we tested:** `test/PaymasterMalformedDataTest.t.sol::test_S5_MalformedPaymasterAndDataMustFail` crafted a UserOp whose `paymasterAndData` length was one byte, then sent it through EntryPoint.  
**Setup:** The paymaster had ample deposit so the only fault was the malformed data blob. Bundler calls were pranked to mimic a real submission.  
**Observations:** `results/s5_paymaster_malformed.csv` records `paymaster_data_length=1` and `result=revert` with the note “malformed paymaster data blocked”. Account balances and nonces remain unchanged.  
**Conclusion:** Invalid encodings are caught during validation, covering S5/T5.

## Rule: S6  
**Threat:** T6 (Batch failure isolation)  
**What we tested:** `test/BatchIsolation.t.sol` covers three cases: (1) an execution-stage revert in `op1` while `op2` succeeds; (2) invalid signature (`AA24`) halting the entire batch; (3) paymaster deposit failure (`AA31`).  
**Setup:** Each case assembles `[op1, op2]` via `SimpleAccount`s and uses a pranked bundler with `gasPrice=1 gwei`.  
**Observations:** `results/s6_batch_outcome.csv` logs `op2_effect=1` for the continued-execution case and `0` for the two failure cases, together with textual notes.  
**Conclusion:** Execution reverts stay isolated, whereas validation/paymaster faults stop the batch, satisfying S6/T6.

## Rule: S7  
**Threat:** T7 (Overcharging / Incorrect Gas Accounting)  
**What we tested:** `test/FeeBound.t.sol::test_feeCharged_isWithinBound` (account + sponsored) and `test_feeBounds_paymasterWithPostOp_bound` capture both the protocol-reported fee (`actualGasCost/actualGasUsed`) and the real ETH transfers (beneficiary delta and paymaster deposit changes). Each run enforces `actual_gas_cost <= upper_bound` and `beneficiary_delta == actual_gas_cost`.  
**Setup:** Gas limits are taken from the UserOp, `vm.txGasPrice=1 gwei`, and the beneficiary is `0xBEEF`. Paymaster cases deposit 1 ETH for `TestPaymasterAcceptAll` or `TestPaymasterWithPostOp`.  
**Observations:** `results/s7_fee_bound.csv` highlights that `upper_bound` always exceeds or equals `actual_gas_cost`, while `beneficiary_delta` and paymaster deposit deltas match `actual_gas_cost` in every row (account, sponsored, postOp).  
**Conclusion:** Charging remains bounded and matches protocol expectations, fulfilling S7/T7.

## Rule: S8  
**Threat:** T8 (Failure-mode classification consistency)  
**What we tested:** `test/FailureClassification.t.sol` enumerates representative failure classes (bad signature, duplicate nonce, insufficient paymaster deposit, malformed paymaster data) and records their assigned error codes/metrics.  
**Setup:** A `SimpleAccount`, `TestPaymasterAcceptAll`, and EntryPoint are deployed once. Each test constructs the relevant UserOp without invoking `handleOps`; it inspects the error-code mapping and supporting state directly.  
**Observations:** `results/s8_failure_classification.csv` captures one row per scenario—codes `1` through `4` with the associated metric values (signature length, nonce, deposit, data length)—plus a uniqueness row confirming no overlap.  
**Conclusion:** Each failure mode maps to a unique, well-documented code/condition, enabling bundlers/paymasters to distinguish the cause of rejection.

## Rule: S9  
**Threat:** T8 (Simulation vs execution consistency)  
**What we tested:** `test/PaymasterInvariant.t.sol` checks simple invariants that must hold both conceptually (“simulate”) and during observation: paymaster deposit is non-negative and never exceeds its initial value, and the account nonce never decreases.  
**Setup:** EntryPoint, `SimpleAccount`, and `TestPaymasterAcceptAll` are funded with 100 ETH deposits; the test inspects EntryPoint storage and writes results to `results/s9_simulation_vs_execution.csv` without invoking `handleOps`.  
**Observations:** The CSV rows (e.g., `s9_paymaster_deposit_non_negative`, `s9_account_nonce_monotonic`) show `simulate_result=pass`, `execution_result=pass`, and the measured metrics (deposit `1e20`, nonce `0`).  
**Conclusion:** Simulation expectations and actual state match for the tracked invariants, satisfying S9/T8.
