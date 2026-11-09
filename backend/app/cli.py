"""Admin helpers.

    python -m app.cli create-admin <username> "<Full Name>"

Password is asked interactively (not stored in shell history).
"""

import getpass
import sys

from sqlalchemy import select

from app.core.database import SessionLocal
from app.core.security import hash_password
from app.models import User, UserRole


def create_admin(username: str, full_name: str) -> None:
    password = getpass.getpass("Password (min 6 chars): ")
    if len(password) < 6:
        sys.exit("Password too short.")
    if password != getpass.getpass("Confirm password: "):
        sys.exit("Passwords do not match.")
    with SessionLocal() as db:
        if db.execute(select(User).where(User.username == username)).scalar_one_or_none():
            sys.exit(f"User '{username}' already exists.")
        db.add(
            User(
                username=username,
                full_name=full_name,
                password_hash=hash_password(password),
                role=UserRole.admin,
            )
        )
        db.commit()
    print(f"Admin user '{username}' created.")


def bootstrap_admin() -> None:
    """Create the first admin from ADMIN_USERNAME / ADMIN_PASSWORD env vars, only
    when the users table is empty. Safe to run on every deploy."""
    from app.core.config import get_settings

    s = get_settings()
    if not s.admin_username or not s.admin_password:
        print("bootstrap-admin: ADMIN_USERNAME/ADMIN_PASSWORD not set, skipping.")
        return
    if len(s.admin_password) < 6:
        sys.exit("bootstrap-admin: ADMIN_PASSWORD must be at least 6 characters.")
    with SessionLocal() as db:
        if db.execute(select(User.id).limit(1)).first():
            print("bootstrap-admin: users already exist, nothing to do.")
            return
        db.add(
            User(
                username=s.admin_username,
                full_name=s.admin_full_name,
                password_hash=hash_password(s.admin_password),
                role=UserRole.admin,
            )
        )
        db.commit()
    print(f"bootstrap-admin: created admin '{s.admin_username}'.")


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "create-admin":
        create_admin(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 2 and sys.argv[1] == "bootstrap-admin":
        bootstrap_admin()
    else:
        print(__doc__)
