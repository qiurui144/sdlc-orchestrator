You are operating AS the codebase-reviewer agent (agents/codebase-reviewer.md
is appended to your system prompt). Perform a structural scan then deep-review
the top hotspot from this sample repo. Produce your full two-pass report.

---

## Repo: sample-repo (3 Python files, no test files)

### File inventory

| File | Lines | Markers | Test file? |
|------|-------|---------|-----------|
| big_handler.py | 258 | FIXME (line 84) | NO |
| utils.py | 15 | none | implied by docstring |
| config.py | 9 | none | none needed (env vars only) |

### big_handler.py  (258 lines — full content)

```python
"""
HTTP request handler for the order processing service.
No corresponding test file exists for this module.
"""

import json
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

class Order:
    def __init__(self, order_id, user_id, items, metadata=None):
        self.order_id = order_id
        self.user_id = user_id
        self.items = items
        self.metadata = metadata    # optional dict; may be None
        self.status = "pending"
        self.created_at = datetime.utcnow()
        self.total = 0.0
        self.payment_result = None
        self.inventory_holds = []
        self.notifications_sent = []
        self.audit_log = []

class PaymentGateway:
    def __init__(self, api_key, endpoint):
        self.api_key = api_key
        self.endpoint = endpoint
        self.last_transaction = None

    def charge(self, user_id, amount, currency="USD"):
        if amount <= 0:
            raise ValueError("Charge amount must be positive")
        self.last_transaction = {"user_id": user_id, "amount": amount}
        return {"status": "ok", "txn_id": f"txn_{user_id}_{int(amount*100)}"}

class InventoryService:
    def __init__(self, db_conn):
        self.db_conn = db_conn
        self.reserved = {}

    def reserve(self, sku, qty):
        key = f"{sku}:{qty}"
        self.reserved[key] = True
        return {"hold_id": f"hold_{sku}", "sku": sku, "qty": qty}

    def release(self, hold_id):
        logger.info("Releasing hold %s", hold_id)
        return True

class NotificationService:
    def __init__(self, smtp_host, from_addr):
        self.smtp_host = smtp_host
        self.from_addr = from_addr

    def send_email(self, to_addr, subject, body):
        return True

    def send_sms(self, phone, message):
        return True

class AuditLogger:
    def __init__(self, store):
        self.store = store
        self.entries = []

    def log(self, event_type, payload):
        entry = {"ts": datetime.utcnow().isoformat(), "event": event_type, "payload": payload}
        self.entries.append(entry)
        self.store.append(entry)

class OrderHandler:
    """
    Handles the full order lifecycle: validate → price → reserve → charge → notify → audit.

    Known issues:
      # FIXME: no unit tests; every change here risks silent regression
    """

    def __init__(self, payment_gw, inventory_svc, notification_svc, audit_logger):
        self.payment_gw = payment_gw
        self.inventory_svc = inventory_svc
        self.notification_svc = notification_svc
        self.audit_logger = audit_logger
        self._processed = []

    def validate_order(self, order):
        if not order.items:
            raise ValueError("Order must contain at least one item")
        for item in order.items:
            if item.get("qty", 0) <= 0:
                raise ValueError(f"Invalid qty for sku {item.get('sku')}")
            if item.get("unit_price", 0) < 0:
                raise ValueError(f"Negative price for sku {item.get('sku')}")
        return True

    def calculate_total(self, order):
        total = 0.0
        for item in order.items:
            total += item["qty"] * item["unit_price"]
        # BUG: no None-guard on metadata — crashes with AttributeError/TypeError
        # when order.metadata is None (the default)
        discount = order.metadata["discount"]   # NullPointerError if metadata is None
        total = total * (1.0 - discount)
        order.total = round(total, 2)
        return order.total

    def reserve_inventory(self, order):
        holds = []
        for item in order.items:
            hold = self.inventory_svc.reserve(item["sku"], item["qty"])
            holds.append(hold)
            order.inventory_holds.append(hold)
        return holds

    def release_inventory(self, order):
        for hold in order.inventory_holds:
            self.inventory_svc.release(hold["hold_id"])
        order.inventory_holds = []

    def process_payment(self, order):
        result = self.payment_gw.charge(order.user_id, order.total)
        order.payment_result = result
        if result.get("status") != "ok":
            raise RuntimeError(f"Payment failed: {result}")
        return result

    def notify_user(self, order, user_email, user_phone=None):
        subject = f"Order #{order.order_id} confirmed"
        body = f"Hi,\n\nYour order #{order.order_id} has been placed.\nTotal: ${order.total:.2f}\n\nThank you!"
        ok = self.notification_svc.send_email(user_email, subject, body)
        order.notifications_sent.append({"channel": "email", "ok": ok})
        if user_phone:
            sms_ok = self.notification_svc.send_sms(
                user_phone, f"Order #{order.order_id} confirmed. Total: ${order.total:.2f}"
            )
            order.notifications_sent.append({"channel": "sms", "ok": sms_ok})

    def notify_ops(self, order):
        subject = f"[OPS] New order #{order.order_id}"
        body = json.dumps({"order_id": order.order_id, "user_id": order.user_id,
                           "total": order.total, "items": order.items}, indent=2)
        self.notification_svc.send_email("ops@example.com", subject, body)

    def record_audit(self, order, event_type, extra=None):
        payload = {"order_id": order.order_id, "user_id": order.user_id, "status": order.status}
        if extra:
            payload.update(extra)
        self.audit_logger.log(event_type, payload)
        order.audit_log.append(event_type)

    def handle(self, order, user_email, user_phone=None):
        """Full order processing pipeline."""
        self.validate_order(order)
        self.record_audit(order, "order.received")
        total = self.calculate_total(order)    # raises TypeError if metadata=None
        self.record_audit(order, "order.priced", {"total": total})
        holds = self.reserve_inventory(order)
        self.record_audit(order, "order.inventory_reserved", {"holds": len(holds)})
        try:
            payment = self.process_payment(order)
            self.record_audit(order, "order.charged", {"txn_id": payment.get("txn_id")})
        except RuntimeError:
            self.release_inventory(order)
            self.record_audit(order, "order.payment_failed")
            order.status = "failed"
            raise
        order.status = "confirmed"
        self.record_audit(order, "order.confirmed")
        self.notify_user(order, user_email, user_phone)
        self.notify_ops(order)
        self.record_audit(order, "order.notifications_sent")
        self._processed.append(order.order_id)
        return order

    def retry_handle(self, order, user_email, max_retries=3, user_phone=None):
        """Retry wrapper — no exponential back-off, no dedup guard."""
        last_err = None
        for attempt in range(1, max_retries + 1):
            try:
                return self.handle(order, user_email, user_phone)
            except RuntimeError as exc:
                logger.warning("Attempt %d/%d failed: %s", attempt, max_retries, exc)
                last_err = exc
        raise last_err

    def get_processed_ids(self):
        return list(self._processed)

    def reset(self):
        self._processed = []
```

### utils.py  (15 lines — full content)

```python
"""Tiny utility helpers — well-tested, no markers, no known bugs."""

def clamp(value, lo, hi):
    return max(lo, min(hi, value))

def slugify(text):
    return text.strip().lower().replace(" ", "-")

def parse_bool(s):
    return str(s).strip().lower() in ("1", "yes", "true", "on")
```

### config.py  (9 lines — full content)

```python
"""App configuration loaded from environment variables."""
import os

PAYMENT_API_KEY = os.environ.get("PAYMENT_API_KEY", "")
PAYMENT_ENDPOINT = os.environ.get("PAYMENT_ENDPOINT", "https://pay.example.com/v1")
SMTP_HOST = os.environ.get("SMTP_HOST", "localhost")
SMTP_FROM = os.environ.get("SMTP_FROM", "noreply@example.com")
DB_URL = os.environ.get("DB_URL", "sqlite:///orders.db")
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")
```

---

Perform your two-pass review:
1. Structural scan: rank all three files by hotspot score (size + markers + test coverage + bug signals).
2. Deep review: the #1 hotspot only — flag bugs, FIXME items, missing tests, and give a verdict (WARN / FAIL / BLOCK).
