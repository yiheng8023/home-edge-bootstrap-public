# 公开发布契约

英文文件为规范真源；本文件是简体中文阅读映射。

## 目的

公开发布将项目源码包与完整离线恢复包分开。两种归档格式都从同一个干净的公开 Git
提交生成，并由同一离线契约验证。运行时载荷、GPL 许可证副本和完整对应源码不会进入
公开 Git 历史；它们只出现在已验证的离线发布包及独立的对应源码资产中。

发布验证只证明归档完整性和已声明的本地契约，不保证服务商可用性，也不保证敏感操作、
账号、支付、注册、金融或地区验证结果。路线可达、低延迟、国家标签或自动选中的节点，
都不能作为出口身份稳定的证据。

## 精确发布表面

每个版本化发布恰好包含九个契约文件。`v0.1.2` 对应：

- `home-edge-bootstrap-v0.1.2-source.zip`
- `home-edge-bootstrap-v0.1.2-source.tar.gz`
- `home-edge-bootstrap-v0.1.2-offline.zip`
- `home-edge-bootstrap-v0.1.2-offline.tar.gz`
- `mihomo-v1.19.28-source-complete.tar.gz`
- `shellcrash-1.9.4-source-complete.tar.gz`
- `SBOM.spdx.json`
- `RELEASE-MANIFEST.json`
- `SHA256SUMS`

`SHA256SUMS` 覆盖其余八个分发文件；它无法为自身记录摘要。
`RELEASE-MANIFEST.json` 记录公开提交、确定性构建时间、支持限制、组件锁、资产大小和
摘要。`SBOM.spdx.json` 是发布专用 SBOM，与 `config/sbom.json` 中的源码 checkout
SBOM 分离。

发布者应保留契约文件名，并采用 `docs/zh-CN/RELEASE_NOTES.md` 中的精确人类可读资源标签。
发布前，每个上传资源的标签都必须非空。

普通用户不需要下载全部九个文件，最小下载组合是一个归档加 `SHA256SUMS`。只有在运行时
已存在、仅需脚本或文档时，才选择相应格式的源码包。manifest、SBOM 与独立完整源码归档
用于审计和保障源码可获得性，不是额外安装部件。GitHub 自动生成的 **Source code** 归档
不属于上述精确发布表面，也不能替代契约内归档。`docs/zh-CN/RELEASE_NOTES.md` 中的版本
专用已知限制优先于资源的一般预期角色。

## 源码包与离线包分离

源码归档只包含由 `config/public-release-files.txt` 选择的已提交路径，以及 `VERSION`、
`PUBLIC-COMMIT` 和 `CONTENT-SHA256SUMS`。它排除运行时载荷、完整对应源码归档、从 GPL
组件复制的许可证、Git 历史、发布输出、缓存、日志、本地策略和凭据。

离线归档从相同的已验证项目源码开始，并另外包含：

- `bundle/mihomo-linux-arm64`、`bundle/ShellCrash.tar.gz`、manifest 和摘要；
- `third-party/licenses/` 下的 GPL-3.0-only 许可证副本；
- `third-party/sources/` 下的完整对应源码。

ZIP 和 tar 必须只有一个安全包根目录，不得包含路径穿越或链接条目；两种格式的文件列表
和字节必须一致，并且必须具有完整有效的 `CONTENT-SHA256SUMS`。

## 构建与验证

先使用 `scripts/prepare-public-sources.ps1` 或 `.sh`，在 Git checkout 外准备已验证的
第三方材料。然后构建到一个尚不存在的输出目录：

```powershell
.\scripts\build-public-release.ps1 `
  -Repo (Get-Location) `
  -Version v0.1.2 `
  -PreparedDir C:\path\to\verified-prepared-material `
  -Output C:\path\to\dist
```

```sh
sh scripts/build-public-release.sh \
  --repo . \
  --version v0.1.2 \
  --prepared-dir /path/to/verified-prepared-material \
  --output /path/to/dist
```

验证过程不接触路由器或网络：

```powershell
.\scripts\verify-public-release.ps1 -Repo (Get-Location) -Version v0.1.2 -Dist C:\path\to\dist
```

```sh
sh scripts/verify-public-release.sh --repo . --version v0.1.2 --dist /path/to/dist
```

稳定成功标记为 `public_release_state=ready`。构建失败不会留下部分输出。构建和验证都不会
创建 Git 标签、发布 GitHub Release、改变仓库可见性或接触路由器。

创建或编辑 GitHub Release 前，应针对目标仓库和版本，使用
`scripts/render-release-body.py` 渲染 `docs/RELEASE_NOTES.md`。该步骤会把仓库链接转换为
固定到 tag 的 URL；若直接把文档文件作为 Release 正文，相对链接可能从错误目录解析。

生成器的 `--source-ref` 选择包含 Release 正文的已审阅提交/tag，`--version` 选择用于校验
仓库链接的发布 tag。正常新版本中两者应是同一个新 tag。勘误现有正文时必须显式指定后续
已审阅 `--source-ref`，且不得暗示旧资源包含后续修复。

## v0.1.2 验收合同

v0.1.2 发布必须同时满足：

- 创建新 tag 和新的版本化资源；不得替换 v0.1.1 资源，也不得暗示其资源已包含后续宿主
  验证修复。
- 保留九类契约资源，验证 `SHA256SUMS`、发布 manifest、SPDX SBOM、许可证与完整对应源码，
  并为每个上传资源应用精确的非空标签。
- 从已审阅 v0.1.2 tag 生成 Release 正文，并验证所有固定到 tag 的链接。
- 使用精确 tag checkout 分别通过 Linux、macOS 与 Windows 宿主路径；路由器运行正常或单一
  宿主路径通过，不能替代另外两个宿主任务。
- 记录受支持真实官方 Asuswrt-Merlin 环境中运行内核、启动存续、controller/UI、透明与
  显式代理路径、客户端检查和安装收官证据。
- 针对精确 tag 实现验证辅助命令回退、持久 JFFS 外的临时运行时 staging、安装中断清理和
  回滚。破坏性失败分支可采用确定性离线故障注入，而不是故意中断正在使用的真实网络，但
  必须披露证据类型。
- 记录精确源码提交、现场证据与离线验证边界；仅有主机 CI 或 fixture 不能替代上述真实
  运行时证据。

发布说明记录最终证据及其限制；本合同不额外认证硬件、服务商、路线、账号或地区结果。

## 敏感出口限制

日常自愈优化的是可用性和受限恢复，不是敏感出口保障机制。在独立的连续性能力完成验证
之前，操作者不能把路线健康解释为有效叶子、ASN 类别、信誉、DNS 路径、账号风险状态或
平台接受度稳定的证明。公开发布就绪也不会升级这一限制。
