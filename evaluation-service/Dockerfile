# ---------- Stage 1: build ----------
FROM golang:1.22-alpine AS builder

WORKDIR /src
RUN apk add --no-cache git ca-certificates

# ATENCAO: o go.sum do repositorio esta corrompido (e uma copia do go.mod).
# Por isso ele fica de fora do build (.dockerignore) e o grafo e resolvido
# do zero com 'go mod tidy'.
COPY go.mod ./
COPY *.go ./
RUN go mod tidy && \
    CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/evaluation-service .

# ---------- Stage 2: runtime ----------
FROM alpine:3.20

RUN apk add --no-cache ca-certificates wget && \
    adduser -D -u 10001 -h /home/appuser appuser

COPY --from=builder /out/evaluation-service /usr/local/bin/evaluation-service

USER appuser
WORKDIR /home/appuser
ENV PORT=8004
EXPOSE 8004

ENTRYPOINT ["evaluation-service"]
