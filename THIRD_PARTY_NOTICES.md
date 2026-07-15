# Third-Party Notices

Project-original work is licensed under Apache-2.0. The distribution also includes the following separately licensed components:

## Mihomo v1.19.28

- Source: https://github.com/MetaCubeX/mihomo
- Source commit: `cbd11db1e13a75d8e680e0fe7742c95be4cba2be`
- License: GPL-3.0-only
- Upstream license SHA-256: `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986`
- Runtime payload SHA-256: `6c08572c7115549ea51cb0f94b0d9ff08073a901bf2347d908c7209c4621e96a`
- Complete corresponding source: `mihomo-v1.19.28-complete-source.tar.gz`
- Complete corresponding source SHA-256: `db87b6d230cc7f850aca82bd63b0ed16bd6512253e6b9edd7eaa80c96a85fd6b`
- Dependency source workflow: `go mod download -json all`, `go mod verify`, then `go mod vendor`
- Pinned Go source-preparation archive (windows/amd64): `go1.26.5.windows-amd64.zip`, SHA-256 `97e6b2a833b6d89f9ff17d25419ac0a7e3b482a044e9ab18cdef834bd834fd38`
- Pinned Go source-preparation archive (windows/arm64): `go1.26.5.windows-arm64.zip`, SHA-256 `f96ee46396d69f1e231c8d981ec6a70216238a646a1f2cd74aea0d0016bbc017`
- Pinned Go source-preparation archive (linux/amd64): `go1.26.5.linux-amd64.tar.gz`, SHA-256 `5c2c3b16caefa1d968a94c1daca04a7ca301a496d9b086e17ad77bb81393f053`
- Pinned Go source-preparation archive (linux/arm64): `go1.26.5.linux-arm64.tar.gz`, SHA-256 `fe4789e92b1f33358680864bbe8704289e7bb5fc207d80623c308935bd696d49`
- Pinned Go source-preparation archive (darwin/amd64): `go1.26.5.darwin-amd64.tar.gz`, SHA-256 `6231d8d3b8f5552ec6cbf6d685bdd5482e1e703214b120e89b3bf0d7bf1ef725`
- Pinned Go source-preparation archive (darwin/arm64): `go1.26.5.darwin-arm64.tar.gz`, SHA-256 `efb87ff28af9a188d0536ef5d42e63dd52ba8263cd7344a993cc48dd11dedb6a`
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
