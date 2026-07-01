import os
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    PROJECT_NAME: str = "ColiseuSpeed SaaS Admin Panel"
    
    # Database Settings
    # Use SQLite as fallback if PostgreSQL is not specified
    DATABASE_URL: str = os.getenv("DATABASE_URL", "sqlite:///./coliseuspeed_admin.db")
    IDENTITY_DATABASE_URL: str = os.getenv("IDENTITY_DATABASE_URL", "sqlite:///./coliseuspeed_admin.db")
    
    # Security Settings
    JWT_SECRET: str = os.getenv("JWT_SECRET", "747a7da7a7b9317b9c6a7880abcdef1234567890abcdef1234567890abcdef12")
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60
    
    # Redis Session Cache (rate limit / monitor logs)
    REDIS_URL: str = os.getenv("REDIS_URL", "redis://localhost:6379/0")
    
    # Sales API Integration URL (for license validation queries)
    SALES_API_URL: str = os.getenv("SALES_API_URL", "https://licencas.coliseusistemas.com.br")
    
    # Default Admin Seed Credentials
    SEED_ADMIN_EMAIL: str = os.getenv("SEED_ADMIN_EMAIL", "admin@coliseu.com.br")
    SEED_ADMIN_PASSWORD: str = os.getenv("SEED_ADMIN_PASSWORD", "98683818")

    class Config:
        case_sensitive = True

settings = Settings()
