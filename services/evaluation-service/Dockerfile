# ---------- Stage 1: build ----------
FROM golang:1.27-alpine AS builder

WORKDIR /src
RUN apk add --no-cache ca-certificates

# go.mod + go.sum versionados: build reproduzivel (sem 'go mod tidy' no build)
COPY go.mod go.sum ./
RUN go mod download && go mod verify

COPY *.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/evaluation-service .

# ---------- Stage 2: runtime ----------
FROM alpine:3.24

RUN apk add --no-cache ca-certificates wget && \
    adduser -D -u 10001 -h /home/appuser appuser

COPY --from=builder /out/evaluation-service /usr/local/bin/evaluation-service

USER appuser
WORKDIR /home/appuser
ENV PORT=8004
EXPOSE 8004

ENTRYPOINT ["evaluation-service"]
