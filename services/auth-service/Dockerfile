FROM golang:1.27-alpine AS builder

WORKDIR /src
RUN apk add --no-cache ca-certificates

COPY go.mod go.sum ./
RUN go mod download && go mod verify

COPY *.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/auth-service .

FROM alpine:3.24

RUN apk add --no-cache ca-certificates wget && \
    adduser -D -u 10001 -h /home/appuser appuser

COPY --from=builder /out/auth-service /usr/local/bin/auth-service

USER appuser
WORKDIR /home/appuser
ENV PORT=8001
EXPOSE 8001

ENTRYPOINT ["auth-service"]
