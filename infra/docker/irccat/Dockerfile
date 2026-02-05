FROM golang:1.21-alpine AS builder

WORKDIR /src
RUN apk add --no-cache git
RUN git clone https://github.com/irccloud/irccat.git .
RUN go build -o irccat .

FROM alpine:latest

WORKDIR /app
RUN apk add --no-cache ca-certificates

COPY --from=builder /src/irccat /app/irccat
COPY config.json.template /app/config.json.template
COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh

CMD ["/app/run.sh"]
