# Threat to Spec Traceability

| Threat | Spec Rule | Test Case | Evidence Artifact |
| --- | --- | --- | --- |
| T1 | S1 | `test/PaymasterAuth.t.sol::test_validatePaymasterUserOp_onlyEntryPoint_canCall` / `test_postOp_onlyEntryPoint_canCall` | `results/s1_paymaster_access.csv` |
| T2 | S2 | `test/NonceReplay.t.sol::test_replayNonce_shouldFail` | `results/s2_nonce_replay.csv` |
| T3 | S3 | `test/BadSignature.t.sol::test_invalidSignature_shouldFail` | `results/s3_bad_signature.csv` |
| T4 | S4 | `test/PaymasterInsufficientDepositTest.t.sol::test_S4_PaymasterInsufficientDepositMustFail` | `results/s4_paymaster_deposit.csv` |
| T5 | S5 | `test/PaymasterMalformedDataTest.t.sol::test_S5_MalformedPaymasterAndDataMustFail` | `results/s5_paymaster_malformed.csv` |
| T6 | S6 | `test/BatchIsolation.t.sol::test_batchIsolation_keeps_successful_ops_running` | `results/s6_batch_outcome.csv` |
| T6 | S6 | `test/BatchIsolation.t.sol::test_batchIsolation_invalidSignature_revertsEntireBatch` | `results/s6_batch_outcome.csv` |
| T6 | S6 | `test/BatchIsolation.t.sol::test_batchIsolation_paymasterDepositTooLow_revertsBatch` | `results/s6_batch_outcome.csv` |
| T7 | S7 | `test/FeeBound.t.sol::test_feeCharged_isWithinBound` | `results/s7_fee_bound.csv` |
| T7 | S7 | `test/FeeBound.t.sol::test_feeBounds_paymasterWithPostOp_bound` | `results/s7_fee_bound.csv` |
| T8 | S8 | `test/FailureClassification.t.sol::*` | `results/s8_failure_classification.csv` |
| T8 | S9 | `test/PaymasterInvariant.t.sol::*` | `results/s9_simulation_vs_execution.csv` |
