# The dedicated server: the same Linux export players run, started headless as a server.
# Build context is the export dir (python tools/export.py linux → build/linux/); see
# deploy/docker-compose.yml.
FROM debian:13-slim

RUN useradd --create-home jotra && mkdir /data && chown jotra /data
# The whole export: the game plus the webrtc-native library it loads next to it.
COPY . /opt/jotra/
RUN chmod 755 /opt/jotra/jotra.x86_64
# Godot dies on SIGTERM without running any code, so on docker stop this asks the server to
# save and exit through its stop file instead.
COPY --chmod=755 <<'EOF' /opt/jotra/entrypoint.sh
#!/bin/sh
rm -f /tmp/jotra.stop
/opt/jotra/jotra.x86_64 --headless -- "$@" --stop-file=/tmp/jotra.stop &
pid=$!
trap 'touch /tmp/jotra.stop' TERM INT
# wait returns early on a trapped signal, so keep waiting until the server is gone.
while kill -0 "$pid" 2>/dev/null; do
	wait "$pid"
	code=$?
done
exit "$code"
EOF
USER jotra

# The world save; keep it in a volume.
VOLUME /data
# Game (ENet, UDP) and Prometheus metrics (HTTP, TCP).
EXPOSE 17777/udp 9310/tcp
ENTRYPOINT ["/opt/jotra/entrypoint.sh", "--server", "--port=17777", "--metrics-port=9310", "--world=/data/world"]
