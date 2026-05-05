# syntax=docker/dockerfile:1.7

FROM hexpm/elixir:1.20.0-rc.4-erlang-29.0-rc3-debian-bookworm-20260421-slim AS builder

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
      build-essential git curl xz-utils ca-certificates libssl-dev libncurses-dev && \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get update -y && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

RUN corepack enable

ARG FRONTMAN_REPO=https://github.com/frontman-ai/frontman.git
ARG FRONTMAN_REF=main

WORKDIR /src
RUN git clone --depth=1 --branch "${FRONTMAN_REF}" "${FRONTMAN_REPO}" .

COPY patches/ /patches/
RUN /patches/apply.sh /src

RUN yarn install --immutable
RUN yarn rescript clean && yarn rescript build

ENV MIX_ENV=prod
WORKDIR /src/apps/frontman_server

RUN for i in 1 2 3 4 5; do curl -fsSL -o /tmp/hex.ez https://builds.hex.pm/installs/1.19.0/hex-2.4.2-otp-28.ez && break || sleep 5; done && \
    mix archive.install --force /tmp/hex.ez && \
    for i in 1 2 3 4 5; do curl -fsSL -o /tmp/rebar3 https://builds.hex.pm/installs/1.18.4/rebar3-3.25.1-otp-28 && break || sleep 5; done && \
    chmod +x /tmp/rebar3 && \
    mix local.rebar --force rebar3 /tmp/rebar3 && \
    mix deps.get --only "${MIX_ENV}" && \
    mix deps.compile

RUN mix tailwind.install --if-missing && mix esbuild.install --if-missing

RUN mix compile
RUN mix tailwind frontman_server --minify && \
    mix esbuild frontman_server --minify && \
    mix esbuild browser_test --minify && \
    mix phx.digest

RUN mix release

FROM debian:bookworm-slim

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV PHX_SERVER=true
ENV MIX_ENV=prod

WORKDIR /app
COPY --from=builder --chown=nobody:root /src/apps/frontman_server/_build/prod/rel/frontman_server ./

USER nobody
EXPOSE 4000

CMD ["/app/bin/server"]
