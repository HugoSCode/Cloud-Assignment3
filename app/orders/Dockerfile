# orders service image. Identical to catalog's by design: what differs between
# services is requirements.txt (orders adds redis), not the build.
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PROMETHEUS_MULTIPROC_DIR=/tmp/prometheus

WORKDIR /app

# Dependencies first: this layer is rebuilt only when requirements.txt changes,
# so editing app.py reuses the cached pip install.
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

COPY . /app

# Non-root. UID 10001 must match runAsUser in manifests/04-orders.yaml.
RUN useradd --create-home --uid 10001 appuser \
 && mkdir -p /tmp/prometheus \
 && chown -R appuser:appuser /app /tmp/prometheus
USER appuser

EXPOSE 5000

# One worker: prometheus_client keeps counters in process memory, so several
# workers would each report a partial count. Scale by Pod instead.
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "1", "--threads", "4", "app:app"]