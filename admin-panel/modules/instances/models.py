from sqlalchemy import Column, Integer, String, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from datetime import datetime
from config.database import Base
from modules.companies.models import GUID

class Instance(Base):
    __tablename__ = "instances"

    id = Column(Integer, primary_key=True, index=True)
    company_id = Column(GUID, ForeignKey("companies.Id"), nullable=False)
    instance_type = Column(String, nullable=False) # web, mobile
    instance_name = Column(String, nullable=False)
    status = Column(String, default="offline") # online, offline, error
    last_sync = Column(DateTime, nullable=True)
    version = Column(String, default="1.0.0")
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    company = relationship("Company", back_populates="instances")
