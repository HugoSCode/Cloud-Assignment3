# frontend service image. Same build as catalog and orders; requirements.txt
# differs (no redis client), the Dockerfile does not.
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PROMETHEUS_MULTIPROC_DIR=/tmp/prometheus

WORKDIR /app

# Dependencies first so the pip layer is cached across source edits.
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

COPY . /app

# Non-root. UID 10001 must match runAsUser in manifests/05-frontend.yaml.
RUN useradd --create-home --uid 10001 appuser \
 && mkdir -p /tmp/prometheus \
 && chown -R appuser:appuser /app /tmp/prometheus
USER appuser

EXPOSE 5000

# One worker: in-process Prometheus counters (see orders/Dockerfile).
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "1", "--threads", "4", "app:app"]