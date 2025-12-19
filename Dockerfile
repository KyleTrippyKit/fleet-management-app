# syntax=docker/dockerfile:1
ARG RUBY_VERSION=3.3.10
FROM ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

# Runtime dependencies only
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      curl libjemalloc2 libvips postgresql-client bzip2 xz-utils && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# --- Build stage ---
FROM base AS build

# Install build dependencies
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential git libpq-dev libyaml-dev pkg-config python-is-python3 && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# Copy Gemfiles
COPY Gemfile Gemfile.lock ./

# Install gems (build dependencies present here)
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy the app code
COPY . .

# Precompile bootsnap cache for app directories
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# --- Final production image ---
FROM base

# Create non-root user
RUN groupadd --system --gid 1000 rails && \
    useradd --system --uid 1000 --gid 1000 --create-home --shell /bin/bash rails
USER 1000:1000

# Copy gems and app code from build stage
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Entrypoint & command
ENTRYPOINT ["/rails/bin/docker-entrypoint"]
CMD ["./bin/rails", "server", "-b", "0.0.0.0"]

EXPOSE 80
