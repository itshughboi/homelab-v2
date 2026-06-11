# syntax=docker/dockerfile:1
# Multi-stage build for the Hugo docs site.
#   build stage: regenerate content/ from docs/ (sync.sh) + build Hugo. The hugo-book theme
#                is a Hugo Module, so Go is required to fetch it (hence the golang base).
#   serve stage: static nginx. Immutable — each deploy is a fresh image, no in-place mutation.
# Built + (re)deployed by .gitea/workflows/docs-deploy.yaml on push to main.

# ---- build ----
FROM golang:1.22-bookworm AS build
ARG HUGO_VERSION=0.161.1
ARG BASE_URL=https://docs.hughboi.cc/
ARG BOOK_REPO=https://gitea.hughboi.cc/hughboi/homelab
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && curl -sSLo /tmp/hugo.tar.gz \
      "https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_linux-amd64.tar.gz" \
 && tar -xf /tmp/hugo.tar.gz -C /usr/local/bin hugo \
 && hugo version
WORKDIR /src
COPY . .
# BOOK_REPO override points the "Edit" link at internal Gitea (vs. the GitHub default in hugo.toml)
RUN cd docs/hugo \
 && ./sync.sh \
 && HUGO_PARAMS_BOOKREPO="${BOOK_REPO}" hugo --minify --baseURL "${BASE_URL}"

# ---- serve ----
FROM nginx:1.27-alpine
COPY --from=build /src/docs/hugo/public /usr/share/nginx/html
EXPOSE 80
