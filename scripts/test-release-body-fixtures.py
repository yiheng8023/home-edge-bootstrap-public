#!/usr/bin/env python3
"""Regression tests for release download guidance and tag-pinned Markdown links."""

from __future__ import annotations

import argparse
import pathlib
import posixpath
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Optional


LINK_RE = re.compile(r"!?\[[^\]\r\n]*\]\(([^)\s]+)\)")
REPOSITORY = "example-owner/example-repository"
VERSION = "v0.1.0"


def fail(message: str) -> None:
    raise SystemExit(f"release_body_fixture_tests=failed\n{message}")


def run_renderer(
    root: pathlib.Path,
    source: str,
    output: pathlib.Path,
    *,
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
        VERSION,
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


def required_assets(surface: str) -> tuple[str, ...]:
    if surface == "private":
        return (
            "home-edge-bootstrap-v0.1.0.zip",
            "home-edge-bootstrap-v0.1.0.tar.gz",
            "RELEASE-MANIFEST.json",
            "SHA256SUMS",
        )
    return (
        "home-edge-bootstrap-v0.1.0-offline.zip",
        "home-edge-bootstrap-v0.1.0-offline.tar.gz",
        "home-edge-bootstrap-v0.1.0-source.zip",
        "home-edge-bootstrap-v0.1.0-source.tar.gz",
        "mihomo-v1.19.28-source-complete.tar.gz",
        "shellcrash-1.9.4-source-complete.tar.gz",
        "RELEASE-MANIFEST.json",
        "SBOM.spdx.json",
        "SHA256SUMS",
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
    git(fixture, "add", ".")
    git(fixture, "commit", "-qm", "release notes fixture")
    git(fixture, "tag", VERSION)


def exercise(root: pathlib.Path, notes_root: pathlib.Path, surface: str) -> None:
    renderer = root / "scripts/render-release-body.py"
    if not renderer.is_file():
        fail("release body renderer is missing")

    documents = (
        notes_root / "docs/RELEASE_NOTES.md",
        notes_root / "docs/zh-CN/RELEASE_NOTES.md",
    )
    for document in documents:
        if not document.is_file():
            fail(f"release note is missing: {document.relative_to(notes_root).as_posix()}")
        text = document.read_text(encoding="utf-8")
        for asset in required_assets(surface):
            if asset not in text:
                fail(f"{document.name} does not explain release asset: {asset}")
        for required_phrase in ("Source code (zip)", "Source code (tar.gz)", "SHA256SUMS"):
            if required_phrase not in text:
                fail(f"{document.name} omits download guidance: {required_phrase}")

    with tempfile.TemporaryDirectory(prefix=f"home-edge-release-body-{surface}-") as temporary:
        temp = pathlib.Path(temporary)
        fixture = temp / "tagged-repo"
        create_tagged_fixture(fixture, renderer, documents, notes_root)
        for document in documents:
            relative = document.relative_to(notes_root).as_posix()
            output = temp / (relative.replace("/", "-") + ".rendered.md")
            run_renderer(fixture, relative, output, expect_ok=True)
            rendered = output.read_text(encoding="utf-8")
            assert_no_relative_links(rendered, relative)
            if f"https://github.com/{REPOSITORY}/blob/{VERSION}/" not in rendered:
                fail(f"{relative} did not produce a tag-pinned repository link")

        (fixture / "docs/RELEASE_NOTES.md").write_text(
            "[missing](missing.md)\n", encoding="utf-8", newline="\n"
        )
        git(fixture, "add", "docs/RELEASE_NOTES.md")
        git(fixture, "commit", "-qm", "broken release note link")
        output = temp / "invalid-link-output.md"
        run_renderer(
            fixture,
            "docs/RELEASE_NOTES.md",
            output,
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
