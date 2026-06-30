from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, JSON
from sqlalchemy.orm import relationship
from datetime import datetime
from config.database import Base

class License(Base):
    __tablename__ = "licenses"

    id = Column(Integer, primary_key=True, index=True)
    company_id = Column(Integer, ForeignKey("companies.id"), nullable=False)
    license_key = Column(String, unique=True, index=True, nullable=False)
    product_type = Column(String, default="coliseu_speed") # coliseu_speed, coliseu_crm
    status = Column(String, default="inactive") # active, inactive, expired, suspended
    activation_date = Column(DateTime, nullable=True)
    expiration_date = Column(DateTime, nullable=True)
    max_users = Column(Integer, default=5)
    max_branches = Column(Integer, default=1)
    features = Column(JSON, nullable=True) # JSON list of enabled modules
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    company = relationship("Company", back_populates="licenses")
