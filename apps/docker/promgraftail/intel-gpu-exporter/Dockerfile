# Minimal Intel GPU Prometheus exporter — runs intel_gpu_top -J and serves /metrics.
# Uses only the Python stdlib, so no pip deps to audit/pin beyond the base image.
FROM ubuntu:24.04

# intel-gpu-tools provides intel_gpu_top; python3 runs the exporter.
RUN apt-get update \
    && apt-get install -y --no-install-recommends intel-gpu-tools python3 \
    && rm -rf /var/lib/apt/lists/*

COPY exporter.py /usr/local/bin/exporter.py

EXPOSE 8080
ENTRYPOINT ["python3", "/usr/local/bin/exporter.py"]
