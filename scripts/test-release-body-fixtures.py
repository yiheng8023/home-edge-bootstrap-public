#!/usr/bin/env python3
"""Regression tests for release download guidance and tag-pinned Markdown links."""

from __future__ import annotations

import argparse
import contextlib
import os
import pathlib
import posixpath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from typing import Optional


LINK_RE = re.compile(r"!?\[[^\]\r\n]*\]\(([^)\s]+)\)")
DOWNLOAD_RE = re.compile(
    r"https://github\.com/([^/\s]+)/([^/\s]+)/releases/download/([^/\s]+)/([^?#)\s]+)"
)
VERSION_HEADING_RE = re.compile(r"^##\s+(v\d+\.\d+\.\d+)\b", re.MULTILINE)
CONCRETE_BUILD_VERSION_RE = re.compile(
    r"(?:build-release\.sh\s+|(?:-Version|--version)\s+)(v\d+\.\d+\.\d+)"
)
LABEL_ROW_RE = re.compile(r"^\|\s*`([^`]+)`\s*\|\s*`([^`]+)`\s*\|\s*$", re.MULTILINE)
REPOSITORY = "example-owner/example-repository"


def fail(message: str) -> None:
    raise SystemExit(f"release_body_fixture_tests=failed\n{message}")


def run_renderer(
    root: pathlib.Path,
    source: str,
    output: pathlib.Path,
    *,
    version: str,
    expect_ok: bool,
    source_ref: Optional[str] = None,
) -> str:
    command = [
        sys.executable,
        str(root / "scripts/render-release-body.py"),
        "--repo-root",
        str(root),
        "--repository",
        REPOSITORY,
        "--version",
        version,
        "--source",
        source,
        "--output",
        str(output),
    ]
    if source_ref:
        command.extend(("--source-ref", source_ref))
    result = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
    )
    if expect_ok and result.returncode:
        fail(f"renderer failed for {source}: {result.stdout.strip()}")
    if not expect_ok and not result.returncode:
        fail(f"renderer accepted an invalid source: {source}")
    return result.stdout


def assert_no_relative_links(rendered: str, label: str) -> None:
    for target in LINK_RE.findall(rendered):
        if target.startswith("#") or target.startswith(("https://", "http://", "mailto:")):
            continue
        fail(f"{label} retained a relative Markdown link: {target}")


def required_assets(surface: str, version: str) -> tuple[str, ...]:
    if surface == "private":
        return (
            f"home-edge-bootstrap-{version}.zip",
            f"home-edge-bootstrap-{version}.tar.gz",
            "RELEASE-MANIFEST.json",
            "SHA256SUMS",
        )
    return (
        f"home-edge-bootstrap-{version}-offline.zip",
        f"home-edge-bootstrap-{version}-offline.tar.gz",
        f"home-edge-bootstrap-{version}-source.zip",
        f"home-edge-bootstrap-{version}-source.tar.gz",
        "mihomo-v1.19.28-source-complete.tar.gz",
        "shellcrash-1.9.4-source-complete.tar.gz",
        "RELEASE-MANIFEST.json",
        "SBOM.spdx.json",
        "SHA256SUMS",
    )


def expected_labels(surface: str, version: str) -> dict[str, str]:
    if surface == "private":
        return {
            f"home-edge-bootstrap-{version}.zip": "Windows portable package",
            f"home-edge-bootstrap-{version}.tar.gz": "macOS/Linux portable package",
            "SHA256SUMS": "Checksums - download with one selected package",
            "RELEASE-MANIFEST.json": "Release manifest - provenance and audit",
        }
    return {
        f"home-edge-bootstrap-{version}-offline.zip": "Windows offline package - runtime included",
        f"home-edge-bootstrap-{version}-offline.tar.gz": "macOS/Linux offline package - runtime included",
        f"home-edge-bootstrap-{version}-source.zip": "Windows source-only package - runtime not included",
        f"home-edge-bootstrap-{version}-source.tar.gz": "macOS/Linux source-only package - runtime not included",
        "SHA256SUMS": "Checksums - download with one selected package",
        "RELEASE-MANIFEST.json": "Release manifest - provenance and audit",
        "SBOM.spdx.json": "SPDX SBOM - audit",
        "mihomo-v1.19.28-source-complete.tar.gz": "Mihomo complete source - not required for installation",
        "shellcrash-1.9.4-source-complete.tar.gz": "ShellCrash complete source - not required for installation",
    }


def assert_current_release_contract(
    rendered: str, label: str, surface: str, version: str
) -> tuple[frozenset[str], tuple[tuple[str, str], ...]]:
    version_headings = VERSION_HEADING_RE.findall(rendered)
    if version_headings != [version]:
        fail(
            f"{label} must contain only the {version} release section; "
            f"found version headings: {version_headings}"
        )
    expected_repository = (
        "yiheng8023/home-edge-bootstrap"
        if surface == "private"
        else "yiheng8023/home-edge-bootstrap-public"
    )
    downloads: set[str] = set()
    for owner, repository, tag, asset in DOWNLOAD_RE.findall(rendered):
        if f"{owner}/{repository}" != expected_repository:
            fail(
                f"{label} download URL targets {owner}/{repository}, expected "
                f"{expected_repository}"
            )
        if tag != version:
            fail(f"{label} links to historical release download tag: {tag}")
        downloads.add(asset)
    expected_assets = set(required_assets(surface, version))
    if downloads != expected_assets:
        fail(
            f"{label} download targets do not exactly match the current asset contract: "
            f"expected={sorted(expected_assets)} actual={sorted(downloads)}"
        )

    label_rows = dict(LABEL_ROW_RE.findall(rendered))
    expected = expected_labels(surface, version)
    actual_labels = {asset: label_rows.get(asset) for asset in expected}
    if actual_labels != expected:
        fail(
            f"{label} GitHub labels do not match the release contract: "
            f"expected={expected!r} actual={actual_labels!r}"
        )
    unknown_label_assets = set(label_rows) - expected_assets
    if unknown_label_assets:
        fail(f"{label} contains labels for unknown assets: {sorted(unknown_label_assets)}")
    return frozenset(downloads), tuple(sorted(actual_labels.items()))


def assert_version_neutral_build_guidance(notes_root: pathlib.Path, surface: str) -> None:
    documents = (
        (
            "README.md",
            "README.zh-CN.md",
            "docs/RUNBOOK.md",
            "docs/zh-CN/RUNBOOK.md",
        )
        if surface == "private"
        else ("docs/PUBLIC_RELEASE.md", "docs/zh-CN/PUBLIC_RELEASE.md")
    )
    for relative in documents:
        text = (notes_root / relative).read_text(encoding="utf-8")
        concrete_versions = CONCRETE_BUILD_VERSION_RE.findall(text)
        if concrete_versions:
            fail(
                f"{relative} hard-codes release build version(s) {concrete_versions}; "
                "use the vX.Y.Z placeholder"
            )


def git(root: pathlib.Path, *arguments: str) -> None:
    result = subprocess.run(
        ["git", "-C", str(root), *arguments],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
    )
    if result.returncode:
        fail(f"fixture Git operation failed: {' '.join(arguments)}: {result.stderr.strip()}")


@contextlib.contextmanager
def temporary_fixture_directory(prefix: str):
    path = pathlib.Path(tempfile.mkdtemp(prefix=prefix))
    try:
        yield path
    finally:
        for attempt in range(10):
            try:
                shutil.rmtree(path, onerror=make_writable_and_retry)
                break
            except PermissionError as error:
                if attempt == 9:
                    fail(f"fixture temporary directory cleanup failed: {path}: {error}")
                time.sleep(0.1 * (attempt + 1))


def make_writable_and_retry(function, path: str, _error) -> None:
    os.chmod(path, stat.S_IREAD | stat.S_IWRITE)
    function(path)


def repository_links(text: str, source: pathlib.PurePosixPath) -> set[str]:
    result: set[str] = set()
    for target in LINK_RE.findall(text):
        if target.startswith("#") or target.startswith(("https://", "http://", "mailto:")):
            continue
        path = target.partition("#")[0].partition("?")[0]
        resolved = posixpath.normpath(posixpath.join(source.parent.as_posix(), path))
        if resolved == ".." or resolved.startswith("../"):
            fail(f"release note link escapes the repository: {target}")
        result.add(resolved)
    return result


def create_tagged_fixture(
    fixture: pathlib.Path,
    renderer: pathlib.Path,
    documents: tuple[pathlib.Path, ...],
    notes_root: pathlib.Path,
    version: str,
) -> None:
    (fixture / "scripts").mkdir(parents=True)
    shutil.copy2(renderer, fixture / "scripts/render-release-body.py")
    document_map: dict[str, str] = {}
    linked_paths: set[str] = set()
    for document in documents:
        relative = document.relative_to(notes_root).as_posix()
        text = document.read_text(encoding="utf-8")
        document_map[relative] = text
        linked_paths.update(repository_links(text, pathlib.PurePosixPath(relative)))
    for relative, text in document_map.items():
        destination = fixture.joinpath(*pathlib.PurePosixPath(relative).parts)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(text, encoding="utf-8", newline="\n")
    for relative in linked_paths:
        destination = fixture.joinpath(*pathlib.PurePosixPath(relative).parts)
        if not destination.exists():
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(f"fixture target for {relative}\n", encoding="utf-8", newline="\n")
    git(fixture, "init", "-q", "-b", "main")
    git(fixture, "config", "user.name", "Release Body Fixture")
    git(fixture, "config", "user.email", "fixture@example.invalid")
    git(fixture, "config", "maintenance.auto", "false")
    git(fixture, "config", "gc.auto", "0")
    git(fixture, "add", ".")
    git(fixture, "commit", "-qm", "release notes fixture")
    git(fixture, "tag", version)


def exercise(root: pathlib.Path, notes_root: pathlib.Path, surface: str) -> None:
    renderer = root / "scripts/render-release-body.py"
    if not renderer.is_file():
        fail("release body renderer is missing")
    assert_version_neutral_build_guidance(notes_root, surface)

    documents = (
        notes_root / "docs/RELEASE_NOTES.md",
        notes_root / "docs/zh-CN/RELEASE_NOTES.md",
    )
    current_version: Optional[str] = None
    for document in documents:
        if not document.is_file():
            fail(f"release note is missing: {document.relative_to(notes_root).as_posix()}")
        text = document.read_text(encoding="utf-8")
        version_headings = VERSION_HEADING_RE.findall(text)
        if not version_headings:
            fail(f"{document.name} has no versioned release section")
        if current_version is None:
            current_version = version_headings[0]
        elif version_headings[0] != current_version:
            fail(
                f"{document.name} current version {version_headings[0]} does not match "
                f"{current_version}"
            )
        for asset in required_assets(surface, current_version):
            if asset not in text:
                fail(f"{document.name} does not explain release asset: {asset}")

    if current_version is None:
        fail("current release version could not be derived")

    rendered_contracts: list[tuple[frozenset[str], tuple[tuple[str, str], ...]]] = []
    with temporary_fixture_directory(prefix=f"home-edge-release-body-{surface}-") as temp:
        fixture = temp / "tagged-repo"
        create_tagged_fixture(fixture, renderer, documents, notes_root, current_version)
        for document in documents:
            relative = document.relative_to(notes_root).as_posix()
            output = temp / (relative.replace("/", "-") + ".rendered.md")
            run_renderer(fixture, relative, output, version=current_version, expect_ok=True)
            rendered = output.read_text(encoding="utf-8")
            assert_no_relative_links(rendered, relative)
            rendered_contracts.append(
                assert_current_release_contract(rendered, relative, surface, current_version)
            )
            if f"https://github.com/{REPOSITORY}/blob/{current_version}/" not in rendered:
                fail(f"{relative} did not produce a tag-pinned repository link")

        if len(set(rendered_contracts)) != 1:
            fail("English and Chinese rendered release contracts do not match")

        (fixture / "docs/RELEASE_NOTES.md").write_text(
            f"# Release notes\n\n## {current_version}\n\n[missing](missing.md)\n",
            encoding="utf-8",
            newline="\n",
        )
        git(fixture, "add", "docs/RELEASE_NOTES.md")
        git(fixture, "commit", "-qm", "broken release note link")
        output = temp / "invalid-link-output.md"
        run_renderer(
            fixture,
            "docs/RELEASE_NOTES.md",
            output,
            version=current_version,
            expect_ok=False,
            source_ref="HEAD",
        )
        if output.exists():
            fail("failed rendering left a partial output")
        inside_output = fixture / "GITHUB-RELEASE.md"
        run_renderer(
            fixture,
            "docs/zh-CN/RELEASE_NOTES.md",
            inside_output,
            version=current_version,
            expect_ok=False,
        )
        if inside_output.exists():
            fail("renderer wrote output inside the repository")

    print("release_body_fixture_tests=ok")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True, type=pathlib.Path)
    parser.add_argument("--notes-root", type=pathlib.Path)
    parser.add_argument("--surface", required=True, choices=("private", "public"))
    arguments = parser.parse_args()
    root = arguments.repo_root.resolve()
    notes_root = arguments.notes_root.resolve() if arguments.notes_root else root
    exercise(root, notes_root, arguments.surface)


if __name__ == "__main__":
    main()
