## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

The repository name is **CS6290_Group9**. After cloning the repository on a new computer, follow the steps below.

------


## Getting Started (Windows + Git Bash)

### 1) Clone (with submodule)

Open Git Bash in any directory:

```bash
git clone --recurse-submodules https://github.com/AdaHyun/CS6290_Group9.git
cd CS6290_Group9
```

If you already cloned but didn’t include the submodule, run this in the repository root:

```bash
git submodule update --init --recursive
```

---

### 2) Install Foundry

```bash
curl -L https://foundry.paradigm.xyz | bash
```

**Close Git Bash and reopen** (to apply PATH changes)

Or, if you don’t want to close, run the following command to reload the configuration:

```
source ~/.bashrc
```

Then:

```bash
foundryup
```

Verify:

```bash
forge --version
anvil --version
```

---

### 3) Run tests

In the repository root (`CS6290_Group9`) run:

```bash
forge test -vv
```

If you see `3 tests passed`, the environment is ready.

---

## Common errors

### A) `foundryup` download interrupted (curl 18)

```bash
export FOUNDRYUP_CURL_ARGS="--retry 10 --retry-delay 2 --retry-all-errors -L -C -"
foundryup
```

### B) Compilation cannot find `account-abstraction` / `openzeppelin`

This indicates that the submodules were not fully fetched:

```bash
git submodule update --init --recursive
forge test -vv
```

---
