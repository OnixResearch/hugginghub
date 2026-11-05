# OPTIONAL FALLBACK. Not the Spark path.
# GB10 hosts run NixOS and should enable services.hugginghub from this flake.
# This image is only for a machine that cannot import that module.
# Build context is the repository root (see deploy/docker-compose.yml).

FROM rust:1-bookworm AS build
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY static ./static
COPY templates ./templates
RUN cargo build --release --locked

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/target/release/hugginghub /usr/local/bin/hugginghub
# git http-backend is invoked as `git http-backend` via HH_GIT.
ENV HH_DATA=/data \
    HH_BIND=0.0.0.0:8080 \
    HH_GIT=/usr/bin/git \
    HH_OPEN_SIGNUP=0 \
    HOME=/data
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/hugginghub"]
