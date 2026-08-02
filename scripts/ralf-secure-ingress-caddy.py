#!/usr/bin/env python3
"""Validate and render the local RALF Caddy secure-ingress provider."""

from __future__ import annotations

import argparse
import dataclasses
import getpass
import ipaddress
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import tomllib
from typing import Any, Iterable


EXPECTED_CADDY_VERSION = "2.11.4"
FIXED_UPSTREAM = "127.0.0.1:8080"
TLS_MODE = "internal"
AUTHENTICATION_MODE = "Basic Auth with Argon2id"
IDENTITY_HEADER = "X-RALF-Authenticated-User"
REALM = "RALF Bootstrap"
MINIMUM_PASSWORD_LENGTH = 16

_FQDN_LABEL = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")
_USERNAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
_ARGON2ID = re.compile(
    r"^\$argon2id\$v=19\$m=[1-9][0-9]*,t=[1-9][0-9]*,p=[1-9][0-9]*"
    r"\$[A-Za-z0-9+/]+\$[A-Za-z0-9+/]+$"
)


class IngressError(RuntimeError):
    """Expected validation or rendering failure without secret-bearing detail."""


@dataclasses.dataclass(frozen=True)
class ProviderConfig:
    schema_version: int
    provider: str
    fqdn: str
    allowed_cidrs: tuple[str, ...]
    username: str


@dataclasses.dataclass(frozen=True)
class RenderOverrides:
    """Test-only rendering values; they are deliberately unreachable from the CLI."""

    https_port: int
    upstream_port: int
    bind_host: str = "127.0.0.1"
    disable_http_redirect: bool = True

    def __post_init__(self) -> None:
        for value, label in (
            (self.https_port, "HTTPS-Port"),
            (self.upstream_port, "Upstream-Port"),
        ):
            if isinstance(value, bool) or not isinstance(value, int) or not 1024 <= value <= 65535:
                raise IngressError(f"Ungültiger testinterner {label}")
        if self.bind_host != "127.0.0.1":
            raise IngressError("Testinterne Bindung muss 127.0.0.1 verwenden")

    @property
    def upstream(self) -> str:
        return f"127.0.0.1:{self.upstream_port}"


def _require_exact_keys(mapping: Any, expected: set[str], context: str) -> dict[str, Any]:
    if not isinstance(mapping, dict):
        raise IngressError(f"{context} muss eine TOML-Tabelle sein")
    actual = set(mapping)
    if actual != expected:
        unknown = sorted(actual - expected)
        missing = sorted(expected - actual)
        details: list[str] = []
        if unknown:
            details.append("unbekannt=" + ",".join(unknown))
        if missing:
            details.append("fehlt=" + ",".join(missing))
        raise IngressError(f"Ungültige Schlüssel in {context}: {'; '.join(details)}")
    return mapping


def validate_fqdn(value: Any) -> str:
    if not isinstance(value, str) or not value:
        raise IngressError("site.fqdn muss eine nicht leere Zeichenkette sein")
    try:
        value.encode("ascii")
    except UnicodeEncodeError as exc:
        raise IngressError("site.fqdn muss ein ASCII-Name sein") from exc
    if value != value.lower():
        raise IngressError("site.fqdn muss vollständig kleingeschrieben sein")
    if len(value) > 253:
        raise IngressError("site.fqdn ist länger als 253 Zeichen")
    if value.endswith("."):
        raise IngressError("site.fqdn darf keinen abschließenden Punkt besitzen")
    if value == "localhost" or value.startswith("*.") or "*" in value:
        raise IngressError("site.fqdn darf weder localhost noch ein Wildcard-Name sein")
    if "://" in value or "/" in value or ":" in value:
        raise IngressError("site.fqdn darf weder Schema, Pfad noch Port enthalten")
    try:
        ipaddress.ip_address(value)
    except ValueError:
        pass
    else:
        raise IngressError("site.fqdn darf keine IP-Adresse sein")
    labels = value.split(".")
    if len(labels) < 2:
        raise IngressError("site.fqdn muss aus mindestens zwei Labels bestehen")
    for label in labels:
        if not 1 <= len(label) <= 63 or _FQDN_LABEL.fullmatch(label) is None:
            raise IngressError("site.fqdn enthält ein ungültiges DNS-Label")
    return value


def validate_cidrs(value: Any) -> tuple[str, ...]:
    if not isinstance(value, list) or not value:
        raise IngressError("site.allowed_cidrs muss eine nicht leere Liste sein")
    result: list[str] = []
    for item in value:
        if not isinstance(item, str):
            raise IngressError("site.allowed_cidrs darf nur Zeichenketten enthalten")
        if item == "private_ranges" or "/" not in item:
            raise IngressError("Jeder Allowlist-Eintrag muss ein explizites CIDR sein")
        try:
            network = ipaddress.ip_network(item, strict=True)
        except ValueError as exc:
            raise IngressError("site.allowed_cidrs enthält ein ungültiges oder nicht kanonisches CIDR") from exc
        canonical = str(network)
        if item != canonical:
            raise IngressError("site.allowed_cidrs muss kanonische CIDR-Schreibweise verwenden")
        if network.prefixlen == 0:
            raise IngressError("Eine globale CIDR-Freigabe ist unzulässig")
        if network.network_address.is_multicast or network.network_address.is_unspecified:
            raise IngressError("Multicast- und unspecified-Netze sind unzulässig")
        if canonical in result:
            raise IngressError("Doppelte CIDR-Allowlist-Einträge sind unzulässig")
        result.append(canonical)
    return tuple(result)


def validate_username(value: Any) -> str:
    if not isinstance(value, str) or _USERNAME.fullmatch(value) is None:
        raise IngressError(
            "authentication.username muss 1 bis 64 ASCII-Zeichen besitzen, "
            "alphanumerisch beginnen und darf danach nur Punkt, Unterstrich oder Bindestrich verwenden"
        )
    return value


def load_provider_config(path: Path | str) -> ProviderConfig:
    config_path = Path(path)
    if not config_path.is_file() or config_path.is_symlink():
        raise IngressError("Provider-Konfiguration muss eine reguläre vorhandene Datei sein")
    try:
        data = tomllib.loads(config_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, tomllib.TOMLDecodeError) as exc:
        raise IngressError("Provider-Konfiguration konnte nicht als TOML gelesen werden") from exc
    root = _require_exact_keys(
        data,
        {"schema_version", "provider", "site", "authentication"},
        "Wurzel",
    )
    if type(root["schema_version"]) is not int or root["schema_version"] != 1:
        raise IngressError("schema_version muss exakt 1 sein")
    if root["provider"] != "caddy":
        raise IngressError("provider muss exakt caddy sein")
    site = _require_exact_keys(root["site"], {"fqdn", "allowed_cidrs"}, "site")
    authentication = _require_exact_keys(
        root["authentication"], {"username"}, "authentication"
    )
    return ProviderConfig(
        schema_version=1,
        provider="caddy",
        fqdn=validate_fqdn(site["fqdn"]),
        allowed_cidrs=validate_cidrs(site["allowed_cidrs"]),
        username=validate_username(authentication["username"]),
    )


def validate_password(password: Any) -> str:
    if not isinstance(password, str):
        raise IngressError("Kennwort muss eine Zeichenkette sein")
    if len(password) < MINIMUM_PASSWORD_LENGTH:
        raise IngressError(f"Kennwort muss mindestens {MINIMUM_PASSWORD_LENGTH} Zeichen besitzen")
    if "\x00" in password or "\n" in password or "\r" in password:
        raise IngressError("Kennwort darf weder NUL noch Zeilenumbrüche enthalten")
    return password


def validate_argon2id_hash(output: str) -> str:
    if not isinstance(output, str) or not output.endswith("\n"):
        raise IngressError("Caddy lieferte keine gültige einzeilige Argon2id-Ausgabe")
    if output.count("\n") != 1 or "\r" in output:
        raise IngressError("Caddy lieferte zusätzliche Hash-Ausgabe")
    value = output[:-1]
    if not value or value != value.strip() or _ARGON2ID.fullmatch(value) is None:
        raise IngressError("Caddy lieferte keinen gültigen Argon2id-Hash")
    return value


def _minimal_environment(**overrides: str) -> dict[str, str]:
    environment = {"LC_ALL": "C", "LANG": "C", "PATH": os.environ.get("PATH", "/usr/bin:/bin")}
    environment.update(overrides)
    return environment


def validate_caddy_binary(caddy: Path | str) -> Path:
    binary = Path(caddy)
    try:
        metadata = binary.stat()
    except OSError as exc:
        raise IngressError("Caddy-Binary ist nicht vorhanden") from exc
    if not stat.S_ISREG(metadata.st_mode) or not os.access(binary, os.X_OK):
        raise IngressError("Caddy-Binary muss eine ausführbare reguläre Datei sein")
    try:
        result = subprocess.run(
            [str(binary), "version"],
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
            env=_minimal_environment(),
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise IngressError("Caddy-Version konnte nicht geprüft werden") from exc
    version = result.stdout.strip()
    if result.returncode != 0 or not (
        version == f"v{EXPECTED_CADDY_VERSION}"
        or version.startswith(f"v{EXPECTED_CADDY_VERSION} ")
    ):
        raise IngressError(f"Caddy muss exakt Version {EXPECTED_CADDY_VERSION} besitzen")
    return binary


def hash_password(caddy: Path | str, password: str) -> str:
    secret = validate_password(password)
    binary = validate_caddy_binary(caddy)
    try:
        result = subprocess.run(
            [str(binary), "hash-password", "--algorithm", "argon2id"],
            input=secret + "\n",
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
            env=_minimal_environment(),
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise IngressError("Caddy-Kennworthashing ist fehlgeschlagen") from exc
    if result.returncode != 0:
        raise IngressError("Caddy-Kennworthashing ist fehlgeschlagen")
    return validate_argon2id_hash(result.stdout)


def render_caddyfile(
    config: ProviderConfig,
    password_hash: str,
    overrides: RenderOverrides | None = None,
) -> str:
    hashed_password = validate_argon2id_hash(password_hash + "\n")
    site_address = config.fqdn
    upstream = FIXED_UPSTREAM
    global_options = ["\tadmin off", "\tpersist_config off", "\tskip_install_trust"]
    site_options: list[str] = []
    if overrides is not None:
        site_address = f"https://{config.fqdn}:{overrides.https_port}"
        upstream = overrides.upstream
        site_options.append(f"\tbind {overrides.bind_host}")
        if overrides.disable_http_redirect:
            global_options.append("\tauto_https disable_redirects")
    cidrs = " ".join(config.allowed_cidrs)
    lines = ["{", *global_options, "}", "", f"{site_address} {{", *site_options]
    if site_options:
        lines.append("")
    lines.extend(
        [
            "\ttls internal",
            "",
            "\troute {",
            f"\t\t@outside not remote_ip {cidrs}",
            "\t\trespond @outside 403",
            "",
            "\t\trequest_header -X-RALF-*",
            "",
            f'\t\tbasic_auth argon2id "{REALM}" {{',
            f"\t\t\t{config.username} {hashed_password}",
            "\t\t}",
            "",
            f"\t\treverse_proxy {upstream} {{",
            "\t\t\theader_up -Authorization",
            "\t\t\theader_up -Proxy-Authorization",
            "\t\t\theader_up -Forwarded",
            "\t\t\theader_up -X-Real-IP",
            f"\t\t\theader_up {IDENTITY_HEADER} {{http.auth.user.id}}",
            "\t\t}",
            "\t}",
            "}",
            "",
        ]
    )
    rendered = "\n".join(lines)
    validate_rendered_contract(rendered, config, hashed_password, overrides)
    return rendered


def validate_rendered_contract(
    rendered: str,
    config: ProviderConfig,
    password_hash: str,
    overrides: RenderOverrides | None = None,
) -> None:
    expected_upstream = FIXED_UPSTREAM if overrides is None else overrides.upstream
    required_once = (
        "admin off",
        "persist_config off",
        "skip_install_trust",
        "tls internal",
        "remote_ip",
        'basic_auth argon2id "RALF Bootstrap"',
        f"reverse_proxy {expected_upstream}",
        "header_up -Authorization",
        "header_up -Proxy-Authorization",
        "header_up -Forwarded",
        "header_up -X-Real-IP",
        "request_header -X-RALF-*",
        f"header_up {IDENTITY_HEADER} {{http.auth.user.id}}",
    )
    for item in required_once:
        if rendered.count(item) != 1:
            raise IngressError(f"Caddyfile-Vertrag verletzt: {item}")
    directive_expectations = {
        "admin": "off",
        "persist_config": "off",
        "skip_install_trust": "",
    }
    for directive, value in directive_expectations.items():
        matches = re.findall(
            rf"(?m)^[ \t]*{re.escape(directive)}(?:[ \t]+([^ \t\r\n]+))?[ \t]*$",
            rendered,
        )
        observed = [match or "" for match in matches]
        if observed != [value]:
            raise IngressError(f"Caddyfile enthält eine unerwartete {directive}-Vorgabe")
    if rendered.count(password_hash) != 1:
        raise IngressError("Caddyfile muss exakt einen Argon2id-Hash enthalten")
    if rendered.count(f"\n{config.fqdn} {{") != (1 if overrides is None else 0):
        raise IngressError("Caddyfile muss exakt einen expliziten Site-Block enthalten")
    if f"@outside not remote_ip {' '.join(config.allowed_cidrs)}" not in rendered:
        raise IngressError("Caddyfile enthält nicht die exakte CIDR-Allowlist")
    forbidden = (
        "0.0.0.0",
        "private_ranges",
        "client_ip",
        "trusted_proxies",
        "tls_insecure_skip_verify",
        "on_demand_tls",
        "acme_dns",
        "forward_auth",
        "localhost:8080",
        "{$",
        "\nimport ",
        "$2a$",
        "$2b$",
        "$2y$",
    )
    lowered = rendered.lower()
    for item in forbidden:
        if item.lower() in lowered:
            raise IngressError(f"Verbotener Caddyfile-Inhalt: {item}")
    if overrides is None:
        if "auto_https" in rendered or "\tbind " in rendered:
            raise IngressError("Testinterne Optionen dürfen nicht in die Produktiv-Caddyfile gelangen")
        if rendered.count("\n" + config.fqdn + " {") != 1:
            raise IngressError("Produktiv-Caddyfile muss den bestätigten FQDN exakt verwenden")
    else:
        expected_site = f"\nhttps://{config.fqdn}:{overrides.https_port} {{"
        if rendered.count(expected_site) != 1 or rendered.count("\tbind 127.0.0.1") != 1:
            raise IngressError("Test-Caddyfile enthält keine isolierte Loopback-Bindung")


def _walk(value: Any) -> Iterable[dict[str, Any]]:
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from _walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from _walk(child)


def validate_adapted_config(
    adapted: dict[str, Any],
    config: ProviderConfig,
    password_hash: str,
    overrides: RenderOverrides | None = None,
) -> None:
    admin = adapted.get("admin")
    if admin != {"disabled": True, "config": {"persist": False}}:
        raise IngressError("Adaptierte Konfiguration deaktiviert Admin/Persistenz nicht exakt")
    apps = adapted.get("apps")
    if not isinstance(apps, dict) or set(apps) != {"http", "pki", "tls"}:
        raise IngressError("Adaptierte Konfiguration enthält unerwartete Apps")
    servers = apps.get("http", {}).get("servers", {})
    if not isinstance(servers, dict) or len(servers) != 1:
        raise IngressError("Adaptierte Konfiguration muss exakt einen HTTP-Server besitzen")
    server = next(iter(servers.values()))
    expected_listener = ":443" if overrides is None else f"127.0.0.1:{overrides.https_port}"
    if server.get("listen") != [expected_listener]:
        raise IngressError("Adaptierte Konfiguration enthält einen unerwarteten Listener")
    nodes = list(_walk(adapted))
    hosts = [node["host"] for node in nodes if "host" in node]
    if hosts != [[config.fqdn]]:
        raise IngressError("Adaptierte Konfiguration enthält nicht exakt einen Hostmatcher")
    remote_ranges = [
        node["remote_ip"].get("ranges")
        for node in nodes
        if isinstance(node.get("remote_ip"), dict)
    ]
    if remote_ranges != [list(config.allowed_cidrs)]:
        raise IngressError("Adaptierte Konfiguration enthält nicht die exakte CIDR-Allowlist")
    static_responses = [node for node in nodes if node.get("handler") == "static_response"]
    if len(static_responses) != 1 or static_responses[0].get("status_code") != 403:
        raise IngressError("Adaptierte Konfiguration enthält nicht die vorgesehene 403-Antwort")
    authentications = [node for node in nodes if node.get("handler") == "authentication"]
    if len(authentications) != 1:
        raise IngressError("Adaptierte Konfiguration enthält nicht exakt einen Authentifizierer")
    basic = authentications[0].get("providers", {}).get("http_basic")
    if not isinstance(basic, dict):
        raise IngressError("Adaptierte Konfiguration verwendet nicht HTTP Basic Auth")
    if basic.get("hash") != {"algorithm": "argon2id"} or basic.get("realm") != REALM:
        raise IngressError("Adaptierte Konfiguration verwendet nicht den Argon2id-Vertrag")
    if basic.get("accounts") != [{"password": password_hash, "username": config.username}]:
        raise IngressError("Adaptierte Konfiguration enthält unerwartete Authentifizierungsdaten")
    proxies = [node for node in nodes if node.get("handler") == "reverse_proxy"]
    expected_upstream = FIXED_UPSTREAM if overrides is None else overrides.upstream
    if len(proxies) != 1 or proxies[0].get("upstreams") != [{"dial": expected_upstream}]:
        raise IngressError("Adaptierte Konfiguration enthält nicht exakt den Loopback-Upstream")
    request_headers = proxies[0].get("headers", {}).get("request", {})
    expected_delete = {
        "authorization",
        "proxy-authorization",
        "forwarded",
        "x-real-ip",
    }
    observed_delete = {value.lower() for value in request_headers.get("delete", [])}
    if observed_delete != expected_delete:
        raise IngressError("Adaptierte Konfiguration bereinigt Header nicht exakt")
    header_set = {key.lower(): value for key, value in request_headers.get("set", {}).items()}
    if header_set != {IDENTITY_HEADER.lower(): ["{http.auth.user.id}"]}:
        raise IngressError("Adaptierte Konfiguration setzt den Identitätsheader nicht exakt")
    preclean_handlers = [node for node in nodes if node.get("handler") == "headers"]
    if len(preclean_handlers) != 1:
        raise IngressError("Adaptierte Konfiguration bereinigt Identitätsheader nicht vorab")
    preclean_request = preclean_handlers[0].get("request", {})
    if preclean_request.get("delete") != ["X-RALF-*"] or preclean_request.get("set"):
        raise IngressError("Adaptierte Konfiguration bereinigt X-RALF-Header nicht exakt")
    pki_local = apps.get("pki", {}).get("certificate_authorities", {}).get("local")
    if pki_local != {"install_trust": False}:
        raise IngressError("Adaptierte Konfiguration darf den Trust-Store nicht verändern")
    policies = apps.get("tls", {}).get("automation", {}).get("policies")
    if policies != [{"subjects": [config.fqdn], "issuers": [{"module": "internal"}]}]:
        raise IngressError("Adaptierte Konfiguration verwendet nicht ausschließlich internen TLS-Issuer")
    allowed_handlers = {
        "subroute",
        "static_response",
        "headers",
        "authentication",
        "reverse_proxy",
    }
    handlers = {node["handler"] for node in nodes if "handler" in node}
    if not handlers <= allowed_handlers:
        raise IngressError("Adaptierte Konfiguration enthält unerwartete Handler")


def validate_with_caddy(
    caddy: Path | str,
    caddyfile: Path | str,
    config: ProviderConfig,
    password_hash: str,
    overrides: RenderOverrides | None = None,
) -> dict[str, Any]:
    binary = validate_caddy_binary(caddy)
    path = Path(caddyfile)
    with tempfile.TemporaryDirectory(prefix="ralf-caddy-validate-") as runtime:
        runtime_path = Path(runtime)
        environment = _minimal_environment(
            HOME=str(runtime_path / "home"),
            XDG_DATA_HOME=str(runtime_path / "data"),
            XDG_CONFIG_HOME=str(runtime_path / "config"),
        )
        commands = (
            [str(binary), "validate", "--config", str(path), "--adapter", "caddyfile"],
            [str(binary), "adapt", "--config", str(path), "--adapter", "caddyfile", "--pretty"],
        )
        results: list[subprocess.CompletedProcess[str]] = []
        for command in commands:
            try:
                result = subprocess.run(
                    command,
                    check=False,
                    capture_output=True,
                    text=True,
                    timeout=30,
                    env=environment,
                )
            except (OSError, subprocess.SubprocessError) as exc:
                raise IngressError("Caddy-Konfigurationsprüfung ist fehlgeschlagen") from exc
            if result.returncode != 0:
                raise IngressError("Caddy-Konfigurationsprüfung ist fehlgeschlagen")
            results.append(result)
        try:
            adapted = json.loads(results[1].stdout)
        except (json.JSONDecodeError, TypeError) as exc:
            raise IngressError("Caddy adapt lieferte keine gültige JSON-Konfiguration") from exc
    if not isinstance(adapted, dict):
        raise IngressError("Caddy adapt lieferte keine JSON-Objektkonfiguration")
    validate_adapted_config(adapted, config, password_hash, overrides)
    return adapted


def write_validated_caddyfile(
    config: ProviderConfig,
    caddy: Path | str,
    output: Path | str,
    password: str,
) -> Path:
    binary = validate_caddy_binary(caddy)
    output_path = Path(output)
    if str(output_path) == "-":
        raise IngressError("Ausgabe auf stdout ist unzulässig")
    parent = output_path.parent
    if not parent.is_dir():
        raise IngressError("Ausgabe-Elternverzeichnis muss bereits vorhanden sein")
    try:
        output_path.lstat()
    except FileNotFoundError:
        pass
    except OSError as exc:
        raise IngressError("Ausgabepfad konnte nicht geprüft werden") from exc
    else:
        raise IngressError("Ausgabepfad darf noch nicht existieren")
    password_hash = hash_password(binary, password)
    rendered = render_caddyfile(config, password_hash)
    descriptor, temporary_name = tempfile.mkstemp(prefix=".ralf-caddy.", dir=parent)
    temporary_path = Path(temporary_name)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
            descriptor = -1
            stream.write(rendered)
            stream.flush()
            os.fsync(stream.fileno())
        validate_with_caddy(binary, temporary_path, config, password_hash)
        try:
            os.link(temporary_path, output_path)
        except FileExistsError as exc:
            raise IngressError("Ausgabepfad wurde während der Prüfung angelegt") from exc
        temporary_path.unlink()
        if stat.S_IMODE(output_path.stat().st_mode) != 0o600:
            raise IngressError("Erzeugte Caddyfile besitzt nicht Modus 0600")
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        temporary_path.unlink(missing_ok=True)
    return output_path


def read_password_from_stdin() -> str:
    raw = sys.stdin.buffer.read(4097)
    if len(raw) > 4096:
        raise IngressError("Kennworteingabe ist zu lang")
    try:
        value = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise IngressError("Kennworteingabe ist kein gültiges UTF-8") from exc
    if value.endswith("\n"):
        value = value[:-1]
    return validate_password(value)


def print_plan(config: ProviderConfig) -> None:
    print("RALF secure-ingress Caddy-Plan")
    print(f"Provider: {config.provider}")
    print(f"FQDN: {config.fqdn}")
    print("CIDR-Allowlist: " + ", ".join(config.allowed_cidrs))
    print(f"Authentifizierungsbenutzer: {config.username}")
    print(f"TLS-Modus: {TLS_MODE}")
    print(f"Upstream: {FIXED_UPSTREAM}")
    print("Caddy-Admin-API: deaktiviert")
    print(
        "Headerbereinigung: Authorization, Proxy-Authorization, Forwarded, "
        "X-Real-IP und clientseitige X-RALF-*"
    )
    print("Kennworthash: noch nicht erzeugt")
    print("Reale Installation und LAN-Freigabe: nicht Bestandteil dieses Plans")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    plan = subparsers.add_parser("plan", help="nicht geheime Providerdaten read-only prüfen")
    plan.add_argument("--config", required=True, type=Path)
    render = subparsers.add_parser("render", help="validierte geschützte Caddyfile erzeugen")
    render.add_argument("--config", required=True, type=Path)
    render.add_argument("--caddy", required=True, type=Path)
    render.add_argument("--output", required=True, type=Path)
    render.add_argument("--password-stdin", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        config = load_provider_config(args.config)
        if args.command == "plan":
            print_plan(config)
            return 0
        password = read_password_from_stdin() if args.password_stdin else validate_password(
            getpass.getpass("Caddy-Basic-Auth-Kennwort: ")
        )
        output = write_validated_caddyfile(config, args.caddy, args.output, password)
        print(f"Validierte Caddyfile erzeugt: {output}")
        return 0
    except IngressError as exc:
        print(f"Fehler: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
