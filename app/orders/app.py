"""Order service -- validates orders against the catalog, stores them in Redis.

The only service that talks to Redis. Exposes both the automatic HTTP
metrics and hand-written business metrics (cache hits/misses, orders placed).
"""

import json
import os
import socket

import requests
from flask import Flask, jsonify, request
from prometheus_client import Counter
from prometheus_flask_exporter import PrometheusMetrics
from redis import Redis
from redis.backoff import NoBackoff
from redis.exceptions import RedisError
from redis.retry import Retry

app = Flask(__name__)

POD_NAME = socket.gethostname()

APP_VERSION = os.environ.get("APP_VERSION", "0.0.0-dev")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "development")

# Service names resolved by cluster DNS, never Pod IPs.
CATALOG_URL = os.environ.get("CATALOG_URL", "http://catalog:5000")
REDIS_HOST = os.environ.get("REDIS_HOST", "redis")

# Sensitive value, injected from a Kubernetes Secret.
DB_PASSWORD = os.environ.get("DB_PASSWORD", "NOT SET")

metrics = PrometheusMetrics(app, group_by="endpoint")
metrics.info(
    "order_service_info",
    "Order service build information",
    version=APP_VERSION,
    environment=ENVIRONMENT,
)

# Business metrics the automatic HTTP instrumentation cannot infer.
# A Counter only ever increases; rate() in PromQL turns it into a per-second
# rate at query time, which is why counters are preferred over gauges here.
CACHE_LOOKUPS = Counter(
    "order_catalog_cache_lookups_total",
    "Catalog lookups performed by the order service, by cache outcome.",
    ["outcome"],
)
ORDERS_PLACED = Counter(
    "orders_placed_total",
    "Orders successfully written to the datastore.",
)
ORDERS_REJECTED = Counter(
    "orders_rejected_total",
    "Orders refused, by reason.",
    ["reason"],
)

# Fail fast when Redis is unavailable. Without the explicit Retry, redis-py
# retries with exponential backoff, so a dead Redis makes THIS service slow
# rather than making it return an error -- and a caller with a 3s timeout
# would then wrongly report the order service as down.
redis = Redis(
    host=REDIS_HOST,
    port=6379,
    socket_connect_timeout=1,
    socket_timeout=1,
    retry=Retry(NoBackoff(), retries=0),
    decode_responses=True,
)

CACHE_TTL_SECONDS = 30


def lookup_product(product_id):
    """Fetch a product, using Redis as a short-lived read-through cache.

    Returns (product_dict, error_string). Exactly one is None.
    """
    cache_key = f"product:{product_id}"

    try:
        cached = redis.get(cache_key)
    except RedisError:
        # A cache that is down must not take the request down with it.
        cached = None

    if cached is not None:
        CACHE_LOOKUPS.labels(outcome="hit").inc()
        return json.loads(cached), None

    CACHE_LOOKUPS.labels(outcome="miss").inc()

    try:
        response = requests.get(f"{CATALOG_URL}/products/{product_id}", timeout=3)
    except requests.RequestException:
        return None, "catalog service unavailable"

    if response.status_code == 404:
        return None, f"no product with id {product_id}"
    if response.status_code != 200:
        return None, "catalog service returned an error"

    product = response.json()

    try:
        redis.setex(cache_key, CACHE_TTL_SECONDS, json.dumps(product))
    except RedisError:
        pass  # Caching is best-effort.

    return product, None


@app.post("/orders")
def create_order():
    data = request.get_json(silent=True) or {}
    product_id = data.get("product_id")
    quantity = int(data.get("quantity", 1))

    if product_id is None:
        ORDERS_REJECTED.labels(reason="missing_product_id").inc()
        return jsonify({"error": "product_id is required"}), 400

    product, error = lookup_product(product_id)

    if error == "catalog service unavailable":
        ORDERS_REJECTED.labels(reason="catalog_unavailable").inc()
        return jsonify({"error": error}), 503
    if error is not None:
        ORDERS_REJECTED.labels(reason="unknown_product").inc()
        return jsonify({"error": error}), 404

    try:
        order_id = redis.incr("order:next_id")
        order = {
            "id": order_id,
            "product": product["name"],
            "unit_price": product["price"],
            "quantity": quantity,
            "total": round(product["price"] * quantity, 2),
            "placed_by": POD_NAME,
        }
        redis.rpush("orders", json.dumps(order))
    except RedisError:
        ORDERS_REJECTED.labels(reason="store_unavailable").inc()
        return jsonify({"error": "order store unavailable"}), 503

    ORDERS_PLACED.inc()
    return jsonify(order), 201


@app.get("/orders")
def list_orders():
    try:
        raw_orders = redis.lrange("orders", 0, -1)
    except RedisError:
        return jsonify({"served_by": POD_NAME, "orders": [], "store_available": False})

    return jsonify(
        {
            "served_by": POD_NAME,
            "orders": [json.loads(item) for item in raw_orders],
            "store_available": True,
        }
    )


@app.get("/config")
def show_config():
    """Expose non-sensitive config, and prove the Secret was injected.

    The password is reported only as a boolean and a length. Never return a
    secret value from an API -- the lab did so to make the mechanism visible,
    but that is not acceptable practice in an assessed deployment.
    """
    return jsonify(
        {
            "served_by": POD_NAME,
            "version": APP_VERSION,
            "environment": ENVIRONMENT,
            "db_password_present": DB_PASSWORD != "NOT SET",
            "db_password_length": len(DB_PASSWORD) if DB_PASSWORD != "NOT SET" else 0,
        }
    )


@app.get("/healthz")
@metrics.do_not_track()
def healthz():
    """Deliberately does NOT check Redis or the catalog."""
    return "ok", 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
