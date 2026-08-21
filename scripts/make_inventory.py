#!/usr/bin/env python3
"""Write a stable TSV inventory for a local file or directory."""

import argparse
import hashlib
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    parser.add_argument(
        "--sha256",
        action="store_true",
        help="Read each file and include its SHA-256 digest",
    )
    args = parser.parse_args()

    root = args.path.resolve()
    if not root.exists():
        parser.error(f"path does not exist: {root}")

    files = [root] if root.is_file() else sorted(
        path for path in root.rglob("*") if path.is_file()
    )

    columns = ["path", "bytes"]
    if args.sha256:
        columns.append("sha256")
    print("\t".join(columns))

    for path in files:
        relative = path.name if root.is_file() else path.relative_to(root).as_posix()
        values = [relative, str(path.stat().st_size)]
        if args.sha256:
            values.append(sha256(path))
        print("\t".join(values))


if __name__ == "__main__":
    main()
