"""Symlink-safe, durable filesystem primitives for security-relevant files."""

from __future__ import annotations

import contextlib
import json
import os
import pathlib
import stat
import tempfile
from collections.abc import Iterator

from .models import ProvisioningError, canonical_json


class SecureFilesystem:
    """Map absolute logical paths into an optional injected test root."""

    def __init__(self, physical_root: pathlib.Path = pathlib.Path("/")) -> None:
        self.physical_root = physical_root.resolve()

    def path(self, logical: pathlib.Path | str) -> pathlib.Path:
        value = pathlib.Path(logical)
        if not value.is_absolute():
            raise ProvisioningError("PATH_INVALID", f"Pfad ist nicht absolut: {value}")
        relative = value.relative_to("/")
        candidate = self.physical_root / relative
        if self.physical_root != pathlib.Path("/"):
            return candidate
        return value

    def reject_symlink_components(self, logical: pathlib.Path | str) -> pathlib.Path:
        target = self.path(logical)
        try:
            relative = target.relative_to(self.physical_root)
        except ValueError as exc:
            raise ProvisioningError("PATH_OUTSIDE_ROOT", str(logical)) from exc
        current = self.physical_root
        for part in relative.parts:
            current /= part
            try:
                info = current.lstat()
            except FileNotFoundError:
                continue
            if stat.S_ISLNK(info.st_mode):
                raise ProvisioningError("SYMLINK_CONFLICT", f"Symlink unzulässig: {logical}")
        return target

    def validate(
        self,
        logical: pathlib.Path | str,
        *,
        kind: str,
        mode: int,
        uid: int = 0,
        gid: int = 0,
        require_nonempty: bool = False,
    ) -> os.stat_result:
        target = self.reject_symlink_components(logical)
        try:
            info = target.lstat()
        except FileNotFoundError as exc:
            raise ProvisioningError("PATH_MISSING", f"Pfad fehlt: {logical}") from exc
        expected_type = stat.S_ISDIR if kind == "directory" else stat.S_ISREG
        if not expected_type(info.st_mode):
            raise ProvisioningError("PATH_TYPE_CONFLICT", f"Falscher Typ: {logical}")
        if stat.S_IMODE(info.st_mode) != mode or info.st_uid != uid or info.st_gid != gid:
            raise ProvisioningError("PATH_METADATA_CONFLICT", f"Unsichere Metadaten: {logical}")
        if require_nonempty and info.st_size == 0:
            raise ProvisioningError("EMPTY_SECRET", f"Datei ist leer: {logical}")
        return info

    def ensure_directory(
        self,
        logical: pathlib.Path | str,
        *,
        mode: int = 0o700,
        uid: int = 0,
        gid: int = 0,
    ) -> pathlib.Path:
        target = self.reject_symlink_components(logical)
        if target.exists():
            self.validate(logical, kind="directory", mode=mode, uid=uid, gid=gid)
            return target
        parent = target.parent
        if not parent.exists():
            raise ProvisioningError("PARENT_MISSING", f"Elternpfad fehlt: {parent}")
        parent_fd = os.open(parent, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
        try:
            os.mkdir(target.name, mode=mode, dir_fd=parent_fd)
            os.chown(target.name, uid, gid, dir_fd=parent_fd, follow_symlinks=False)
            os.fsync(parent_fd)
        finally:
            os.close(parent_fd)
        self.validate(logical, kind="directory", mode=mode, uid=uid, gid=gid)
        return target

    def exclusive_bytes(
        self,
        logical: pathlib.Path | str,
        data: bytes,
        *,
        mode: int = 0o600,
        uid: int = 0,
        gid: int = 0,
    ) -> pathlib.Path:
        target = self.reject_symlink_components(logical)
        parent_fd = os.open(target.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        try:
            fd = os.open(target.name, flags, mode, dir_fd=parent_fd)
            try:
                os.fchmod(fd, mode)
                os.fchown(fd, uid, gid)
                view = memoryview(data)
                while view:
                    written = os.write(fd, view)
                    view = view[written:]
                os.fsync(fd)
            finally:
                os.close(fd)
            os.fsync(parent_fd)
        finally:
            os.close(parent_fd)
        self.validate(logical, kind="file", mode=mode, uid=uid, gid=gid)
        return target

    def atomic_bytes(
        self,
        logical: pathlib.Path | str,
        data: bytes,
        *,
        mode: int = 0o600,
        uid: int = 0,
        gid: int = 0,
    ) -> pathlib.Path:
        target = self.reject_symlink_components(logical)
        parent = target.parent
        parent_fd = os.open(parent, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
        fd, temporary = tempfile.mkstemp(prefix=f".{target.name}.", dir=parent)
        temporary_path = pathlib.Path(temporary)
        try:
            os.fchmod(fd, mode)
            os.fchown(fd, uid, gid)
            view = memoryview(data)
            while view:
                written = os.write(fd, view)
                view = view[written:]
            os.fsync(fd)
            os.close(fd)
            fd = -1
            if target.exists() and target.is_symlink():
                raise ProvisioningError("SYMLINK_CONFLICT", f"Symlink unzulässig: {logical}")
            os.replace(temporary_path.name, target.name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
            os.fsync(parent_fd)
        finally:
            if fd >= 0:
                os.close(fd)
            with contextlib.suppress(FileNotFoundError):
                temporary_path.unlink()
            os.close(parent_fd)
        self.validate(logical, kind="file", mode=mode, uid=uid, gid=gid)
        return target

    def atomic_json(self, logical: pathlib.Path | str, value: object) -> pathlib.Path:
        return self.atomic_bytes(logical, canonical_json(value) + b"\n")

    def exclusive_json(self, logical: pathlib.Path | str, value: object) -> pathlib.Path:
        return self.exclusive_bytes(logical, canonical_json(value) + b"\n")

    def read_json(self, logical: pathlib.Path | str) -> object:
        data = self.read_bytes(logical, maximum=2_000_000)
        try:
            return json.loads(data)
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise ProvisioningError("JSON_INVALID", f"Ungültiges JSON: {logical}") from exc

    def read_bytes(self, logical: pathlib.Path | str, *, maximum: int = 2_000_000) -> bytes:
        target = self.reject_symlink_components(logical)
        flags = os.O_RDONLY | os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        fd = os.open(target, flags)
        try:
            chunks: list[bytes] = []
            total = 0
            while True:
                chunk = os.read(fd, 65_536)
                if not chunk:
                    break
                total += len(chunk)
                if total > maximum:
                    raise ProvisioningError("FILE_TOO_LARGE", f"Datei zu groß: {logical}")
                chunks.append(chunk)
        finally:
            os.close(fd)
        return b"".join(chunks)

    @contextlib.contextmanager
    def exclusive_lock(self, logical: pathlib.Path | str) -> Iterator[int]:
        import fcntl

        target = self.reject_symlink_components(logical)
        parent = target.parent
        parent.mkdir(parents=True, exist_ok=True) if self.physical_root != pathlib.Path("/") else None
        if target.exists():
            info = target.lstat()
            if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o600:
                raise ProvisioningError("LOCK_CONFLICT", "Sperrpfad besitzt falsche Metadaten")
            if self.physical_root == pathlib.Path("/") and (info.st_uid != 0 or info.st_gid != 0):
                raise ProvisioningError("LOCK_CONFLICT", "Sperrpfad gehört nicht root:root")
        flags = os.O_RDWR | os.O_CREAT | os.O_CLOEXEC
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        fd = os.open(target, flags, 0o600)
        try:
            os.fchmod(fd, 0o600)
            if os.geteuid() == 0:
                os.fchown(fd, 0, 0)
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as exc:
                raise ProvisioningError(
                    "PROVISIONING_ALREADY_RUNNING", "Provisionierung läuft bereits"
                ) from exc
            yield fd
        finally:
            with contextlib.suppress(OSError):
                fcntl.flock(fd, fcntl.LOCK_UN)
            os.close(fd)
