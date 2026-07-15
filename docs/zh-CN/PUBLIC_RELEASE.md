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

`v0.1.0` 发布恰好包含以下九个文件：

- `home-edge-bootstrap-v0.1.0-source.zip`
- `home-edge-bootstrap-v0.1.0-source.tar.gz`
- `home-edge-bootstrap-v0.1.0-offline.zip`
- `home-edge-bootstrap-v0.1.0-offline.tar.gz`
- `mihomo-v1.19.28-source-complete.tar.gz`
- `shellcrash-1.9.4-source-complete.tar.gz`
- `SBOM.spdx.json`
- `RELEASE-MANIFEST.json`
- `SHA256SUMS`

`SHA256SUMS` 覆盖其余八个分发文件；它无法为自身记录摘要。
`RELEASE-MANIFEST.json` 记录公开提交、确定性构建时间、支持限制、组件锁、资产大小和
摘要。`SBOM.spdx.json` 是发布专用 SBOM，与 `config/sbom.json` 中的源码 checkout
SBOM 分离。

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
  -Version v0.1.0 `
  -PreparedDir C:\path\to\verified-prepared-material `
  -Output C:\path\to\dist
```

```sh
sh scripts/build-public-release.sh \
  --repo . \
  --version v0.1.0 \
  --prepared-dir /path/to/verified-prepared-material \
  --output /path/to/dist
```

验证过程不接触路由器或网络：

```powershell
.\scripts\verify-public-release.ps1 -Repo (Get-Location) -Version v0.1.0 -Dist C:\path\to\dist
```

```sh
sh scripts/verify-public-release.sh --repo . --version v0.1.0 --dist /path/to/dist
```

稳定成功标记为 `public_release_state=ready`。构建失败不会留下部分输出。构建和验证都不会
创建 Git 标签、发布 GitHub Release、改变仓库可见性或接触路由器。

## 敏感出口限制

日常自愈优化的是可用性和受限恢复，不是敏感出口保障机制。在独立的连续性能力完成验证
之前，操作者不能把路线健康解释为有效叶子、ASN 类别、信誉、DNS 路径、账号风险状态或
平台接受度稳定的证明。公开发布就绪也不会升级这一限制。
