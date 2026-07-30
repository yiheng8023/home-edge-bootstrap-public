#!/usr/bin/env python3
"""Render repository Markdown as a tag-pinned GitHub Release body."""

from __future__ import annotations

import argparse
import pathlib
import posixpath
import re
import subprocess
import urllib.parse


REPOSITORY_RE = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")
VERSION_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")
LINK_RE = re.compile(r"(?P<prefix>!?\[[^\]\r\n]*\]\()(?P<target>[^)\s]+)(?P<suffix>\))")
EXTERNAL_SCHEMES = ("http://", "https://", "mailto:")


def fail(message: str) -> None:
    raise SystemExit(f"render-release-body: ERROR {message}")


def safe_repository_path(value: str) -> pathlib.PurePosixPath:
    if not value or "\\" in value or value.startswith("/"):
        fail(f"unsafe repository path: {value}")
    normalized = posixpath.normpath(value)
    if normalized in (".", "..") or normalized.startswith("../"):
        fail(f"unsafe repository path: {value}")
    return pathlib.PurePosixPath(normalized)


def run_git(root: pathlib.Path, arguments: list[str], *, text: bool = True):
    result = subprocess.run(
        ["git", "-C", str(root), *arguments],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=text,
        encoding="utf-8" if text else None,
    )
    if result.returncode:
        detail = result.stderr.strip() if text else result.stderr.decode("utf-8", "replace").strip()
        fail(f"Git operation failed ({' '.join(arguments)}): {detail}")
    return result.stdout


def require_git_path(root: pathlib.Path, revision: str, path: str) -> None:
    result = subprocess.run(
        ["git", "-C", str(root), "cat-file", "-e", f"{revision}:{path}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
    )
    if result.returncode:
        fail(f"repository link target is absent from {revision}: {path}")


def rewrite_target(
    target: str,
    *,
    source_relative: pathlib.PurePosixPath,
    root: pathlib.Path,
    repository: str,
    version: str,
    link_revision: str,
) -> str:
    lower = target.lower()
    if target.startswith("#") or lower.startswith(EXTERNAL_SCHEMES):
        return target
    if target.startswith("/") or target.startswith("\\") or "\\" in target:
        fail(f"unsupported repository link: {target}")

    path_and_query, separator, fragment = target.partition("#")
    path_part, query_separator, query = path_and_query.partition("?")
    if not path_part:
        return target

    resolved = posixpath.normpath(posixpath.join(source_relative.parent.as_posix(), path_part))
    if resolved == ".." or resolved.startswith("../") or resolved.startswith("/"):
        fail(f"repository link escapes the checkout: {target}")
    require_git_path(root, link_revision, resolved)

    encoded_path = "/".join(urllib.parse.quote(part, safe="") for part in resolved.split("/"))
    rendered = (
        f"https://github.com/{repository}/blob/{urllib.parse.quote(version, safe='')}/{encoded_path}"
    )
    if query_separator:
        rendered += "?" + query
    if separator:
        rendered += "#" + fragment
    return rendered


def render(
    text: str,
    *,
    source_relative: pathlib.PurePosixPath,
    root: pathlib.Path,
    repository: str,
    version: str,
    link_revision: str,
) -> str:
    def replace(match: re.Match[str]) -> str:
        target = rewrite_target(
            match.group("target"),
            source_relative=source_relative,
            root=root,
            repository=repository,
            version=version,
            link_revision=link_revision,
        )
        return f"{match.group('prefix')}{target}{match.group('suffix')}"

    return LINK_RE.sub(replace, text).replace("\r\n", "\n").replace("\r", "\n").rstrip("\n") + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert repository-relative Markdown links to tag-pinned GitHub URLs."
    )
    parser.add_argument("--repository", required=True, help="GitHub OWNER/REPOSITORY")
    parser.add_argument("--version", required=True, help="Git tag used by the Release")
    parser.add_argument("--source", required=True, help="repository-relative Markdown source path")
    parser.add_argument(
        "--source-ref",
        help="Git revision containing the body source; defaults to --version",
    )
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--repo-root", type=pathlib.Path, default=pathlib.Path.cwd())
    arguments = parser.parse_args()

    if not REPOSITORY_RE.fullmatch(arguments.repository):
        fail("--repository must be OWNER/REPOSITORY")
    if not VERSION_RE.fullmatch(arguments.version):
        fail("--version is not a safe Git tag")

    root = arguments.repo_root.resolve()
    output = arguments.output if arguments.output.is_absolute() else root / arguments.output
    source_relative = safe_repository_path(arguments.source)
    source_ref = arguments.source_ref or arguments.version
    link_revision = arguments.version
    run_git(root, ["rev-parse", "--verify", f"{source_ref}^{{commit}}"])
    run_git(root, ["rev-parse", "--verify", f"{link_revision}^{{commit}}"])
    require_git_path(root, source_ref, source_relative.as_posix())
    try:
        output.resolve().relative_to(root)
    except ValueError:
        pass
    else:
        fail("output must be outside the repository checkout")
    if output.exists():
        fail("output already exists")

    source_bytes = run_git(
        root,
        ["show", f"{source_ref}:{source_relative.as_posix()}"],
        text=False,
    )
    rendered = render(
        source_bytes.decode("utf-8", "strict"),
        source_relative=source_relative,
        root=root,
        repository=arguments.repository,
        version=arguments.version,
        link_revision=link_revision,
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write(rendered)
    print(f"release_body_path={output}")
    print("release_body_state=ready")


if __name__ == "__main__":
    main()
