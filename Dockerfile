# === Build stage ===
FROM hexpm/elixir:1.18.4-erlang-28.0.2-debian-bookworm-20260202-slim AS build

RUN apt-get update -y && \
    apt-get install -y build-essential git curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

# Install dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mkdir config
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

# Copy source and compile (must happen before assets.deploy
# so phoenix-colocated hooks are generated for esbuild)
COPY priv priv
COPY assets assets
COPY lib lib
COPY config/runtime.exs config/
RUN mix compile

# Build assets
RUN mix assets.deploy

# Build release
RUN mix release

# === Runtime stage ===
FROM debian:bookworm-slim AS runtime

RUN apt-get update -y && \
    apt-get install -y \
      libstdc++6 openssl libncurses5 locales ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app

RUN useradd --create-home --shell /bin/bash app
USER app

COPY --from=build --chown=app:app /app/_build/prod/rel/ksef_hub ./

ENV PHX_SERVER=true
EXPOSE 4000

CMD ["bin/ksef_hub", "start"]
