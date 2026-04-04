# 云端验证报告（给本地 Windows 使用）

生成时间（UTC）：2026-04-04
仓库路径：`/workspace/openclaw-vm`

## 本次在云端完成的验证（Windows 本地不方便做的部分）

我在 Linux 云端实际执行了以下脚本，用于验证当前仓库在类 Linux 环境下的可运行性与依赖状态：

1. `bash ./scripts/ensure-host.sh`
2. `bash ./scripts/check-assets.sh`

> 说明：这两步能快速确认“是否具备 VM 模式运行条件”以及“Ubuntu 基础镜像资产是否齐全且可校验”。

---

## 验证结果摘要

### 1) 主机与依赖检查（ensure-host.sh）

结论：当前云端环境是 **sandbox_only**（只能走 sandbox，不能走 VM）。

关键结果：
- `host_os`: `linux`
- `running_inside_vm`: `true`
- `sandbox_available`: `true`
- `vm_available`: `false`
- 缺少：`qemu_system`、`qemu_img`、`ubuntu_base_asset`

含义：
- 说明脚本逻辑正常运行并可返回结构化状态。
- 如果你希望在本地/云端启用 VM 模式，需要安装 QEMU 并准备 Ubuntu 资产。

---

### 2) 资产检查（check-assets.sh）

结论：状态为 **needs_attention**（资产未就绪）。

关键结果：
- 资产根目录：`/workspace/openclaw-vm/ubuntu`
- 缺少必需：
  - `ubuntu-24.04-server-cloudimg-amd64.img`
  - `ubuntu/SHA256SUMS`
- 建议补齐（可选但推荐）：
  - `ubuntu-24.04.4-live-server-amd64.iso`
  - `ubuntu/ubuntu-release-SHA256SUMS`
- 另外缺少 GPG 签名文件（`*.gpg`），会影响“签名验证”，但不影响基础哈希校验流程。

含义：
- 校验脚本逻辑可用，且能正确识别缺失资产并给出引导。

---

## 你在本地 Windows 建议照做的步骤

在 PowerShell 中按顺序执行：

```powershell
.\scripts\check-assets.ps1
.\scripts\ensure-host.ps1
.\scripts\bootstrap-base-image.ps1
```

然后根据输出重点确认：

1. `vm_available` 是否为 `true`
2. `missing_required` 是否为空
3. `status` 是否从 `sandbox_only` 变成可用 VM 的状态

如果缺文件，按仓库文档 `references/download-assets.md` 下载到 `ubuntu/` 目录。

---

## 本地结果回传格式（建议）

请把你本地 PowerShell 的 JSON 输出粘贴回来，至少包含：

- `status`
- `vm_available`
- `missing_required`
- `asset_root`

我可以据此继续帮你判断是否已经达到可启动 VM 的条件，以及下一步怎么修。
