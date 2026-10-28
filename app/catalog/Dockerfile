# ===========================================================================
# WORKED EXAMPLE -- supplied complete.
#
# The Dockerfiles for the orders and frontend services are yours to write.
#
# Be warned that this is a trap as much as a gift. You may well conclude
# that all three can be byte-identical -- and you would be right, because
# what differs between the services is their requirements.txt, not their
# build. That is a legitimate finding, so state it in your report rather
# than inventing differences to look busy.
#
# What is assessed here is not typing. It is whether you can explain every
# line of this file in the code defense: why the base image, why the COPY
# order, why a non-root user, why one worker. TASKS.md lists the questions.
# ===========================================================================
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PROMETHEUS_MULTIPROC_DIR=/tmp/prometheus

WORKDIR /app

COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

COPY . /app

# Run as a non-root user. The default python image runs as root, which
# would let a container escape have far more impact than it needs to.
RUN useradd --create-home --uid 10001 appuser \
 && mkdir -p /tmp/prometheus \
 && chown -R appuser:appuser /app /tmp/prometheus
USER appuser

EXPOSE 5000

# One worker: prometheus_client keeps counters in process memory, so
# multiple gunicorn workers would each hold a different partial count and
# /metrics would return whichever worker answered. Multi-worker setups need
# PROMETHEUS_MULTIPROC_DIR and a merged collector -- see the exemplar notes.
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "1", "--threads", "4", "app:app"]
