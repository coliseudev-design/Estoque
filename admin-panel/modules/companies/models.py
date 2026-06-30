from sqlalchemy import Column, Integer, String, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from datetime import datetime
from config.database import Base

class Company(Base):
    __tablename__ = "companies"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    fantasy_name = Column(String, nullable=True)
    cnpj = Column(String, unique=True, index=True, nullable=False)
    email = Column(String, nullable=False)
    phone = Column(String, nullable=True)
    logo_url = Column(String, nullable=True)
    status = Column(String, default="active") # active, inactive, suspended
    app_type = Column(String, default="both") # mobile, web, both
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    details = relationship("CompanyDetails", uselist=False, back_populates="company", cascade="all, delete-orphan")
    licenses = relationship("License", back_populates="company", cascade="all, delete-orphan")
    integrations = relationship("ApiIntegration", back_populates="company", cascade="all, delete-orphan")
    instances = relationship("Instance", back_populates="company", cascade="all, delete-orphan")
    api_keys = relationship("ApiKey", back_populates="company", cascade="all, delete-orphan")

class CompanyDetails(Base):
    __tablename__ = "company_details"

    id = Column(Integer, primary_key=True, index=True)
    company_id = Column(Integer, ForeignKey("companies.id"), nullable=False)
    state_registration = Column(String, nullable=True)
    municipal_registration = Column(String, nullable=True)
    address = Column(String, nullable=True)
    city = Column(String, nullable=True)
    state = Column(String, nullable=True)
    zip_code = Column(String, nullable=True)
    business_type = Column(String, default="retail") # retail, wholesale, service
    tax_regime = Column(String, default="simples") # simples, lucro_real, lucro_presumido
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Back populates
    company = relationship("Company", back_populates="details")
