# Minimal Jellyfin Prometheus exporter — stdlib only, no pip deps.
FROM python:3.12-slim

COPY exporter.py /usr/local/bin/exporter.py

EXPOSE 8080
ENTRYPOINT ["python3", "/usr/local/bin/exporter.py"]
