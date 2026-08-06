#!/usr/bin/env python3
"""CLI entrypoint for the bounded postgresql-main guest provisioner."""

from postgresql_main.guest import main


if __name__ == "__main__":
    raise SystemExit(main())
