"""Frontend service -- the only service exposed outside the cluster.

Owns no data. Every value on the page is fetched from another service.
Reached from the internet through the Ingress controller, which terminates
TLS; this service itself only ever speaks plain HTTP inside the cluster.
"""

import os
import socket

import requests
from flask import Flask, redirect, render_template, request, url_for
from prometheus_flask_exporter import PrometheusMetrics

app = Flask(__name__)

POD_NAME = socket.gethostname()

# Non-sensitive configuration from a ConfigMap.
APP_VERSION = os.environ.get("APP_VERSION", "0.0.0-dev")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "development")
FEATURE_ORDERING = os.environ.get("FEATURE_ORDERING", "on").lower() == "on"

CATALOG_URL = os.environ.get("CATALOG_URL", "http://catalog:5000")
ORDER_URL = os.environ.get("ORDER_URL", "http://orders:5000")

metrics = PrometheusMetrics(app, group_by="endpoint")
metrics.info(
    "frontend_service_info",
    "Frontend service build information",
    version=APP_VERSION,
    environment=ENVIRONMENT,
)


def fetch_products():
    try:
        response = requests.get(f"{CATALOG_URL}/products", timeout=3)
        response.raise_for_status()
        payload = response.json()
        return payload["products"], payload["served_by"], True
    except (requests.RequestException, ValueError, KeyError):
        return [], None, False


def fetch_orders():
    """Returns (orders, pod, service_up, store_up).

    service_up and store_up are separate so the page can distinguish the
    order service being unreachable from the order service being healthy
    but having lost its datastore.
    """
    try:
        response = requests.get(f"{ORDER_URL}/orders", timeout=3)
        response.raise_for_status()
        payload = response.json()
        return payload["orders"], payload["served_by"], True, payload["store_available"]
    except (requests.RequestException, ValueError, KeyError):
        return [], None, False, False


@app.get("/")
def index():
    products, catalog_pod, catalog_up = fetch_products()
    orders, order_pod, orders_up, store_up = fetch_orders()

    return render_template(
        "index.html",
        frontend_pod=POD_NAME,
        catalog_pod=catalog_pod,
        order_pod=order_pod,
        catalog_up=catalog_up,
        orders_up=orders_up,
        store_up=store_up,
        products=products,
        orders=orders,
        app_version=APP_VERSION,
        environment=ENVIRONMENT,
        feature_ordering=FEATURE_ORDERING,
        secure=request.headers.get("X-Forwarded-Proto", "http") == "https",
        message=request.args.get("message"),
        error=request.args.get("error"),
    )


@app.post("/order")
def place_order():
    if not FEATURE_ORDERING:
        return redirect(url_for("index", error="Ordering is disabled by feature toggle."))

    product_id = request.form.get("product_id", type=int)
    quantity = request.form.get("quantity", default=1, type=int)

    try:
        response = requests.post(
            f"{ORDER_URL}/orders",
            json={"product_id": product_id, "quantity": quantity},
            timeout=3,
        )
    except requests.RequestException:
        return redirect(url_for("index", error="Order service is unreachable."))

    if response.status_code == 201:
        order = response.json()
        return redirect(
            url_for("index", message=f"Order #{order['id']} placed for {order['product']}.")
        )

    detail = response.json().get("error", "unknown error")
    return redirect(url_for("index", error=f"Order rejected: {detail}"))


@app.get("/healthz")
@metrics.do_not_track()
def healthz():
    return "ok", 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
