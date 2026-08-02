"""Explicit controller database initialization command."""

from __future__ import annotations

import argparse
from pathlib import Path

from .controller.storage import init_database, schema_status


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="RALF-Controllerdatenbank verwalten")
    subparsers = parser.add_subparsers(dest="command", required=True)
    init_parser = subparsers.add_parser("init", help="Schema explizit initialisieren")
    init_parser.add_argument("--database", required=True, type=Path)
    args = parser.parse_args(argv)
    if args.command == "init":
        init_database(args.database)
        status = schema_status(args.database)
        print(f"Controllerdatenbank bereit: Schema {status['schema_version']}")
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
