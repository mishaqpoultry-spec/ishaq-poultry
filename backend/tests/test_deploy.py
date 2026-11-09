from app.core.config import Settings
from app.models import User, UserRole


def test_database_url_accepts_neon_and_render_formats():
    neon = "postgresql://u:p@ep-x.aws.neon.tech/neondb?sslmode=require"
    assert Settings(database_url=neon).database_url == "postgresql+psycopg://u:p@ep-x.aws.neon.tech/neondb?sslmode=require"
    assert Settings(database_url="postgres://u:p@h/db").database_url == "postgresql+psycopg://u:p@h/db"
    already = "postgresql+psycopg://u:p@h/db"
    assert Settings(database_url=already).database_url == already


def test_bootstrap_admin_only_when_no_users(db, monkeypatch):
    import app.cli as cli
    from app.core.config import get_settings

    monkeypatch.setattr(cli, "SessionLocal", lambda: _NoClose(db))
    s = get_settings()
    monkeypatch.setattr(s, "admin_username", "owner1")
    monkeypatch.setattr(s, "admin_password", "secret123")

    cli.bootstrap_admin()
    users = db.query(User).all()
    assert [(u.username, u.role) for u in users] == [("owner1", UserRole.admin)]

    monkeypatch.setattr(s, "admin_username", "someone_else")
    cli.bootstrap_admin()  # users exist -> no change
    assert db.query(User).count() == 1


class _NoClose:
    """Lets the CLI's `with SessionLocal() as db` reuse the test session."""

    def __init__(self, db):
        self.db = db

    def __enter__(self):
        return self.db

    def __exit__(self, *a):
        return False
