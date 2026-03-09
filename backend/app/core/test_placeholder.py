"""
Placeholder for unit tests.
Run with: pytest tests/
"""
import pytest
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_root():
    response = client.get("/")
    assert response.status_code == 200
    assert response.json() == {"message": "Neo AI Backend is running"}

# Add more tests for endpoints, tools, memory, etc.