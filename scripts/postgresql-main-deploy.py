#!/usr/bin/env python3
"""Hash-bound apply and resume CLI for the postgresql-main provider instance."""

from __future__ import annotations

import argparse
import pathlib
import secrets
import sys

from postgresql_main.filesystem import SecureFilesystem
from postgresql_main.host import (
    ARTIFACT_PATHS,
    CONFIG_PATH,
    HostBackend,
    Provisioner,
    build_resume_plan,
    utc_now,
)
from postgresql_main.marker import MarkerStore
from postgresql_main.models import ProvisioningError
from postgresql_main.pki import OpenSslRunner, PkiManager, load_policy


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]
PKI_POLICY_PATH = REPO_ROOT / "deploy/postgresql/pki-policy.toml"


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Bounded PostgreSQL-main apply and resume path"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    apply = subparsers.add_parser("apply")
    apply.add_argument("--config", required=True, type=pathlib.Path)
    apply.add_argument("--confirm-plan-sha256", required=True)

    resume_plan = subparsers.add_parser("resume-plan")
    resume_plan.add_argument("--config", required=True, type=pathlib.Path)
    resume_plan.add_argument("--format", choices=("text", "json"), default="text")

    resume_apply = subparsers.add_parser("resume-apply")
    resume_apply.add_argument("--config", required=True, type=pathlib.Path)
    resume_apply.add_argument("--confirm-resume-sha256", required=True)
    return parser


def build_services() -> tuple[Provisioner, SecureFilesystem, HostBackend, MarkerStore]:
    filesystem = SecureFilesystem()
    backend = HostBackend()
    store = MarkerStore(filesystem, clock=utc_now)
    pki = PkiManager(
        filesystem,
        OpenSslRunner(),
        load_policy(PKI_POLICY_PATH),
        serial_source=lambda: secrets.randbits(158) + 1,
    )
    provisioner = Provisioner(
        filesystem=filesystem,
        backend=backend,
        marker_store=store,
        pki=pki,
        artifact_paths=ARTIFACT_PATHS,
    )
    return provisioner, filesystem, backend, store


def require_config_path(path: pathlib.Path) -> pathlib.Path:
    if path != CONFIG_PATH:
        raise ProvisioningError(
            "CONFIG_PATH_INVALID",
            f"Reale Konfiguration muss exakt {CONFIG_PATH} sein",
        )
    return path


def main(argv: list[str] | None = None) -> int:
    args = create_parser().parse_args(argv)
    try:
        config = require_config_path(args.config)
        provisioner, filesystem, backend, store = build_services()
        if args.command == "apply":
            marker = provisioner.apply(config, args.confirm_plan_sha256)
            print(f"PROVISIONING_COMPLETED operation_id={marker['operation_id']}")
        elif args.command == "resume-plan":
            resume = build_resume_plan(
                filesystem=filesystem,
                backend=backend,
                marker_store=store,
                pki=provisioner.pki,
                artifact_paths=ARTIFACT_PATHS,
            )
            print(resume.render_json() if args.format == "json" else resume.render_text(), end="")
            return 0 if resume.status == "RESUME_READY" else 4
        elif args.command == "resume-apply":
            resume = build_resume_plan(
                filesystem=filesystem,
                backend=backend,
                marker_store=store,
                pki=provisioner.pki,
                artifact_paths=ARTIFACT_PATHS,
            )
            marker = provisioner.resume(resume, args.confirm_resume_sha256)
            print(f"PROVISIONING_COMPLETED operation_id={marker['operation_id']}")
        return 0
    except ProvisioningError as exc:
        print(f"{exc.code}: {exc.message}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
