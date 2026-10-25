# The dedicated server: the same Linux export players run, started headless as a server.
# Build context is the export dir (python tools/export.py linux → build/linux/); CI builds and
# pushes it to ghcr.io/yggdrion/jotra-server on every push to main and every v* tag.
FROM debian:13-slim

RUN useradd --create-home jotra
COPY --chmod=755 jotra.x86_64 /opt/jotra/jotra.x86_64
USER jotra

# Game (ENet, UDP) and Prometheus metrics (HTTP, TCP).
EXPOSE 17777/udp 9310/tcp
ENTRYPOINT ["/opt/jotra/jotra.x86_64", "--headless", "--", "--server", "--port=17777", "--metrics-port=9310"]
