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

你们仓库名就是 **CS6290_Group9**。新电脑拉取你们仓库后，按下面做即可（写进 README 也用这段）。

------

## Getting Started (Windows+ Git Bash)

### 1) Clone（务必带 submodule）

在任意目录打开 Git Bash：

```bash
git clone --recurse-submodules https://github.com/AdaHyun/CS6290_Group9.git
cd CS6290_Group9
```

如果他已经 clone 了但没带 submodule，在仓库根目录补：

```bash
git submodule update --init --recursive
```

------

### 2) 安装 Foundry

```bash
curl -L https://foundry.paradigm.xyz | bash
```

**关闭 Git Bash 窗口并重新打开**（让 PATH 生效）

或者不关闭，执行以下命令，重新加载配置：

```
source ~/.bashrc
```

然后：

```bash
foundryup
```

验证：

```bash
forge --version
anvil --version
```

------

### 3) 跑测试

在仓库根目录（`CS6290_Group9`）执行：

```bash
forge test -vv
```

看到 `3 tests passed` 就表示环境 OK。

------

## Common error

### A) `foundryup` 下载中断（curl 18）

```bash
export FOUNDRYUP_CURL_ARGS="--retry 10 --retry-delay 2 --retry-all-errors -L -C -"
foundryup
```

### B) 编译提示找不到 `account-abstraction` / `openzeppelin`

说明 submodule 没拉全：

```bash
git submodule update --init --recursive
forge test -vv
```

------

