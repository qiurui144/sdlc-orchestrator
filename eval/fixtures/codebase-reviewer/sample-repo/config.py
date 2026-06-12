"""App configuration loaded from environment variables."""

import os


PAYMENT_API_KEY = os.environ.get("PAYMENT_API_KEY", "")
PAYMENT_ENDPOINT = os.environ.get("PAYMENT_ENDPOINT", "https://pay.example.com/v1")
SMTP_HOST = os.environ.get("SMTP_HOST", "localhost")
SMTP_FROM = os.environ.get("SMTP_FROM", "noreply@example.com")
DB_URL = os.environ.get("DB_URL", "sqlite:///orders.db")
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")
