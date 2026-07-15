#!/usr/bin/env python3
"""Offline cross-platform fixtures for the public release contract."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile


VERSION = "v0.1.0"
MIHOMO_SOURCE = "mihomo-v1.19.28-source-complete.tar.gz"
SHELLCRASH_SOURCE = "shellcrash-1.9.4-source-complete.tar.gz"
MIHOMO_PREPARED_SOURCE = "mihomo-v1.19.28-complete-source.tar.gz"
SHELLCRASH_PREPARED_SOURCE = "shellcrash-1.9.4-complete-source.tar.gz"


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path: pathlib.Path, data: str | bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(data, bytes):
        path.write_bytes(data)
    else:
        path.write_text(data, encoding="utf-8", newline="\n")


def run(command: list[object], *, ok: bool = True, contains: str | None = None) -> str:
    result = subprocess.run(
        [str(value) for value in command],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if ok and result.returncode != 0:
        raise SystemExit(f"command failed ({result.returncode}): {' '.join(map(str, command))}\n{result.stdout}")
    if not ok and result.returncode == 0:
        raise SystemExit(f"expected rejection: {' '.join(map(str, command))}\n{result.stdout}")
    if contains and contains.lower() not in result.stdout.lower():
        raise SystemExit(
            f"expected output containing {contains!r}: {' '.join(map(str, command))}\n{result.stdout}"
        )
    return result.stdout


def git(repo: pathlib.Path, *arguments: str) -> str:
    return run(["git", "-C", repo, *arguments]).strip()


def deterministic_tar(path: pathlib.Path, root: str, files: dict[str, bytes]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=1, compresslevel=9) as zipped:
            with tarfile.open(fileobj=zipped, mode="w", format=tarfile.PAX_FORMAT) as archive:
                directory = tarfile.TarInfo(root)
                directory.type = tarfile.DIRTYPE
                directory.mode = 0o755
                directory.mtime = 1
                archive.addfile(directory)
                for relative, content in sorted(files.items()):
                    item = tarfile.TarInfo(f"{root}/{relative}")
                    item.size = len(content)
                    item.mode = 0o644
                    item.mtime = 1
                    archive.addfile(item, io.BytesIO(content))


def create_fixture(root: pathlib.Path, source: pathlib.Path, name: str) -> tuple[pathlib.Path, pathlib.Path]:
    fixture = root / name
    repo = fixture / "repo"
    prepared = fixture / "prepared"
    repo.mkdir(parents=True)
    for script in (
        "build-public-release.ps1",
        "build-public-release.sh",
        "public-release.py",
        "verify-public-release.ps1",
        "verify-public-release.sh",
    ):
        candidate = source / "scripts" / script
        if not candidate.is_file():
            raise SystemExit(f"missing public release implementation: {candidate}")
        target = repo / "scripts" / script
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(candidate, target)
    write(repo / "README.md", "# Fixture public repository\n")
    write(repo / "LICENSE", "Apache License\nVersion 2.0, January 2004\n")
    write(repo / "NOTICE", "Fixture public project\n")
    write(repo / "docs/PUBLIC_RELEASE.md", "# Public release\n")
    write(repo / "docs/zh-CN/PUBLIC_RELEASE.md", "# 公开发布\n")
    write(
        repo / "config/public-release-files.txt",
        "\n".join(
            (
                "LICENSE",
                "NOTICE",
                "README.md",
                "config/public-release-files.txt",
                "config/sbom.json",
                "config/third-party-lock.json",
                "docs/PUBLIC_RELEASE.md",
                "docs/zh-CN/PUBLIC_RELEASE.md",
                "scripts/build-public-release.ps1",
                "scripts/build-public-release.sh",
                "scripts/public-release.py",
                "scripts/verify-public-release.ps1",
                "scripts/verify-public-release.sh",
            )
        )
        + "\n",
    )
    write(prepared / "third-party/mihomo/mihomo-linux-arm64", b"fixture mihomo payload\n")
    write(prepared / "third-party/shellcrash/ShellCrash.tar.gz", b"fixture shellcrash payload\n")
    license_bytes = b"fixture GPL-3.0-only license\n"
    write(prepared / "third-party/mihomo/LICENSE", license_bytes)
    # Match the canonical output contract of both source preparers and the
    # third-party compliance verifiers. ShellCrash ships this file as
    # LICENSE.txt; accepting a fixture-only LICENSE path masks integration
    # failures in the real release workflow.
    write(prepared / "third-party/shellcrash/LICENSE.txt", license_bytes)
    deterministic_tar(
        prepared / f"third-party/sources/{MIHOMO_PREPARED_SOURCE}",
        "mihomo-v1.19.28-source",
        {"LICENSE": license_bytes, "main.go": b"package main\n"},
    )
    deterministic_tar(
        prepared / f"third-party/sources/{SHELLCRASH_PREPARED_SOURCE}",
        "shellcrash-1.9.4-source",
        {"LICENSE": license_bytes, "install.sh": b"#!/bin/sh\nexit 0\n"},
    )
    lock = {
        "schema_version": 1,
        "components": [
            {
                "id": "mihomo-linux-arm64",
                "version": "v1.19.28",
                "source_repository": "https://example.invalid/mihomo",
                "source_commit": "1" * 40,
                "license": "GPL-3.0-only",
                "payload_sha256": sha256(prepared / "third-party/mihomo/mihomo-linux-arm64"),
                "license_sha256": hashlib.sha256(license_bytes).hexdigest(),
                "complete_source_sha256": sha256(prepared / f"third-party/sources/{MIHOMO_PREPARED_SOURCE}"),
            },
            {
                "id": "shellcrash",
                "version": "1.9.4",
                "source_repository": "https://example.invalid/shellcrash",
                "source_commit": "2" * 40,
                "license": "GPL-3.0-only",
                "payload_sha256": sha256(prepared / "third-party/shellcrash/ShellCrash.tar.gz"),
                "license_sha256": hashlib.sha256(license_bytes).hexdigest(),
                "complete_source_sha256": sha256(prepared / f"third-party/sources/{SHELLCRASH_PREPARED_SOURCE}"),
            },
        ],
    }
    write(repo / "config/third-party-lock.json", json.dumps(lock, indent=2) + "\n")
    sbom = {
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": "fixture-public-source",
        "documentNamespace": "https://example.invalid/spdx/fixture",
        "creationInfo": {"created": "2026-01-01T00:00:00Z", "creators": ["Tool: fixture"]},
        "packages": [
            {
                "name": "fixture-public-source",
                "SPDXID": "SPDXRef-Package-Source",
                "versionInfo": "0.1.0-source",
                "downloadLocation": "NOASSERTION",
                "filesAnalyzed": False,
                "licenseConcluded": "Apache-2.0",
                "licenseDeclared": "Apache-2.0",
                "copyrightText": "NOASSERTION",
            }
        ],
    }
    write(repo / "config/sbom.json", json.dumps(sbom, indent=2) + "\n")
    run(["git", "init", "-q", "-b", "main", repo])
    git(repo, "config", "user.email", "fixture@example.invalid")
    git(repo, "config", "user.name", "Public Release Fixture")
    git(repo, "add", ".")
    git(repo, "commit", "-q", "-m", "fixture public source")
    return repo, prepared


def commands(mode: str, source: pathlib.Path, repo: pathlib.Path, prepared: pathlib.Path, output: pathlib.Path):
    if mode == "powershell":
        host = shutil.which("powershell") or shutil.which("pwsh")
        if not host:
            raise SystemExit("PowerShell is required")
        build = [
            host,
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            repo / "scripts/build-public-release.ps1",
            "-Repo",
            repo,
            "-Version",
            VERSION,
            "-PreparedDir",
            prepared,
            "-Output",
            output,
            "-Commit",
            "HEAD",
            "-FixtureMode",
        ]
        verify = [
            host,
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            repo / "scripts/verify-public-release.ps1",
            "-Repo",
            repo,
            "-Dist",
            output,
            "-Version",
            VERSION,
            "-Commit",
            "HEAD",
        ]
    else:
        build = [
            "sh",
            repo / "scripts/build-public-release.sh",
            "--repo",
            repo,
            "--version",
            VERSION,
            "--prepared-dir",
            prepared,
            "--output",
            output,
            "--commit",
            "HEAD",
            "--fixture-mode",
        ]
        verify = [
            "sh",
            repo / "scripts/verify-public-release.sh",
            "--repo",
            repo,
            "--dist",
            output,
            "--version",
            VERSION,
            "--commit",
            "HEAD",
        ]
    return build, verify


def replace_argument(command: list[object], name: str, value: object) -> list[object]:
    result = list(command)
    position = result.index(name)
    result[position + 1] = value
    return result


def refresh_artifact_metadata(dist: pathlib.Path, filename: str) -> None:
    artifact = dist / filename
    digest = sha256(artifact)
    sbom_path = dist / "SBOM.spdx.json"
    sbom = json.loads(sbom_path.read_text(encoding="utf-8"))
    sbom_record = next((item for item in sbom.get("releaseArtifacts", []) if item.get("path") == filename), None)
    if sbom_record is not None:
        sbom_record["sha256"] = digest
        sbom_record["size"] = artifact.stat().st_size
        write(sbom_path, json.dumps(sbom, indent=2) + "\n")
    manifest_path = dist / "RELEASE-MANIFEST.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    record = next(item for item in manifest["artifacts"] if item["path"] == filename)
    record["sha256"] = digest
    record["size"] = artifact.stat().st_size
    sbom_record = next(item for item in manifest["artifacts"] if item["path"] == "SBOM.spdx.json")
    sbom_record["sha256"] = sha256(sbom_path)
    sbom_record["size"] = sbom_path.stat().st_size
    write(manifest_path, json.dumps(manifest, indent=2) + "\n")
    manifest_digest = sha256(manifest_path)
    lines = (dist / "SHA256SUMS").read_text(encoding="ascii").splitlines()
    replacements = {
        filename: digest,
        "SBOM.spdx.json": sha256(sbom_path),
        "RELEASE-MANIFEST.json": manifest_digest,
    }
    write(
        dist / "SHA256SUMS",
        "\n".join(
            f"{replacements[name]}  {name}"
            if (name := line[66:]) in replacements
            else line
            for line in lines
        )
        + "\n",
    )


def refresh_manifest_checksum(dist: pathlib.Path) -> None:
    manifest_digest = sha256(dist / "RELEASE-MANIFEST.json")
    lines = (dist / "SHA256SUMS").read_text(encoding="ascii").splitlines()
    write(
        dist / "SHA256SUMS",
        "\n".join(
            f"{manifest_digest}  RELEASE-MANIFEST.json"
            if line.endswith("  RELEASE-MANIFEST.json")
            else line
            for line in lines
        )
        + "\n",
    )


def refresh_content_manifest(package: pathlib.Path) -> None:
    entries = sorted(
        item
        for item in package.rglob("*")
        if item.is_file() and item.name != "CONTENT-SHA256SUMS"
    )
    lines = [f"{sha256(item)}  {item.relative_to(package).as_posix()}" for item in entries]
    write(package / "CONTENT-SHA256SUMS", "\n".join(lines) + "\n")


def repack_zip(path: pathlib.Path, mutate) -> None:
    with tempfile.TemporaryDirectory(prefix="public-release-zip-") as temporary:
        root = pathlib.Path(temporary)
        with zipfile.ZipFile(path) as archive:
            archive.extractall(root)
        mutate(root)
        with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for item in sorted(candidate for candidate in root.rglob("*") if candidate.is_file()):
                archive.write(item, item.relative_to(root).as_posix())


def repack_tar(path: pathlib.Path, mutate) -> None:
    with tempfile.TemporaryDirectory(prefix="public-release-tar-") as temporary:
        root = pathlib.Path(temporary)
        with tarfile.open(path, "r:gz") as archive:
            archive.extractall(root, filter="data")
        mutate(root)
        package_root = next(root.iterdir())
        with tarfile.open(path, "w:gz") as archive:
            archive.add(package_root, arcname=package_root.name)


def exercise(mode: str, source: pathlib.Path, root: pathlib.Path) -> None:
    repo, prepared = create_fixture(root, source, "base")
    output = root / "base-dist"
    build, verify = commands(mode, source, repo, prepared, output)

    run(replace_argument(build, "-Version" if mode == "powershell" else "--version", "0.1"), ok=False, contains="invalid")

    write(repo / "README.md", "dirty\n")
    run(build, ok=False, contains="dirty")
    git(repo, "restore", "README.md")

    write(repo / ".env", "TOKEN=fixture\n")
    run(build, ok=False, contains="sensitive")
    (repo / ".env").unlink()

    run(replace_argument(build, "-Commit" if mode == "powershell" else "--commit", "missing-commit"), ok=False, contains="commit")

    unsafe_reference = "C:" + "\\Projects\\home-edge-bootstrap\\internal\n"
    write(repo / "README.md", unsafe_reference)
    git(repo, "add", "README.md")
    git(repo, "commit", "-q", "-m", "unsafe reference")
    run(build, ok=False, contains="reference")
    git(repo, "reset", "--hard", "HEAD~1")

    missing_source = prepared / f"third-party/sources/{MIHOMO_PREPARED_SOURCE}"
    saved = missing_source.read_bytes()
    missing_source.unlink()
    run(build, ok=False, contains="source")
    write(missing_source, saved)

    license_path = prepared / "third-party/mihomo/LICENSE"
    license_saved = license_path.read_bytes()
    write(license_path, b"wrong license\n")
    run(build, ok=False, contains="license")
    write(license_path, license_saved)

    payload_path = prepared / "third-party/mihomo/mihomo-linux-arm64"
    payload_saved = payload_path.read_bytes()
    write(payload_path, b"wrong payload\n")
    run(build, ok=False, contains="checksum")
    write(payload_path, payload_saved)

    for case_name, mutation, expected in (
        ("duplicate-allowlist", lambda lines: lines + ["README.md"], "duplicate"),
        ("missing-allowlist", lambda lines: lines + ["missing-required-root"], "match"),
        ("overlap-allowlist", lambda lines: lines + ["scripts"], "overlap"),
    ):
        case_repo, case_prepared = create_fixture(root, source, case_name)
        allowlist = case_repo / "config/public-release-files.txt"
        lines = allowlist.read_text(encoding="utf-8").splitlines()
        write(allowlist, "\n".join(mutation(lines)) + "\n")
        git(case_repo, "add", "config/public-release-files.txt")
        git(case_repo, "commit", "-q", "-m", case_name)
        case_build, _ = commands(mode, source, case_repo, case_prepared, root / f"{case_name}-dist")
        run(case_build, ok=False, contains=expected)

    build_output = run(build)
    if "public_release_state=ready" not in build_output:
        raise SystemExit("public release ready marker missing")
    verify_output = run(verify)
    if "public_release_state=ready" not in verify_output:
        raise SystemExit("public release verification marker missing")

    wrong_checksums = root / "wrong-checksums"
    shutil.copytree(output, wrong_checksums)
    sums = wrong_checksums / "SHA256SUMS"
    write(sums, sums.read_text(encoding="ascii").replace(sums.read_text(encoding="ascii")[:64], "0" * 64, 1))
    run(replace_argument(verify, "-Dist" if mode == "powershell" else "--dist", wrong_checksums), ok=False, contains="checksum")

    mixed = root / "mixed-source"
    shutil.copytree(output, mixed)
    source_zip = mixed / f"home-edge-bootstrap-{VERSION}-source.zip"
    def add_runtime(root_path: pathlib.Path) -> None:
        package = next(root_path.iterdir())
        write(package / "bundle/mihomo-linux-arm64", b"runtime in source package\n")
    repack_zip(source_zip, add_runtime)
    refresh_artifact_metadata(mixed, source_zip.name)
    run(replace_argument(verify, "-Dist" if mode == "powershell" else "--dist", mixed), ok=False, contains="source archive")

    unsafe = root / "unsafe-archive"
    shutil.copytree(output, unsafe)
    unsafe_zip = unsafe / f"home-edge-bootstrap-{VERSION}-source.zip"
    with zipfile.ZipFile(unsafe_zip, "w") as archive:
        archive.writestr("../escape.txt", "escape\n")
    refresh_artifact_metadata(unsafe, unsafe_zip.name)
    run(replace_argument(verify, "-Dist" if mode == "powershell" else "--dist", unsafe), ok=False, contains="unsafe")

    mismatch = root / "archive-mismatch"
    shutil.copytree(output, mismatch)
    source_tar = mismatch / f"home-edge-bootstrap-{VERSION}-source.tar.gz"
    def alter_readme(root_path: pathlib.Path) -> None:
        package = next(root_path.iterdir())
        write(package / "README.md", "tar-only change\n")
    repack_tar(source_tar, alter_readme)
    refresh_artifact_metadata(mismatch, source_tar.name)
    run(replace_argument(verify, "-Dist" if mode == "powershell" else "--dist", mismatch), ok=False, contains="mismatch")

    commit_drift = root / "commit-drift"
    shutil.copytree(output, commit_drift)
    def alter_committed_source(root_path: pathlib.Path) -> None:
        package = next(root_path.iterdir())
        write(package / "README.md", "synchronized uncommitted content\n")
        refresh_content_manifest(package)
    for filename in (
        f"home-edge-bootstrap-{VERSION}-source.zip",
        f"home-edge-bootstrap-{VERSION}-source.tar.gz",
        f"home-edge-bootstrap-{VERSION}-offline.zip",
        f"home-edge-bootstrap-{VERSION}-offline.tar.gz",
    ):
        if filename.endswith(".zip"):
            repack_zip(commit_drift / filename, alter_committed_source)
        else:
            repack_tar(commit_drift / filename, alter_committed_source)
        refresh_artifact_metadata(commit_drift, filename)
    run(replace_argument(verify, "-Dist" if mode == "powershell" else "--dist", commit_drift), ok=False, contains="commit")

    embedded_source = root / "embedded-source-drift"
    shutil.copytree(output, embedded_source)
    def alter_embedded_source(root_path: pathlib.Path) -> None:
        package = next(root_path.iterdir())
        write(package / f"third-party/sources/{MIHOMO_SOURCE}", b"tampered embedded source\n")
        refresh_content_manifest(package)
    for filename in (
        f"home-edge-bootstrap-{VERSION}-offline.zip",
        f"home-edge-bootstrap-{VERSION}-offline.tar.gz",
    ):
        if filename.endswith(".zip"):
            repack_zip(embedded_source / filename, alter_embedded_source)
        else:
            repack_tar(embedded_source / filename, alter_embedded_source)
        refresh_artifact_metadata(embedded_source, filename)
    run(replace_argument(verify, "-Dist" if mode == "powershell" else "--dist", embedded_source), ok=False, contains="complete source")

    duplicate_components = root / "duplicate-components"
    shutil.copytree(output, duplicate_components)
    manifest_path = duplicate_components / "RELEASE-MANIFEST.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["component_locks"].append(dict(manifest["component_locks"][0]))
    write(manifest_path, json.dumps(manifest, indent=2) + "\n")
    refresh_manifest_checksum(duplicate_components)
    run(replace_argument(verify, "-Dist" if mode == "powershell" else "--dist", duplicate_components), ok=False, contains="duplicate")

    duplicate_artifacts = root / "duplicate-artifacts"
    shutil.copytree(output, duplicate_artifacts)
    manifest_path = duplicate_artifacts / "RELEASE-MANIFEST.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["artifacts"].append(dict(manifest["artifacts"][0]))
    write(manifest_path, json.dumps(manifest, indent=2) + "\n")
    refresh_manifest_checksum(duplicate_artifacts)
    run(replace_argument(verify, "-Dist" if mode == "powershell" else "--dist", duplicate_artifacts), ok=False, contains="duplicate")

    wrong_sbom = root / "wrong-sbom"
    shutil.copytree(output, wrong_sbom)
    sbom_path = wrong_sbom / "SBOM.spdx.json"
    sbom = json.loads(sbom_path.read_text(encoding="utf-8"))
    component = next(item for item in sbom["packages"] if item["SPDXID"] == "SPDXRef-Package-Mihomo")
    component["licenseDeclared"] = "Apache-2.0"
    component["checksums"][0]["checksumValue"] = "0" * 64
    sbom["releaseArtifacts"].pop()
    write(sbom_path, json.dumps(sbom, indent=2) + "\n")
    refresh_artifact_metadata(wrong_sbom, "SBOM.spdx.json")
    run(replace_argument(verify, "-Dist" if mode == "powershell" else "--dist", wrong_sbom), ok=False, contains="SBOM")

    linked = root / "linked-artifact"
    shutil.copytree(output, linked)
    linked_target = root / "linked-source-target.zip"
    shutil.copy2(linked / f"home-edge-bootstrap-{VERSION}-source.zip", linked_target)
    (linked / f"home-edge-bootstrap-{VERSION}-source.zip").unlink()
    try:
        os.symlink(linked_target, linked / f"home-edge-bootstrap-{VERSION}-source.zip")
    except OSError:
        pass
    else:
        run(replace_argument(verify, "-Dist" if mode == "powershell" else "--dist", linked), ok=False, contains="link")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("powershell", "posix"), required=True)
    parser.add_argument("--source", type=pathlib.Path, required=True)
    parser.add_argument("--root", type=pathlib.Path)
    arguments = parser.parse_args()
    source = arguments.source.resolve()
    if arguments.root:
        root = arguments.root.resolve()
        root.mkdir(parents=True, exist_ok=True)
        exercise(arguments.mode, source, root)
    else:
        with tempfile.TemporaryDirectory(prefix=f"home-edge-public-release-{arguments.mode}-") as temporary:
            exercise(arguments.mode, source, pathlib.Path(temporary))
    print("public_release_fixture_tests=ok")


if __name__ == "__main__":
    main()
