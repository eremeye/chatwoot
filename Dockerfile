# pre-build stage
FROM ruby:3.0.4-alpine AS pre-builder

# ARG default to production settings
# For development docker-compose file overrides ARGS
ARG BUNDLE_WITHOUT="development:test"
ENV BUNDLE_WITHOUT ${BUNDLE_WITHOUT}
ENV BUNDLER_VERSION=2.1.2

ARG RAILS_SERVE_STATIC_FILES=true
ENV RAILS_SERVE_STATIC_FILES ${RAILS_SERVE_STATIC_FILES}

ARG RAILS_ENV=production
ENV RAILS_ENV ${RAILS_ENV}

ENV BUNDLE_PATH="/gems"

RUN apk add --no-cache \
    openssl \
    tar \
    build-base \
    tzdata \
    postgresql-dev \
    postgresql-client \
    nodejs \
    yarn \
    git \
    curl \
    unzip \
  && mkdir -p /var/app \
  && gem install bundler

# eremeye: download chatwoot source
RUN version='2.7.0'; \
    curl -o chatwoot-$version.zip -fL "https://github.com/chatwoot/chatwoot/archive/refs/tags/v$version.zip"; \
    unzip chatwoot-$version.zip; \
    mv chatwoot-$version/ /app ; \
    rm chatwoot-$version.zip chatwoot-$version; \
    ls 

WORKDIR /app

COPY app/services/message_templates/hook_execution_service.rb ./app/services/message_templates/hook_execution_service.rb
COPY config/locales/ru.yml ./config/locales/ru.yml
COPY app/javascript/survey/i18n/locale/ru.json ./app/javascript/survey/i18n/locale/ru.json
COPY app/javascript/dashboard/components/widgets/DashboardApp/Frame.vue ./app/javascript/dashboard/components/widgets/DashboardApp/Frame.vue

#COPY Gemfile Gemfile.lock ./

# natively compile grpc and protobuf to support alpine musl (dialogflow-docker workflow)
# https://github.com/googleapis/google-cloud-ruby/issues/13306
# adding xz as nokogiri was failing to build libxml
# https://github.com/chatwoot/chatwoot/issues/4045
RUN apk add --no-cache musl ruby-full ruby-dev gcc make musl-dev openssl openssl-dev g++ linux-headers xz
RUN bundle config set --local force_ruby_platform true

# Do not install development or test gems in production
RUN if [ "$RAILS_ENV" = "production" ]; then \
  bundle config set without 'development test'; bundle install -j 4 -r 3; \
  else bundle install -j 4 -r 3; \
  fi

#COPY package.json yarn.lock ./

RUN yarn install

#COPY . /app

# creating a log directory so that image wont fail when RAILS_LOG_TO_STDOUT is false
# https://github.com/chatwoot/chatwoot/issues/701
RUN mkdir -p /app/log

# generate production assets if production environment
RUN if [ "$RAILS_ENV" = "production" ]; then \
  SECRET_KEY_BASE=precompile_placeholder RAILS_LOG_TO_STDOUT=enabled bundle exec rake assets:precompile \
  && rm -rf spec node_modules tmp/cache; \
  fi

# Remove unnecessary files
RUN rm -rf /gems/ruby/3.0.0/cache/*.gem \
  && find /gems/ruby/3.0.0/gems/ \( -name "*.c" -o -name "*.o" \) -delete

# final build stage
FROM ruby:3.0.4-alpine

ARG BUNDLE_WITHOUT="development:test"
ENV BUNDLE_WITHOUT ${BUNDLE_WITHOUT}
ENV BUNDLER_VERSION=2.1.2

ARG EXECJS_RUNTIME="Disabled"
ENV EXECJS_RUNTIME ${EXECJS_RUNTIME}

ARG RAILS_SERVE_STATIC_FILES=true
ENV RAILS_SERVE_STATIC_FILES ${RAILS_SERVE_STATIC_FILES}

ARG BUNDLE_FORCE_RUBY_PLATFORM=1
ENV BUNDLE_FORCE_RUBY_PLATFORM ${BUNDLE_FORCE_RUBY_PLATFORM}

ARG RAILS_ENV=production
ENV RAILS_ENV ${RAILS_ENV}
ENV BUNDLE_PATH="/gems"

RUN apk add --no-cache \
    openssl \
    tzdata \
    postgresql-client \
    imagemagick \
    git \
  && gem install bundler

RUN if [ "$RAILS_ENV" != "production" ]; then \
  apk add --no-cache nodejs yarn; \
  fi

COPY --from=pre-builder /gems/ /gems/
COPY --from=pre-builder /app /app

WORKDIR /app

EXPOSE 3000