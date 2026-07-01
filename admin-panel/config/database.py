from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from config.config import settings

# Local engine (SQLite) - stores users, Details, Integrations, Keys, Instances
local_connect_args = {}
if settings.DATABASE_URL.startswith("sqlite"):
    local_connect_args = {"check_same_thread": False}

engine = create_engine(
    settings.DATABASE_URL,
    connect_args=local_connect_args
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Identity engine (PostgreSQL central) - stores Companies, Branches, Devices (licenses), Modules
identity_connect_args = {}
if settings.IDENTITY_DATABASE_URL.startswith("sqlite"):
    identity_connect_args = {"check_same_thread": False}

identity_engine = create_engine(
    settings.IDENTITY_DATABASE_URL,
    connect_args=identity_connect_args
)
IdentitySessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=identity_engine)

Base = declarative_base()

# Dependency for local DB (SQLite)
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# Dependency for central ID/Licensing DB (PostgreSQL)
def get_identity_db():
    db = IdentitySessionLocal()
    try:
        yield db
    finally:
        db.close()
