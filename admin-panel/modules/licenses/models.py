from sqlalchemy import Column, Integer, String, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from datetime import datetime
from config.database import Base
from modules.companies.models import GUID

class License(Base):
    __tablename__ = "devices"

    # Maps to coliseu_identity devices columns
    id = Column("Id", GUID, primary_key=True)
    company_id = Column("CompanyId", GUID, ForeignKey("companies.Id"), nullable=False)
    device_uuid = Column("DeviceUuid", String(255), nullable=True)
    model = Column("Model", String(200), nullable=True)
    os = Column("OS", String(100), nullable=True)
    app_version = Column("AppVersion", String(50), nullable=True)
    status_code = Column("Status", Integer, default=0, nullable=False) # 1=Active
    license_key = Column("ActivationKey", String(64), nullable=True)
    activation_date = Column("FirstActivation", DateTime, default=datetime.utcnow)
    last_access = Column("LastAccess", DateTime, default=datetime.utcnow)

    # Relationships
    company = relationship("Company", back_populates="licenses")

    @property
    def status(self) -> str:
        return "active" if self.status_code == 1 else "inactive"

    @property
    def product_type(self) -> str:
        return "coliseu_speed"

    @property
    def max_users(self) -> int:
        return 5

    @property
    def max_branches(self) -> int:
        return 1

    @property
    def expiration_date(self):
        return None
