# syntax=docker/dockerfile:1
FROM python:3.12-slim-bookworm AS builder
ARG TARGETARCH
WORKDIR /app
ENV PATH="/opt/venv/bin:$PATH"
RUN python -m venv /opt/venv
COPY requirements.txt .
RUN --mount=type=secret,id=pipconf,target=/etc/pip.conf,required=true \
    --mount=type=cache,id=shop-worker-pip-${TARGETARCH},target=/root/.cache/pip,sharing=locked \
    python -m pip install -r requirements.txt

FROM builder AS test
COPY requirements-dev.txt .
RUN --mount=type=secret,id=pipconf,target=/etc/pip.conf,required=true \
    --mount=type=cache,id=shop-worker-pip-${TARGETARCH},target=/root/.cache/pip,sharing=locked \
    python -m pip install -r requirements-dev.txt
COPY worker/ ./worker/
COPY tests/ ./tests/
RUN python -m pytest -q

FROM python:3.12-slim-bookworm AS runtime
WORKDIR /app
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1
COPY --from=builder /opt/venv /opt/venv

COPY --from=test /app/worker ./worker
CMD ["python", "-m", "worker.main"]
