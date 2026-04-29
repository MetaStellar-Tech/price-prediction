# AGENTS.md

## 项目定位
PricePrediction 是一个基于代币价格驱动的预测市场。其主要使用基于 Hyperliquid EVM 层的智能合约作为执行结算模块，并且将 Hyperliquid Core 层作为价格预言机输入来源。
这是一个 **纯 Hyperliquid EVM 智能合约协议仓库**，用于承载 PricePrediction 在 HyperEVM / HyperCore 场景下的协议层实现。

当前仓库默认边界：

- 只维护 Solidity / Foundry 相关内容
- 负责协议合约、接口、状态机、权限、升级与资金规则
- 不在本仓直接实现 Go 后端
- 不在本仓实现生产 watcher / risk engine / Go orchestration 服务
- 所有协议相关测试代码、集成 harness、主网 / 测试网 rehearsal 脚本、测试日志和解析报告必须放在本仓 `test/`、`integration/`、`docs/testing/` 或对应 runs 输出目录内

一句话：

**HyperEVM 是投注与结算真值层，HyperCore 是预言机价格来源层。**

---

## 硬约束

- 一次只推进一个工作项。
- 不允许先改资金语义再补文档。
- 不允许弱化：
  - 平台奖金池保护
  - 结算顺序
  - 权限边界
  - 状态机约束
- HyperCore HyperEVM可以通过 `CoreRead` 读取 HyperCore的状态。
- `CoreRead` 口径固定为：`L1Read(primary) + CoreReadAttestor(fallback)`。
- 涉及 Core 真值时，默认先走 `EVM L1Read`；仅在 `L1Read` 读不到或不可用时，才允许走 `CoreReadAttestor` 向 EVM 提交受控同步输入。
- 不允许把 Hardhat 作为主流程引入，除非用户明确要求。
- 默认使用 Foundry-first 工作流。
- 默认不把第三方 `TypeScript RPC harness` 混入协议主路径；所有 TypeScript 测试 harness 必须隔离在 `integration/*-harness/`。
- 真实 HyperEVM / HyperCore testnet 或 mainnet rehearsal 只允许使用本仓 `integration/hyperliquid-live-harness/`，不得在其他项目新增或维护协议测试入口。
- HyperEVM 协议写交易的 gas 默认由平台统一代付，但这不构成提交方强制约束。
- 协议交易提交者可以是平台、项目方或用户；合约只校验签名与权限边界，不强制必须走平台提交。
- 当前默认链假设是 Hyperliquid 的 `HyperEVM + HyperCore` 组合，`HyperEVM` 写交易 gas token 按 Hyperliquid 当前公开机制使用 `HYPE`。
- v1 `withdraw` 收款地址由用户在每次 `withdrawLock` intent 中输入，允许任意非零 EVM 地址（EOA 或合约地址）。

---

## 开工流程

写代码前按顺序做：

1. `pwd`
2. 阅读：
   - `AGENTS.md`
   - `README.md`
   - `docs/workflow/DEVELOPMENT_WORKFLOW.md`
3. 如改动涉及资金、结算或权限，再阅读：
   - `docs/security/CONTRACT_SECURITY_BASELINE.md`
4. 如改动涉及 Hyperliquid 集成边界，再阅读：
   - `docs/hyperliquid/INTEGRATION_CONSTRAINTS.md`
5. 查看当前仓库状态：
   - `git status --short --branch`
   - `git log --oneline -5`
6. 只选择一个工作项推进
7. 如任务较长，先按 `docs/workflow/WORK_ITEM_TEMPLATE.md` 写一页短说明

---

## 实施顺序

默认顺序：

1. 先冻结文档口径
   - 状态机
   - 角色
   - 关键字段
   - 默认参数
2. 先定义 shared errors / events / enums / interfaces
3. 再写合约骨架和最小权限控制
4. 再写资金账本、债务字段、利息与结算逻辑
5. 最后再接 Hyperliquid 边界
6. 最后补测试和安全检查

完成前再过一遍：

- `docs/workflow/DELIVERY_CHECKLIST.md`
- `docs/workflow/REVIEW_RUBRIC.md`

---

## 验证路径

基础验证：

- `forge fmt --check`
- `forge build`
- `forge test -vvv`

增强验证：

- `forge coverage`

如果改动涉及：

- 权限控制
- 借款
- 还款
- 提现
- 结算
- 升级代理
- 资产转移

则至少补对应单测；能补 invariant / fuzz 时优先补。

如果本机装有额外工具，再追加：

- `slither`
- Echidna

---

## 文档同步规则

以下改动必须同步文档：

- 新状态
- 新字段
- 新角色
- 新默认参数
- 新 upgrade 假设
- 新 Hyperliquid 交互假设
- 新安全约束
- 新接入模式

如果本轮改动涉及下面任一项，还必须同步：

- `src/`
- `test/`
- `script/`
- `foundry.toml`
- 合约实现边界
- 当前已完成 / 未完成的实施状态

强制规则：

- 每次完成实际开发后，必须更新 `docs/implementation/IMPLEMENTATION_STATUS.md`
- 要把本轮已经真实落地且已验证通过的内容标记为 `[x]`
- 要把不再准确的“未完成 / 下一步建议顺序 / 当前实现边界”一并改掉
- 纯分析、纯讨论、未落代码的内容，不得在 `IMPLEMENTATION_STATUS.md` 中标记为已完成

---

## 收尾

结束前至少完成：

1. 相关验证已运行
2. 文档已同步
3. `docs/implementation/IMPLEMENTATION_STATUS.md` 已同步到当前真实实现状态（如果本轮有实际开发）
4. 已过一遍 `docs/workflow/DELIVERY_CHECKLIST.md`
5. `README.md` 中的仓库定位没有被改回模板描述
6. 如本轮建立了新的约束或开发规则，补到 `AGENTS.md` 或 `docs/` 下对应文档

---

## 仓库事实

- 本仓是 **纯合约协议仓库**
- Foundry 是主工具链
- 生产 Go 服务不在本仓
- 协议测试 harness 在本仓
- TypeScript harness 只允许放在 `integration/*-harness/`
- 当前正式隔离目录：
  - `integration/hyperliquid-live-harness/`：真实 HyperEVM / HyperCore testnet 与 mainnet preflight、最小资金 rehearsal、日志和报告生成
