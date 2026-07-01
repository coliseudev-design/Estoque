import uuid
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, Boolean, CHAR
from sqlalchemy.orm import relationship
from sqlalchemy.types import TypeDecorator
from sqlalchemy.dialects.postgresql import UUID
from datetime import datetime
from config.database import Base

class GUID(TypeDecorator):
    """Platform-independent GUID type.
    Uses PostgreSQL's UUID type, otherwise uses CHAR(36).
    """
    impl = CHAR
    cache_ok = True

    def load_dialect_impl(self, dialect):
        if dialect.name == 'postgresql':
            return dialect.type_descriptor(UUID())
        else:
            return dialect.type_descriptor(CHAR(36))

    def process_bind_param(self, value, dialect):
        if value is None:
            return value
        elif dialect.name == 'postgresql':
            return str(value)
        else:
            if not isinstance(value, uuid.UUID):
                try:
                    return str(uuid.UUID(str(value)))
                except ValueError:
                    return str(value)
            else:
                return str(value)

    def process_result_value(self, value, dialect):
        if value is None:
            return value
        else:
            if not isinstance(value, uuid.UUID):
                try:
                    return uuid.UUID(str(value))
                except ValueError:
                    return value
            return value

class Company(Base):
    __tablename__ = "companies"

    # Maps to coliseu_identity companies columns
    id = Column("Id", GUID, primary_key=True, index=True, default=uuid.uuid4)
    name = Column("Name", String(200), nullable=False)
    status = Column("Status", Integer, default=1) # 1=Active
    created_at = Column("CreatedAt", DateTime, default=datetime.utcnow)
    updated_at = Column("UpdatedAt", DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    email = Column("ContactEmail", String(255), nullable=True)

    # Relationships
    details = relationship("CompanyDetails", uselist=False, back_populates="company", cascade="all, delete-orphan")
    licenses = relationship("License", back_populates="company", cascade="all, delete-orphan")
    integrations = relationship("ApiIntegration", back_populates="company", cascade="all, delete-orphan")
    instances = relationship("Instance", back_populates="company", cascade="all, delete-orphan")
    api_keys = relationship("ApiKey", back_populates="company", cascade="all, delete-orphan")
    branches = relationship("Branch", back_populates="company", cascade="all, delete-orphan")

    @property
    def cnpj(self) -> str:
        # Return CNPJ from default branch
        default_branch = next((b for b in self.branches if b.is_default), None)
        if default_branch and default_branch.cnpj:
            return default_branch.cnpj
        if self.branches and self.branches[0].cnpj:
            return self.branches[0].cnpj
        return "Sem CNPJ"

    @property
    def logo_url(self) -> str:
        return self.details.logo_url if self.details else ""

    @property
    def app_type(self) -> str:
        return self.details.app_type if self.details else "both"

    @property
    def phone(self) -> str:
        return self.details.phone if self.details else ""

    @property
    def fantasy_name(self) -> str:
        return self.details.fantasy_name if self.details else self.name

class CompanyModule(Base):
    __tablename__ = "company_modules"

    id = Column("Id", GUID, primary_key=True, default=uuid.uuid4)
    company_id = Column("CompanyId", GUID, ForeignKey("companies.Id"), nullable=False)
    module_slug = Column("ModuleSlug", String(50), nullable=False)
    is_active = Column("IsActive", Boolean, default=True)
    api_key_hash = Column("ApiKeyHash", String(256), nullable=True)

    company = relationship("Company")

class Branch(Base):
    __tablename__ = "branches"

    id = Column("Id", GUID, primary_key=True, default=uuid.uuid4)
    company_id = Column("CompanyId", GUID, ForeignKey("companies.Id"), nullable=False)
    name = Column("Name", String(100), nullable=False)
    cnpj = Column("Cnpj", String(20), nullable=True)
    is_default = Column("IsDefault", Boolean, default=False)

    company = relationship("Company", back_populates="branches")

class CompanyDetails(Base):
    __tablename__ = "company_details"

    id = Column(Integer, primary_key=True, index=True)
    company_id = Column(GUID, ForeignKey("companies.Id"), nullable=False)
    fantasy_name = Column(String, nullable=True)
    phone = Column(String, nullable=True)
    logo_url = Column(String, nullable=True)
    app_type = Column(String, default="both") # mobile, web, both
    state_registration = Column(String, nullable=True)
    municipal_registration = Column(String, nullable=True)
    address = Column(String, nullable=True)
    city = Column(String, nullable=True)
    state = Column(String, nullable=True)
    zip_code = Column(String, nullable=True)
    business_type = Column(String, default="retail")
    tax_regime = Column(String, default="simples")
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Back populates
    company = relationship("Company", back_populates="details")
