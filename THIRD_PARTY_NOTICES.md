# Third-Party Notices

Project-original work is licensed under Apache-2.0. The distribution also includes the following separately licensed components:

## Mihomo v1.19.32

- Source: https://github.com/MetaCubeX/mihomo
- Source commit: `88dcbf7f1614a67c3b36b848ee3592dfa92ada36`
- License: GPL-3.0-only
- Upstream license SHA-256: `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986`
- Runtime payload SHA-256: `c80df2ca5159567804da883401e0118908fc1155e05df2baf3dbd4d3ecfc3754`
- Complete corresponding source: `mihomo-v1.19.32-complete-source.tar.gz`
- Complete corresponding source SHA-256: `0a993f5a3ba732879a1bc51f38aec05f54918ddf08649e706cf0ab40f1cce17f`
- Dependency source workflow: `go mod download -json all`, `go mod verify`, then `go mod vendor`
- Pinned Go source-preparation archive (darwin/amd64): `go1.26.8.darwin-amd64.tar.gz`, SHA-256 `186be014105aa6542b767d2c6ed5cca10a0214bdff809ef1724022a8c7894150`
- Pinned Go source-preparation archive (darwin/arm64): `go1.26.8.darwin-arm64.tar.gz`, SHA-256 `a012b25b571bd0138a03dcd25375ceba866fe5ca822f426d2c66a4de56fd3f4b`
- Pinned Go source-preparation archive (linux/amd64): `go1.26.8.linux-amd64.tar.gz`, SHA-256 `d0f743b33e8d8945e6b1f432edd15785c70507121d6e2a723b21285eddf8b57b`
- Pinned Go source-preparation archive (linux/arm64): `go1.26.8.linux-arm64.tar.gz`, SHA-256 `211ffced9dcb9633a55eac6364816ec0ddd951389a740e88fa8b3337971bdda0`
- Pinned Go source-preparation archive (windows/amd64): `go1.26.8.windows-amd64.zip`, SHA-256 `b92c3b2adae85a11ba71fe7216daf0d84e82af4c8ab6c5625807f28622043a59`
- Pinned Go source-preparation archive (windows/arm64): `go1.26.8.windows-arm64.zip`, SHA-256 `4bc560ed3ccb64eec0be6180b8c29185c07f5215276820adb4303d7bf3365435`
- Source-preparation selection: automatic host OS/architecture detection in production; explicit platform selection is fixture-only
- Module services: `https://proxy.golang.org` and `sum.golang.org`, without automatic direct fallback

## ShellCrash 1.9.4

- Source: https://github.com/juewuy/ShellCrash
- Source commit: `0b7f7161b0e71d9930c43190f46325bfa4aa426e`
- License: GPL-3.0-only
- Upstream license SHA-256: `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986`
- Runtime payload SHA-256: `4f946031a0483ed528e266143d459075489cce6c3f8f2f4681f39ca6d7448681`
- Complete corresponding source: `shellcrash-1.9.4-complete-source.tar.gz`
- Complete corresponding source SHA-256: `888cbb368fbc8e80805e9ff128499be48b9a6025b9f3f96ca72fb9acee7e005a`
- Runtime/source evidence: the tagged source tree's `ShellCrash.tar.gz` is byte-identical to the runtime payload above
- Source scope: the full tagged source tree, including upstream build and install scripts

Mihomo and ShellCrash remain subject to their respective GPL-3.0-only licenses. The Apache-2.0 license for project-original work does not relicense either component. The release includes the matching upstream license, verified runtime payload, and complete corresponding source archive identified above. See the release SBOM for machine-readable package details.
