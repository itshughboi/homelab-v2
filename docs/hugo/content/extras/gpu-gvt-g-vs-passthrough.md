---
title: "GPU Passthrough"
---

# GPU Passthrough

---

## Standard Passthrough vs SR-IOV

**Standard Passthrough:** Gives the GPU exclusively to one VM (e.g., TrueNAS for QuickSync transcoding). Simple to set up, but the GPU is fully dedicated — no sharing.

**SR-IOV (Modern Passthrough):** If supported by your GPU model and kernel, SR-IOV splits the GPU into multiple virtual GPUs. You can give a slice to TrueNAS for media encoding and another slice to an LXC container for AI/Ollama or Plex — without needing a second card.

---

## Intel Arc (Current Hardware — pve-srv-1)

Intel Arc supports SR-IOV on newer kernel versions. Check compatibility for your specific Arc model before committing to either approach.

Use cases in this lab:
- TrueNAS: QuickSync hardware transcoding (Plex/Jellyfin)
- LXC container: Ollama or other GPU-accelerated workloads

---

## Which to Use

| Scenario | Approach |
| --- | --- |
| Only one VM needs the GPU | Standard passthrough |
| Multiple VMs/containers need GPU access | SR-IOV (if supported) |
| GPU model/kernel doesn't support SR-IOV | Standard passthrough + second card when needed |
