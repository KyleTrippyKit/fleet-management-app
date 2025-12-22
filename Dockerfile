# syntax=docker/dockerfile:1
ARG RUBY_VERSION=3.3.10

#################################
# Base image (runtime only)
#################################
FROM ruby:${RUBY_VERSION}-slim AS base

WORKDIR /rails

# Runtime dependencies ONLY
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      curl \
      libjemalloc2 \
      libvips \
      postgresql-client \
      imagemagick \
      poppler-utils \
      nodejs \
      ca-certificates && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists/*

ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD=/usr/local/lib/libjemalloc.so

#################################
# Build stage
#################################
FROM base AS build

# Build dependencies
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
      git \
      libpq-dev \
      libyaml-dev \
      pkg-config \
      python-is-python3 && \
    rm -rf /var/lib/apt/lists/*

# Copy Gemfiles
COPY Gemfile Gemfile.lock ./

# Install gems
RUN bundle install && \
    rm -rf ~/.bundle \
      "${BUNDLE_PATH}"/ruby/*/cache \
      "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy app
COPY . .

# Precompile caches & assets
RUN SECRET_KEY_BASE=dummy \
    bundle exec bootsnap precompile -j 1 app/ lib/ && \
    SECRET_KEY_BASE=dummy \
    bundle exec rake assets:precompile

#################################
# Final production image
#################################
FROM base

# Non-root user
RUN groupadd --system --gid 1000 rails && \
    useradd --system --uid 1000 --gid 1000 --create-home rails

USER rails

# Copy built artifacts
COPY --from=build --chown=rails:rails /usr/local/bundle /usr/local/bundle
COPY --from=build --chown=rails:rails /rails /rails

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
CMD ["bin/rails", "server", "-b", "0.0.0.0"]

EXPOSE 80
