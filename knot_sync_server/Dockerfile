FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y libssl3 ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY target/release/knot_sync_server /app/knot_sync_server
COPY migrations ./migrations
COPY web_frontend ./web_frontend
ENV DATABASE_URL=postgres://knot:knot@postgres:5432/knot
ENV PORT=8080
EXPOSE 8080
CMD ["/app/knot_sync_server"]
