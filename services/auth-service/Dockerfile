# ---------- Stage 1: build ----------
FROM golang:1.22-alpine AS builder

WORKDIR /src
RUN apk add --no-cache git ca-certificates

# O repositorio nao veio com go.sum e o go.mod listava um modulo inexistente
# (pgx/v4/stdlib e um pacote, nao um modulo) -> 'go mod tidy' resolve o grafo.
COPY go.mod ./
COPY *.go ./
RUN go mod tidy && \
    CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/auth-service .

# ---------- Stage 2: runtime ----------
FROM alpine:3.20

RUN apk add --no-cache ca-certificates wget && \
    adduser -D -u 10001 -h /home/appuser appuser

COPY --from=builder /out/auth-service /usr/local/bin/auth-service

USER appuser
WORKDIR /home/appuser
ENV PORT=8001
EXPOSE 8001

ENTRYPOINT ["auth-service"]
