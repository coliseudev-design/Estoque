import os
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    PROJECT_NAME: str = "ColiseuSpeed Force Web"
    
    # Internal Docker Compose endpoints (bridges latency)
    MIDDLEWARE_URL: str = os.getenv("MIDDLEWARE_URL", "http://speed-middleware:3000")
    ADMIN_PANEL_URL: str = os.getenv("ADMIN_PANEL_URL", "http://admin-panel:8000")
    
    # API Key for middleware authentication
    API_KEY: str = os.getenv("API_KEY", "")
    
    # Target Tenant Configuration
    COMPANY_ID: str = os.getenv("COMPANY_ID", "a822a7e7-fdd4-4483-bbb5-26587a72739f")
    
    # Session Security settings
    JWT_SECRET: str = os.getenv("JWT_SECRET", "747a7da7a7b9317b9c6a7880abcdef1234567890abcdef1234567890abcdef12")
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 480 # 8 hours reps workday
    
    # Mocking integrations fallback (e.g. offline sandbox testing)
    USE_MOCKS: bool = os.getenv("USE_MOCKS", "True").lower() == "true"

    class Config:
        case_sensitive = True

settings = Settings()
