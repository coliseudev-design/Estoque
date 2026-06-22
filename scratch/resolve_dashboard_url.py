import socket
import requests

try:
    ip = socket.gethostbyname("dashboard.coliseusistemas.com.br")
    print(f"dashboard.coliseusistemas.com.br IP: {ip}")
except Exception as e:
    print(f"Error resolving DNS: {e}")

try:
    # Test requests to licenses (middleware) and dashboard
    r1 = requests.get("https://licencas.coliseusistemas.com.br/health", timeout=5)
    print(f"licencas health status: {r1.status_code}, content: {r1.text}")
except Exception as e:
    print(f"Error calling licencas: {e}")

try:
    r2 = requests.get("https://dashboard.coliseusistemas.com.br/", timeout=5)
    print(f"dashboard root status: {r2.status_code}, content: {r2.text[:200]}")
except Exception as e:
    print(f"Error calling dashboard: {e}")
