import uuid
from sqlalchemy import Column, Integer, String, Boolean, DateTime
from datetime import datetime
from config.database import Base
from modules.companies.models import GUID

class User(Base):
    __tablename__ = "admin_users"

    # Map to central coliseu_identity admin_users columns
    id = Column("Id", GUID, primary_key=True, index=True, default=uuid.uuid4)
    email = Column("Email", String(255), unique=True, index=True, nullable=False)
    password_hash = Column("PasswordHash", String(255), nullable=False)
    full_name = Column("Name", String(200), nullable=True)
    is_active = Column("IsActive", Boolean, default=True)
    role = Column("Role", Integer, default=0) # 0 = SuperAdmin
    created_at = Column("CreatedAt", DateTime, default=datetime.utcnow)
