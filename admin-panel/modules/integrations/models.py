from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey, JSON
from sqlalchemy.orm import relationship
from datetime import datetime
from config.database import Base
from modules.companies.models import GUID

class ApiIntegration(Base):
    __tablename__ = "api_integrations"

    id = Column(Integer, primary_key=True, index=True)
    company_id = Column(GUID, ForeignKey("companies.Id"), nullable=False)
    api_type = Column(String, nullable=False) # whatsapp, fiscal, contract
    api_key = Column(String, nullable=True)
    api_secret = Column(String, nullable=True)
    webhook_url = Column(String, nullable=True)
    is_active = Column(Boolean, default=True)
    configuration = Column(JSON, nullable=True)
    last_tested_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    company = relationship("Company", back_populates="integrations")
