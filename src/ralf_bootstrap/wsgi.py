"""Production import target for Gunicorn."""

from .app import create_app
from .config import load_config

app = create_app(database_path=load_config().database_path)
