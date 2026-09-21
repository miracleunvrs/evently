FROM ruby:4.0-slim
WORKDIR /app
RUN apt-get update -qq && apt-get install --no-install-recommends -y build-essential libpq-dev libsodium23 curl && rm -rf /var/lib/apt/lists/*
COPY Gemfile Gemfile.lock ./
RUN bundle install
COPY . .
ENV RAILS_ENV=production RAILS_LOG_TO_STDOUT=1 RAILS_SERVE_STATIC_FILES=1
EXPOSE 3000
CMD ["sh", "-c", "bin/rails db:prepare && bin/rails db:seed && bundle exec puma -C config/puma.rb"]
