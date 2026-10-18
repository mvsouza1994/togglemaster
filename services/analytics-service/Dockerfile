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
    PORT=8005

COPY --from=builder /opt/venv /opt/venv

WORKDIR /app
COPY app.py .

# pip nao e usado em runtime e traz bibliotecas embutidas (urllib3, msgpack...)
# que aparecem no scan da imagem -> removido
RUN pip uninstall -y --root-user-action=ignore pip && \
    useradd -m -u 10001 appuser
USER appuser

EXPOSE 8005
# 1 worker: o consumidor SQS roda numa thread iniciada no import do modulo.
# Mais workers = mais consumidores concorrentes na mesma fila (o HPA escala por pod).
CMD ["gunicorn", "--bind", "0.0.0.0:8005", "--workers", "1", "--threads", "4", "--timeout", "120", "--access-logfile", "-", "app:app"]
