# Experiment Protocol

1. **Verify Foundry toolchain**
   ```sh
   forge --version
   ```
   This repository was validated with Foundry 0.2.x (Solc 0.8.33). Ensure your `$PATH` points to the same toolchain (on Windows this may be `C:\Users\<user>\.foundry\bin\forge.exe`).

2. **Run the full S1–S9 test suites with verbose logs**
   ```sh
   forge test -vv
   ```
   This command deploys a local `EntryPoint`, builds signed `PackedUserOperation`s, and executes the new `BatchIsolation` and `FeeBound` tests along with existing suites. No public networks or testnets are required; everything runs against the local anvil-style EVM that Foundry spins up for each test.

3. **Evidence generation**
   - The tests themselves emit the structured logs required for the evidence pack.
   - Running `forge test -vv` creates/updates:
     - `results/s1_paymaster_access.csv`
     - `results/s2_nonce_replay.csv`
     - `results/s3_bad_signature.csv`
     - `results/s4_paymaster_deposit.csv`
     - `results/s5_paymaster_malformed.csv`
     - `results/s6_batch_outcome.csv`
     - `results/s7_fee_bound.csv` (includes `upper_bound`, `actual_gas_cost`, `beneficiary_delta`, and paymaster deposit balances)
     - `results/s8_failure_classification.csv`
     - `results/s9_simulation_vs_execution.csv`
   These CSV files capture the quantitative observations referenced in `docs/evidence/RESULTS.md`.

4. **Reproduce documentation context (optional)**
   - Inspect `docs/evidence/RESULTS.md` and `docs/evidence/THREAT_SPEC_TRACEABILITY.md` for narrative summaries.
   - All experiments were executed locally without any reliance on external RPC endpoints or networks.
