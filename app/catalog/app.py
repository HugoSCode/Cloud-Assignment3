"""Catalog service -- owns the product list.

Depends on nothing. Exposes Prometheus metrics on /metrics.
"""

import os
import socket

from flask import Flask, jsonify
from prometheus_flask_exporter import PrometheusMetrics

app = Flask(__name__)

POD_NAME = socket.gethostname()

# Non-sensitive configuration, injected from a ConfigMap.
APP_VERSION = os.environ.get("APP_VERSION", "0.0.0-dev")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "development")

# PrometheusMetrics registers /metrics and instruments every route with
# request counters and latency histograms, labelled by method, path and
# status. group_by="endpoint" keeps the label cardinality bounded -- using
# the raw path would create a new time series per distinct URL.
metrics = PrometheusMetrics(app, group_by="endpoint")
metrics.info(
    "catalog_service_info",
    "Catalog service build information",
    version=APP_VERSION,
    environment=ENVIRONMENT,
)

PRODUCTS = [
    {"id": 1, "name": "Raspberry Pi 5", "price": 79.00},
    {"id": 2, "name": "Arduino Uno R4", "price": 27.50},
    {"id": 3, "name": "ESP32 Dev Board", "price": 12.00},
    {"id": 4, "name": "USB Logic Analyser", "price": 34.95},
]


@app.get("/products")
def list_products():
    return jsonify({"served_by": POD_NAME, "products": PRODUCTS})


@app.get("/products/<int:product_id>")
def get_product(product_id):
    for product in PRODUCTS:
        if product["id"] == product_id:
            return jsonify(product)
    return jsonify({"error": "product not found"}), 404


# Excluded from metrics: probe traffic is high-volume and would otherwise
# dominate the request-rate graphs with traffic no user ever generated.
@app.get("/healthz")
@metrics.do_not_track()
def healthz():
    return "ok", 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
