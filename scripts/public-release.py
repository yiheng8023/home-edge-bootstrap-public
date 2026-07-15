#!/usr/bin/env python3
"""Build and verify deterministic public source and offline release assets."""

from __future__ import annotations

import argparse
import datetime as dt
import gzip
import hashlib
import io
import json
import os
import pathlib
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import uuid
import zipfile


SCHEMA = "home-edge-public-release/v1"
PROJECT = "home-edge-bootstrap"
SUPPORT_BOUNDARY = (
    "Release verification proves archive integrity and declared local contracts only; "
    "it does not guarantee provider availability, sensitive-operation acceptance, "
    "account, payment, registration, financial, or regional-verification outcomes."
)
MIHOMO_SOURCE = "mihomo-v1.19.28-source-complete.tar.gz"
SHELLCRASH_SOURCE = "shellcrash-1.9.4-source-complete.tar.gz"
MIHOMO_PREPARED_SOURCE = "mihomo-v1.19.28-complete-source.tar.gz"
SHELLCRASH_PREPARED_SOURCE = "shellcrash-1.9.4-complete-source.tar.gz"
SENSITIVE_SEGMENTS = {
    ".env", "backup", "backups", "cache", "caches", "log", "logs", "session",
    "sessions", "temp", "tmp",
}
SENSITIVE_SUFFIXES = (
    ".bak", ".backup", ".credentials", ".key", ".local", ".pem", ".pfx",
    ".p12", ".secret", ".temp", ".tmp", ".token", "~",
)
OFFLINE_ONLY = {
    "bundle/MANIFEST.json",
    "bundle/SHA256SUMS",
    "bundle/ShellCrash.tar.gz",
    "bundle/mihomo-linux-arm64",
    f"third-party/sources/{MIHOMO_SOURCE}",
    f"third-party/sources/{SHELLCRASH_SOURCE}",
    "third-party/licenses/mihomo-GPL-3.0-only.txt",
    "third-party/licenses/shellcrash-GPL-3.0-only.txt",
}
INTERNAL_TOKENS = (
    b"public" + b"-overlay",
    b"home-edge-bootstrap-" + b"public-impl",
    b"c:" + b"\\projects\\home-edge-bootstrap\\",
    b"c:" + b"/projects/home-edge-bootstrap/",
)


class ReleaseError(RuntimeError):
    pass


def fail(message: str) -> None:
    raise ReleaseError(message)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: pathlib.Path) -> str:
    with path.open("rb") as stream:
        digest = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_bytes(path: pathlib.Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(data)


def write_text(path: pathlib.Path, value: str) -> None:
    normalized = value.replace("\r\n", "\n").replace("\r", "\n").rstrip("\n") + "\n"
    write_bytes(path, normalized.encode("utf-8"))


def run_git(repo: pathlib.Path, arguments: list[str], *, binary: bool = False):
    result = subprocess.run(
        ["git", "-C", str(repo), *arguments],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode:
        detail = result.stderr.decode("utf-8", "replace").strip()
        fail(f"public commit Git operation failed: {' '.join(arguments)}: {detail}")
    return result.stdout if binary else result.stdout.decode("utf-8", "strict")


def resolve_commit(repo: pathlib.Path, revision: str) -> str:
    value = run_git(repo, ["rev-parse", "--verify", f"{revision}^{{commit}}"] ).strip()
    if not re.fullmatch(r"[0-9a-f]{40}", value):
        fail("public commit did not resolve to a full object identity")
    return value


def commit_epoch(repo: pathlib.Path, commit: str) -> int:
    value = run_git(repo, ["show", "-s", "--format=%ct", commit]).strip()
    if not value.isdigit():
        fail("public commit time is invalid")
    return int(value)


def safe_relative(value: str) -> str:
    if not value or "\\" in value or value.startswith("/") or "//" in value:
        fail(f"unsafe portable path: {value}")
    if not re.fullmatch(r"[A-Za-z0-9._/-]+", value):
        fail(f"unsafe portable path: {value}")
    parts = value.split("/")
    if any(part in ("", ".", "..") or part.endswith(".") for part in parts):
        fail(f"unsafe portable path: {value}")
    for part in parts:
        base = part.split(".", 1)[0].upper()
        if re.fullmatch(r"CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9]", base):
            fail(f"unsafe portable path: {value}")
    return value


def sensitive_path(value: str) -> bool:
    parts = value.lower().split("/")
    if any(part in SENSITIVE_SEGMENTS for part in parts):
        return True
    name = parts[-1]
    return any(name.endswith(suffix) for suffix in SENSITIVE_SUFFIXES)


def assert_clean(repo: pathlib.Path) -> None:
    records = run_git(repo, ["status", "--porcelain=v1", "-z", "--untracked-files=all"], binary=True)
    dirty = [record for record in records.split(b"\0") if record]
    if not dirty:
        return
    for record in dirty:
        text = record.decode("utf-8", "replace")
        path = text[3:].replace("\\", "/") if len(text) > 3 else text
        if text.startswith("?? ") and sensitive_path(path):
            fail(f"untracked sensitive content is present: {path}")
    fail("public source tree is dirty")


def blob(repo: pathlib.Path, commit: str, path: str) -> bytes:
    safe_relative(path)
    return run_git(repo, ["show", f"{commit}:{path}"], binary=True)


def json_blob(repo: pathlib.Path, commit: str, path: str):
    try:
        return json.loads(blob(repo, commit, path).decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"invalid committed JSON at {path}: {error}")


def release_paths(repo: pathlib.Path, commit: str) -> list[str]:
    allowlist = blob(repo, commit, "config/public-release-files.txt").decode("utf-8", "strict")
    roots: list[str] = []
    seen_roots: set[str] = set()
    for raw in allowlist.splitlines():
        value = raw.strip()
        if not value or value.startswith("#"):
            continue
        value = safe_relative(value)
        if value in seen_roots:
            fail(f"duplicate public release allowlist root: {value}")
        seen_roots.add(value)
        roots.append(value)
    if not roots:
        fail("public release allowlist is empty")
    selected_by: dict[str, str] = {}
    for root in roots:
        output = run_git(repo, ["ls-tree", "-r", "--name-only", commit, "--", root])
        matches = [safe_relative(line) for line in output.splitlines() if line]
        if not matches:
            fail(f"public release allowlist root matches no committed path: {root}")
        for path in matches:
            prior = selected_by.get(path)
            if prior is not None:
                fail(f"overlap in public release allowlist: {prior} and {root} both select {path}")
            selected_by[path] = root
    if not selected_by:
        fail("public release allowlist selected no committed files")
    for path in selected_by:
        lowered = path.lower()
        if sensitive_path(path) or lowered == ".git" or lowered.startswith(".git/"):
            fail(f"sensitive path selected by public release allowlist: {path}")
        if lowered == "dist" or lowered.startswith("dist/"):
            fail(f"release output selected by public release allowlist: {path}")
        if path in OFFLINE_ONLY or path.startswith("third-party/sources/"):
            fail(f"source/offline file-list mix-up in public release allowlist: {path}")
        tree = run_git(repo, ["ls-tree", commit, "--", path]).strip()
        mode = tree.split(" ", 1)[0] if tree else ""
        if mode not in ("100644", "100755"):
            fail(f"non-regular committed release path: {path}")
    return sorted(selected_by, key=lambda value: value.encode("utf-8"))


def scan_internal(path: str, data: bytes) -> None:
    lowered = data.lower()
    for token in INTERNAL_TOKENS:
        if token in lowered:
            fail(f"internal reference detected in public release content: {path}")


def component_map(lock: object) -> dict[str, dict]:
    if not isinstance(lock, dict) or lock.get("schema_version") != 1:
        fail("invalid third-party lock schema")
    components = lock.get("components")
    if not isinstance(components, list):
        fail("third-party lock components are missing")
    if any(not isinstance(item, dict) for item in components):
        fail("third-party lock component is not an object")
    identifiers = [item.get("id") for item in components]
    if len(set(identifiers)) != len(identifiers):
        fail("duplicate third-party component ID")
    by_id = {item.get("id"): item for item in components}
    if set(by_id) != {"mihomo-linux-arm64", "shellcrash"}:
        fail("third-party component lock is incomplete")
    for item in by_id.values():
        if item.get("license") != "GPL-3.0-only":
            fail("third-party license declaration is wrong")
        for key in ("payload_sha256", "license_sha256", "complete_source_sha256"):
            if not re.fullmatch(r"[0-9a-f]{64}", str(item.get(key, ""))):
                fail(f"invalid third-party checksum: {item.get('id')} {key}")
    return by_id


def prepared_inputs(prepared: pathlib.Path, lock: dict[str, dict]) -> dict[str, pathlib.Path]:
    paths = {
        "mihomo_payload": prepared / "third-party/mihomo/mihomo-linux-arm64",
        "shellcrash_payload": prepared / "third-party/shellcrash/ShellCrash.tar.gz",
        "mihomo_license": prepared / "third-party/mihomo/LICENSE",
        "shellcrash_license": prepared / "third-party/shellcrash/LICENSE.txt",
        "mihomo_source": prepared / "third-party/sources" / MIHOMO_PREPARED_SOURCE,
        "shellcrash_source": prepared / "third-party/sources" / SHELLCRASH_PREPARED_SOURCE,
    }
    for label, path in paths.items():
        if not path.is_file() or path.is_symlink():
            fail(f"missing prepared {label.replace('_', ' ')}")
    expected = {
        "mihomo_payload": lock["mihomo-linux-arm64"]["payload_sha256"],
        "shellcrash_payload": lock["shellcrash"]["payload_sha256"],
        "mihomo_license": lock["mihomo-linux-arm64"]["license_sha256"],
        "shellcrash_license": lock["shellcrash"]["license_sha256"],
        "mihomo_source": lock["mihomo-linux-arm64"]["complete_source_sha256"],
        "shellcrash_source": lock["shellcrash"]["complete_source_sha256"],
    }
    for label, path in paths.items():
        actual = sha256_file(path)
        if actual != expected[label]:
            word = "license" if "license" in label else "checksum"
            fail(f"prepared {label.replace('_', ' ')} {word} mismatch")
    return paths


def all_files(root: pathlib.Path) -> list[pathlib.Path]:
    return sorted(
        (path for path in root.rglob("*") if path.is_file()),
        key=lambda path: path.relative_to(root).as_posix().encode("utf-8"),
    )


def relative_files(root: pathlib.Path) -> dict[str, bytes]:
    return {path.relative_to(root).as_posix(): path.read_bytes() for path in all_files(root)}


def write_content_manifest(root: pathlib.Path) -> None:
    entries = relative_files(root)
    entries.pop("CONTENT-SHA256SUMS", None)
    lines = [f"{sha256_bytes(data)}  {path}" for path, data in entries.items()]
    write_text(root / "CONTENT-SHA256SUMS", "\n".join(lines))


def expected_source_files(repo: pathlib.Path, commit: str, version: str) -> dict[str, bytes]:
    result = {path: blob(repo, commit, path) for path in release_paths(repo, commit)}
    if "VERSION" in result or "PUBLIC-COMMIT" in result or "CONTENT-SHA256SUMS" in result:
        fail("public release allowlist collides with generated source metadata")
    result["VERSION"] = f"{version}\n".encode("utf-8")
    result["PUBLIC-COMMIT"] = f"{commit}\n".encode("ascii")
    result = dict(sorted(result.items()))
    manifest = "\n".join(f"{sha256_bytes(data)}  {path}" for path, data in result.items()) + "\n"
    result["CONTENT-SHA256SUMS"] = manifest.encode("ascii")
    return dict(sorted(result.items()))


def mode_for(path: str) -> int:
    return 0o755 if path.endswith(".sh") or path == "bootstrap.sh" else 0o644


def zip_time(epoch: int) -> tuple[int, int, int, int, int, int]:
    value = dt.datetime.fromtimestamp(max(epoch, 315532800), tz=dt.timezone.utc)
    return value.year, value.month, value.day, value.hour, value.minute, value.second


def create_zip(root: pathlib.Path, destination: pathlib.Path, epoch: int) -> None:
    with zipfile.ZipFile(destination, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for relative, data in relative_files(root).items():
            info = zipfile.ZipInfo(f"{root.name}/{relative}", date_time=zip_time(epoch))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = (stat.S_IFREG | mode_for(relative)) << 16
            archive.writestr(info, data)


def create_tar(root: pathlib.Path, destination: pathlib.Path, epoch: int) -> None:
    with destination.open("xb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=epoch, compresslevel=9) as zipped:
            with tarfile.open(fileobj=zipped, mode="w", format=tarfile.PAX_FORMAT) as archive:
                for relative, data in relative_files(root).items():
                    info = tarfile.TarInfo(f"{root.name}/{relative}")
                    info.size = len(data)
                    info.mode = mode_for(relative)
                    info.uid = info.gid = 0
                    info.uname = info.gname = ""
                    info.mtime = epoch
                    archive.addfile(info, io.BytesIO(data))


def archive_relative(name: str, expected_root: str) -> str | None:
    if "\\" in name or name.startswith("/") or re.match(r"^[A-Za-z]:", name):
        fail(f"unsafe archive path: {name}")
    parts = name.rstrip("/").split("/")
    if any(part in ("", ".", "..") for part in parts):
        fail(f"unsafe archive path: {name}")
    if parts[0] != expected_root:
        fail(f"unsafe archive root: {name}")
    if len(parts) == 1:
        return None
    relative = "/".join(parts[1:])
    safe_relative(relative)
    return relative


def read_zip(path: pathlib.Path, expected_root: str) -> dict[str, bytes]:
    result: dict[str, bytes] = {}
    try:
        with zipfile.ZipFile(path) as archive:
            for item in archive.infolist():
                relative = archive_relative(item.filename, expected_root)
                if item.is_dir() or relative is None:
                    continue
                mode = (item.external_attr >> 16) & 0o170000
                if mode == stat.S_IFLNK:
                    fail(f"unsafe archive link: {item.filename}")
                if relative in result:
                    fail(f"duplicate archive path: {relative}")
                result[relative] = archive.read(item)
    except (zipfile.BadZipFile, OSError) as error:
        fail(f"invalid ZIP archive: {path.name}: {error}")
    if not result:
        fail(f"empty ZIP archive: {path.name}")
    return dict(sorted(result.items()))


def read_tar(path: pathlib.Path, expected_root: str) -> dict[str, bytes]:
    result: dict[str, bytes] = {}
    try:
        with tarfile.open(path, "r:gz") as archive:
            for item in archive.getmembers():
                relative = archive_relative(item.name, expected_root)
                if item.isdir() or relative is None:
                    continue
                if not item.isfile():
                    fail(f"unsafe archive member type: {item.name}")
                if relative in result:
                    fail(f"duplicate archive path: {relative}")
                stream = archive.extractfile(item)
                if stream is None:
                    fail(f"cannot read archive member: {item.name}")
                result[relative] = stream.read()
    except (tarfile.TarError, OSError) as error:
        fail(f"invalid tar archive: {path.name}: {error}")
    if not result:
        fail(f"empty tar archive: {path.name}")
    return dict(sorted(result.items()))


def verify_content_manifest(files: dict[str, bytes], label: str) -> None:
    raw = files.get("CONTENT-SHA256SUMS")
    if raw is None:
        fail(f"{label} content checksum manifest is missing")
    try:
        lines = raw.decode("ascii").splitlines()
    except UnicodeDecodeError:
        fail(f"{label} content checksum manifest is not ASCII")
    declared: dict[str, str] = {}
    for line in lines:
        match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9._/-]+)", line)
        if not match:
            fail(f"{label} content checksum line is malformed")
        relative = safe_relative(match.group(2))
        if relative in declared:
            fail(f"{label} duplicate content checksum path: {relative}")
        declared[relative] = match.group(1)
    actual_paths = set(files) - {"CONTENT-SHA256SUMS"}
    if set(declared) != actual_paths:
        fail(f"{label} archive content manifest file-list mismatch")
    for relative, expected in declared.items():
        if sha256_bytes(files[relative]) != expected:
            fail(f"{label} archive content checksum mismatch: {relative}")


def verify_archive_pair(dist: pathlib.Path, package: str, label: str) -> dict[str, bytes]:
    zipped = read_zip(dist / f"{package}.zip", package)
    tarred = read_tar(dist / f"{package}.tar.gz", package)
    if label == "source":
        forbidden = sorted(
            path
            for path in set(zipped) | set(tarred)
            if path in OFFLINE_ONLY
            or path.startswith("third-party/licenses/")
            or path.startswith("third-party/sources/")
        )
        if forbidden:
            fail(f"source archive contains offline-only path: {forbidden[0]}")
    if zipped != tarred:
        fail(f"{label} ZIP/tar content mismatch")
    verify_content_manifest(zipped, label)
    return zipped


def build_sbom(version: str, commit: str, created: str, artifacts: list[dict], lock: dict[str, dict]) -> dict:
    packages = [
        {
            "name": PROJECT,
            "SPDXID": "SPDXRef-Package-Source",
            "versionInfo": version,
            "downloadLocation": "NOASSERTION",
            "filesAnalyzed": False,
            "licenseConcluded": "Apache-2.0",
            "licenseDeclared": "Apache-2.0",
            "copyrightText": "NOASSERTION",
            "externalRefs": [{"referenceCategory": "OTHER", "referenceType": "vcs-url", "referenceLocator": f"git+https://github.com/yiheng8023/home-edge-bootstrap-public@{commit}"}],
        }
    ]
    for component_id, spdx_id in (("mihomo-linux-arm64", "SPDXRef-Package-Mihomo"), ("shellcrash", "SPDXRef-Package-ShellCrash")):
        item = lock[component_id]
        packages.append(
            {
                "name": component_id,
                "SPDXID": spdx_id,
                "versionInfo": item["version"],
                "downloadLocation": item["source_repository"],
                "filesAnalyzed": False,
                "licenseConcluded": "GPL-3.0-only",
                "licenseDeclared": "GPL-3.0-only",
                "copyrightText": "NOASSERTION",
                "checksums": [{"algorithm": "SHA256", "checksumValue": item["payload_sha256"]}],
                "externalRefs": [
                    {"referenceCategory": "OTHER", "referenceType": "vcs-url", "referenceLocator": f"git+{item['source_repository']}@{item['source_commit']}"},
                    {"referenceCategory": "OTHER", "referenceType": "complete-source-sha256", "referenceLocator": item["complete_source_sha256"]},
                ],
            }
        )
    return {
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": f"{PROJECT}-{version}-release",
        "documentNamespace": f"https://github.com/yiheng8023/home-edge-bootstrap-public/releases/{version}/sbom/{commit}",
        "creationInfo": {"created": created, "creators": ["Tool: home-edge-bootstrap-public-release"]},
        "documentComment": SUPPORT_BOUNDARY,
        "packages": packages,
        "releaseArtifacts": artifacts,
    }


def build_release(repo: pathlib.Path, version: str, prepared: pathlib.Path, output: pathlib.Path, revision: str) -> None:
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", version):
        fail(f"invalid public release version: {version}")
    repo = repo.resolve()
    prepared = prepared.resolve()
    output = output.resolve()
    if not repo.is_dir() or not (repo / ".git").exists():
        fail("public release repository is not a Git worktree")
    if not output.parent.is_dir():
        fail("public release output parent does not exist")
    assert_clean(repo)
    commit = resolve_commit(repo, revision)
    head = resolve_commit(repo, "HEAD")
    if commit != head:
        fail("public commit must be the clean checked-out HEAD")
    epoch = commit_epoch(repo, commit)
    created = dt.datetime.fromtimestamp(epoch, tz=dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    paths = release_paths(repo, commit)
    lock_data = json_blob(repo, commit, "config/third-party-lock.json")
    lock = component_map(lock_data)
    source_sbom = json_blob(repo, commit, "config/sbom.json")
    if source_sbom.get("spdxVersion") != "SPDX-2.3":
        fail("committed source SBOM is not SPDX 2.3")
    prepared_map = prepared_inputs(prepared, lock)
    lock_path = pathlib.Path(str(output) + ".release.lock")
    stage = output.parent / f".{output.name}.stage-{uuid.uuid4().hex}"
    try:
        lock_path.mkdir()
    except FileExistsError:
        fail("public release output lock is held")
    except OSError as error:
        fail(f"cannot create public release output lock: {error}")
    try:
        if output.exists():
            fail("public release output path must be absent")
        stage.mkdir(mode=0o700)
        source_name = f"{PROJECT}-{version}-source"
        offline_name = f"{PROJECT}-{version}-offline"
        source_root = stage / ".source" / source_name
        offline_root = stage / ".offline" / offline_name
        source_root.mkdir(parents=True)
        for path in paths:
            data = blob(repo, commit, path)
            scan_internal(path, data)
            write_bytes(source_root / path, data)
        write_text(source_root / "VERSION", version)
        write_text(source_root / "PUBLIC-COMMIT", commit)
        write_content_manifest(source_root)
        shutil.copytree(source_root, offline_root)
        (offline_root / "CONTENT-SHA256SUMS").unlink()
        write_bytes(offline_root / "bundle/mihomo-linux-arm64", prepared_map["mihomo_payload"].read_bytes())
        write_bytes(offline_root / "bundle/ShellCrash.tar.gz", prepared_map["shellcrash_payload"].read_bytes())
        bundle_sums = [
            f"{lock['shellcrash']['payload_sha256']}  ShellCrash.tar.gz",
            f"{lock['mihomo-linux-arm64']['payload_sha256']}  mihomo-linux-arm64",
        ]
        write_text(offline_root / "bundle/SHA256SUMS", "\n".join(sorted(bundle_sums)))
        bundle_manifest = {
            "schema": 1,
            "payloads": [
                {"id": "mihomo-linux-arm64", "path": "mihomo-linux-arm64", "version": lock["mihomo-linux-arm64"]["version"], "sha256": lock["mihomo-linux-arm64"]["payload_sha256"]},
                {"id": "shellcrash", "path": "ShellCrash.tar.gz", "version": lock["shellcrash"]["version"], "sha256": lock["shellcrash"]["payload_sha256"]},
            ],
        }
        write_text(offline_root / "bundle/MANIFEST.json", json.dumps(bundle_manifest, indent=2))
        write_bytes(offline_root / "third-party/licenses/mihomo-GPL-3.0-only.txt", prepared_map["mihomo_license"].read_bytes())
        write_bytes(offline_root / "third-party/licenses/shellcrash-GPL-3.0-only.txt", prepared_map["shellcrash_license"].read_bytes())
        write_bytes(offline_root / f"third-party/sources/{MIHOMO_SOURCE}", prepared_map["mihomo_source"].read_bytes())
        write_bytes(offline_root / f"third-party/sources/{SHELLCRASH_SOURCE}", prepared_map["shellcrash_source"].read_bytes())
        write_content_manifest(offline_root)

        assets = stage / ".assets"
        assets.mkdir()
        source_zip = assets / f"{source_name}.zip"
        source_tar = assets / f"{source_name}.tar.gz"
        offline_zip = assets / f"{offline_name}.zip"
        offline_tar = assets / f"{offline_name}.tar.gz"
        create_zip(source_root, source_zip, epoch)
        create_tar(source_root, source_tar, epoch)
        create_zip(offline_root, offline_zip, epoch)
        create_tar(offline_root, offline_tar, epoch)
        shutil.copy2(prepared_map["mihomo_source"], assets / MIHOMO_SOURCE)
        shutil.copy2(prepared_map["shellcrash_source"], assets / SHELLCRASH_SOURCE)

        artifact_paths = [source_zip, source_tar, offline_zip, offline_tar, assets / MIHOMO_SOURCE, assets / SHELLCRASH_SOURCE]
        sbom_records = [{"path": path.name, "sha256": sha256_file(path), "size": path.stat().st_size} for path in artifact_paths]
        sbom = build_sbom(version, commit, created, sbom_records, lock)
        write_text(assets / "SBOM.spdx.json", json.dumps(sbom, indent=2))
        manifest_artifacts = [
            {"path": path.name, "sha256": sha256_file(path), "size": path.stat().st_size}
            for path in [*artifact_paths, assets / "SBOM.spdx.json"]
        ]
        manifest = {
            "schema": SCHEMA,
            "project": PROJECT,
            "version": version,
            "public_commit": commit,
            "build_time": created,
            "support_boundary": SUPPORT_BOUNDARY,
            "content_manifest": "CONTENT-SHA256SUMS",
            "component_locks": lock_data["components"],
            "artifacts": manifest_artifacts,
        }
        write_text(assets / "RELEASE-MANIFEST.json", json.dumps(manifest, indent=2))
        sums_targets = sorted([*artifact_paths, assets / "SBOM.spdx.json", assets / "RELEASE-MANIFEST.json"], key=lambda path: path.name)
        write_text(assets / "SHA256SUMS", "\n".join(f"{sha256_file(path)}  {path.name}" for path in sums_targets))
        verify_distribution(assets, repo, version, commit)
        assets.rename(output)
    finally:
        shutil.rmtree(stage, ignore_errors=True)
        try:
            lock_path.rmdir()
        except FileNotFoundError:
            pass
    print("public_release_state=ready")
    print(f"public_release_version={version}")
    print("public_release_artifact_count=9")


def parse_sums(path: pathlib.Path) -> dict[str, str]:
    result: dict[str, str] = {}
    try:
        lines = path.read_text(encoding="ascii").splitlines()
    except (OSError, UnicodeDecodeError) as error:
        fail(f"release checksum file is unreadable: {error}")
    for line in lines:
        match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9._-]+)", line)
        if not match:
            fail("release checksum line is malformed")
        if match.group(2) in result:
            fail("release checksum contains duplicate path")
        result[match.group(2)] = match.group(1)
    return result


def verify_distribution(dist: pathlib.Path, repo: pathlib.Path, version: str, commit: str) -> None:
    source_name = f"{PROJECT}-{version}-source"
    offline_name = f"{PROJECT}-{version}-offline"
    expected = {
        f"{source_name}.zip", f"{source_name}.tar.gz",
        f"{offline_name}.zip", f"{offline_name}.tar.gz",
        MIHOMO_SOURCE, SHELLCRASH_SOURCE,
        "SBOM.spdx.json", "RELEASE-MANIFEST.json", "SHA256SUMS",
    }
    actual = {path.name for path in dist.iterdir()} if dist.is_dir() else set()
    if actual != expected:
        fail("public release must contain exactly nine regular artifacts")
    for name in expected:
        path = dist / name
        if path.is_symlink():
            fail(f"top-level release artifact is a link: {name}")
        try:
            mode = path.lstat().st_mode
        except OSError:
            fail(f"top-level release artifact is missing: {name}")
        if not stat.S_ISREG(mode):
            fail(f"top-level release artifact is not a regular file: {name}")
    sums = parse_sums(dist / "SHA256SUMS")
    if set(sums) != expected - {"SHA256SUMS"}:
        fail("release checksum file-list mismatch")
    for name, expected_hash in sums.items():
        if sha256_file(dist / name) != expected_hash:
            fail(f"release checksum mismatch: {name}")
    try:
        manifest = json.loads((dist / "RELEASE-MANIFEST.json").read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"invalid release manifest: {error}")
    if manifest.get("schema") != SCHEMA or manifest.get("project") != PROJECT:
        fail("release manifest schema or project mismatch")
    if manifest.get("version") != version or manifest.get("public_commit") != commit:
        fail("release manifest public version or commit mismatch")
    if manifest.get("support_boundary") != SUPPORT_BOUNDARY:
        fail("release manifest sensitive-operation support boundary mismatch")
    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list) or any(not isinstance(item, dict) for item in artifacts):
        fail("release manifest artifacts are missing")
    expected_manifest = expected - {"SHA256SUMS", "RELEASE-MANIFEST.json"}
    artifact_paths = [item.get("path") for item in artifacts]
    if len(set(artifact_paths)) != len(artifact_paths):
        fail("duplicate release manifest artifact path")
    by_path = {item.get("path"): item for item in artifacts}
    if set(by_path) != expected_manifest:
        fail("release manifest artifact file-list mismatch")
    for name, item in by_path.items():
        if item.get("sha256") != sha256_file(dist / name) or item.get("size") != (dist / name).stat().st_size:
            fail(f"release manifest artifact mismatch: {name}")
    lock = component_map({"schema_version": 1, "components": manifest.get("component_locks")})
    committed_lock = component_map(json_blob(repo, commit, "config/third-party-lock.json"))
    if lock != committed_lock:
        fail("release manifest component lock mismatch")
    if sha256_file(dist / MIHOMO_SOURCE) != lock["mihomo-linux-arm64"]["complete_source_sha256"]:
        fail("Mihomo complete source checksum mismatch")
    if sha256_file(dist / SHELLCRASH_SOURCE) != lock["shellcrash"]["complete_source_sha256"]:
        fail("ShellCrash complete source checksum mismatch")
    try:
        sbom = json.loads((dist / "SBOM.spdx.json").read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        fail(f"invalid release SBOM: {error}")
    if sbom.get("spdxVersion") != "SPDX-2.3" or sbom.get("name") != f"{PROJECT}-{version}-release":
        fail("release SBOM identity mismatch")
    if sbom.get("documentComment") != SUPPORT_BOUNDARY:
        fail("release SBOM sensitive-operation support boundary mismatch")
    packages = sbom.get("packages")
    if not isinstance(packages, list) or any(not isinstance(item, dict) for item in packages):
        fail("release SBOM packages are missing")
    package_ids = [item.get("SPDXID") for item in packages]
    if len(set(package_ids)) != len(package_ids):
        fail("duplicate release SBOM package ID")
    packages_by_id = {item.get("SPDXID"): item for item in packages}
    if set(packages_by_id) != {"SPDXRef-Package-Source", "SPDXRef-Package-Mihomo", "SPDXRef-Package-ShellCrash"}:
        fail("release SBOM package closure mismatch")
    source_package = packages_by_id["SPDXRef-Package-Source"]
    expected_public_ref = f"git+https://github.com/yiheng8023/home-edge-bootstrap-public@{commit}"
    if (
        source_package.get("name") != PROJECT
        or source_package.get("versionInfo") != version
        or source_package.get("licenseDeclared") != "Apache-2.0"
        or source_package.get("licenseConcluded") != "Apache-2.0"
        or source_package.get("externalRefs") != [
            {"referenceCategory": "OTHER", "referenceType": "vcs-url", "referenceLocator": expected_public_ref}
        ]
    ):
        fail("release SBOM public source package mismatch")
    for component_id, spdx_id in (("mihomo-linux-arm64", "SPDXRef-Package-Mihomo"), ("shellcrash", "SPDXRef-Package-ShellCrash")):
        package = packages_by_id[spdx_id]
        item = lock[component_id]
        expected_refs = [
            {"referenceCategory": "OTHER", "referenceType": "vcs-url", "referenceLocator": f"git+{item['source_repository']}@{item['source_commit']}"},
            {"referenceCategory": "OTHER", "referenceType": "complete-source-sha256", "referenceLocator": item["complete_source_sha256"]},
        ]
        if (
            package.get("name") != component_id
            or package.get("versionInfo") != item["version"]
            or package.get("downloadLocation") != item["source_repository"]
            or package.get("licenseDeclared") != "GPL-3.0-only"
            or package.get("licenseConcluded") != "GPL-3.0-only"
            or package.get("checksums") != [{"algorithm": "SHA256", "checksumValue": item["payload_sha256"]}]
            or package.get("externalRefs") != expected_refs
        ):
            fail(f"release SBOM component mismatch: {component_id}")
    sbom_artifacts = sbom.get("releaseArtifacts")
    if not isinstance(sbom_artifacts, list) or any(not isinstance(item, dict) for item in sbom_artifacts):
        fail("release SBOM artifact closure is missing")
    sbom_paths = [item.get("path") for item in sbom_artifacts]
    if len(set(sbom_paths)) != len(sbom_paths):
        fail("duplicate release SBOM artifact path")
    expected_sbom_paths = expected - {"SHA256SUMS", "RELEASE-MANIFEST.json", "SBOM.spdx.json"}
    sbom_by_path = {item.get("path"): item for item in sbom_artifacts}
    if set(sbom_by_path) != expected_sbom_paths:
        fail("release SBOM artifact closure mismatch")
    for name, item in sbom_by_path.items():
        if item.get("sha256") != sha256_file(dist / name) or item.get("size") != (dist / name).stat().st_size:
            fail(f"release SBOM artifact mismatch: {name}")
    source_files = verify_archive_pair(dist, source_name, "source")
    offline_files = verify_archive_pair(dist, offline_name, "offline")
    if source_files != expected_source_files(repo, commit, version):
        fail("source archive does not match the declared public commit")
    missing_offline = sorted(OFFLINE_ONLY - set(offline_files))
    if missing_offline:
        fail(f"offline archive is missing required path: {missing_offline[0]}")
    for path, data in source_files.items():
        if path == "CONTENT-SHA256SUMS":
            continue
        if offline_files.get(path) != data:
            fail(f"source/offline shared content mismatch: {path}")
    if offline_files["bundle/mihomo-linux-arm64"] and sha256_bytes(offline_files["bundle/mihomo-linux-arm64"]) != lock["mihomo-linux-arm64"]["payload_sha256"]:
        fail("offline Mihomo payload checksum mismatch")
    if sha256_bytes(offline_files["bundle/ShellCrash.tar.gz"]) != lock["shellcrash"]["payload_sha256"]:
        fail("offline ShellCrash payload checksum mismatch")
    if sha256_bytes(offline_files["third-party/licenses/mihomo-GPL-3.0-only.txt"]) != lock["mihomo-linux-arm64"]["license_sha256"]:
        fail("offline Mihomo license checksum mismatch")
    if sha256_bytes(offline_files["third-party/licenses/shellcrash-GPL-3.0-only.txt"]) != lock["shellcrash"]["license_sha256"]:
        fail("offline ShellCrash license checksum mismatch")
    if sha256_bytes(offline_files[f"third-party/sources/{MIHOMO_SOURCE}"]) != lock["mihomo-linux-arm64"]["complete_source_sha256"]:
        fail("offline Mihomo complete source checksum mismatch")
    if sha256_bytes(offline_files[f"third-party/sources/{SHELLCRASH_SOURCE}"]) != lock["shellcrash"]["complete_source_sha256"]:
        fail("offline ShellCrash complete source checksum mismatch")
    for name in expected - {f"{source_name}.zip", f"{source_name}.tar.gz", f"{offline_name}.zip", f"{offline_name}.tar.gz"}:
        scan_internal(name, (dist / name).read_bytes())
    for label, files in (("source", source_files), ("offline", offline_files)):
        for path, data in files.items():
            scan_internal(f"{label}:{path}", data)


def verify_release(repo: pathlib.Path, version: str, dist: pathlib.Path, revision: str) -> None:
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", version):
        fail(f"invalid public release version: {version}")
    repo = repo.resolve()
    dist = dist.resolve()
    commit = resolve_commit(repo, revision)
    verify_distribution(dist, repo, version, commit)
    print("public_release_state=ready")
    print(f"public_release_version={version}")
    print("public_release_artifact_count=9")


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)
    build = commands.add_parser("build")
    build.add_argument("--repo", required=True, type=pathlib.Path)
    build.add_argument("--version", required=True)
    build.add_argument("--prepared-dir", required=True, type=pathlib.Path)
    build.add_argument("--output", required=True, type=pathlib.Path)
    build.add_argument("--commit", default="HEAD")
    build.add_argument("--fixture-mode", action="store_true")
    verify = commands.add_parser("verify")
    verify.add_argument("--repo", required=True, type=pathlib.Path)
    verify.add_argument("--dist", required=True, type=pathlib.Path)
    verify.add_argument("--version", required=True)
    verify.add_argument("--commit", default="HEAD")
    return root


def main() -> None:
    arguments = parser().parse_args()
    try:
        if arguments.command == "build":
            build_release(arguments.repo, arguments.version, arguments.prepared_dir, arguments.output, arguments.commit)
        else:
            verify_release(arguments.repo, arguments.version, arguments.dist, arguments.commit)
    except ReleaseError as error:
        print("public_release_state=failed", file=sys.stderr)
        print(str(error), file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
