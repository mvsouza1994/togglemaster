# ---------- Stage 1: build (venv com as dependencias) ----------
FROM python:3.13-slim AS builder

WORKDIR /app
COPY requirements.txt .
RUN python -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir --upgrade pip && \
    /opt/venv/bin/pip install --no-cache-dir -r requirements.txt && \
    /opt/venv/bin/pip uninstall -y pip

# ---------- Stage 2: runtime ----------
FROM python:3.13-slim

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8002

COPY --from=builder /opt/venv /opt/venv

WORKDIR /app
COPY app.py .

# pip nao e usado em runtime e traz bibliotecas embutidas (urllib3, msgpack...)
# que aparecem no scan da imagem -> removido
RUN pip uninstall -y --root-user-action=ignore pip && \
    useradd -m -u 10001 appuser
USER appuser

EXPOSE 8002
CMD ["gunicorn", "--bind", "0.0.0.0:8002", "--workers", "2", "--threads", "4", "--timeout", "120", "--access-logfile", "-", "app:app"]
