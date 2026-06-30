import pytest
from fastapi.testclient import TestClient
import sys
import os

# Adjust paths to make config and modules available to tests
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import app

@pytest.fixture(scope="function")
def client():
    with TestClient(app) as test_client:
        yield test_client
