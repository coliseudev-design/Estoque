from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from datetime import datetime
from config.database import Base
from modules.companies.models import GUID

class ApiKey(Base):
    __tablename__ = "api_keys"

    id = Column(Integer, primary_key=True, index=True)
    company_id = Column(GUID, ForeignKey("companies.Id"), nullable=False)
    key = Column(String, unique=True, index=True, nullable=False)
    secret = Column(String, unique=True, nullable=False)
    name = Column(String, default="Padrão")
    is_active = Column(Boolean, default=True)
    last_used_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    company = relationship("Company", back_populates="api_keys")
