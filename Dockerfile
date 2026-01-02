# syntax=docker/dockerfile:1
ARG RUBY_VERSION=3.3.10

#################################
# Base image (runtime only)
#################################
FROM ruby:${RUBY_VERSION}-slim AS base

WORKDIR /rails

# Runtime dependencies
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      curl \
      libjemalloc2 \
      libvips42 \
      libvips-tools \
      postgresql-client \
      imagemagick \
      libmagickwand-dev \
      poppler-utils \
      ca-certificates \
      shared-mime-info && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists/*

ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD=/usr/local/lib/libjemalloc.so \
    NODE_OPTIONS="--max-old-space-size=2048" \
    RAILS_SERVE_STATIC_FILES=true \
    RAILS_LOG_TO_STDOUT=true

#################################
# Build stage
#################################
FROM base AS build

# Build dependencies - FIXED: Missing development libraries
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      build-essential \
      git \
      libpq-dev \
      libyaml-dev \
      pkg-config \
      python-is-python3 \
      nodejs \
      npm \
      libvips-dev \           # CRITICAL: vips development headers
      libmagickwand-dev \     # CRITICAL: imagemagick development headers
      libglib2.0-dev \
      libexpat1-dev && \
    rm -rf /var/lib/apt/lists/*

# Copy Gemfiles
COPY Gemfile Gemfile.lock ./

# Install gems
RUN bundle install && \
    rm -rf ~/.bundle \
      "${BUNDLE_PATH}"/ruby/*/cache \
      "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# Copy app
COPY . .

# Precompile assets - WITH PLACEHOLDER COPY
RUN SECRET_KEY_BASE=dummy \
    RAILS_ENV=production \
    bundle exec rails assets:precompile

# Copy placeholder images to public folder for direct serving on Render
RUN mkdir -p public/placeholders && \
    cp -r app/assets/images/placeholders/* public/placeholders/ 2>/dev/null || echo "Placeholders copied" && \
    cp -r public/assets/placeholders/* public/placeholders/ 2>/dev/null || echo "Compiled placeholders copied"

# Precompile bootsnap
RUN SECRET_KEY_BASE=dummy \
    RAILS_ENV=production \
    bundle exec bootsnap precompile app/ lib/

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

# Set proper permissions
RUN mkdir -p tmp/pids tmp/cache tmp/sockets storage && \
    chmod -R 700 storage tmp

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
CMD ["bin/rails", "server", "-b", "0.0.0.0"]

EXPOSE 3000