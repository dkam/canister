FROM ruby:4.0.1-slim

# Install system dependencies
RUN apt-get update -qq \
  && apt-get install -y --no-install-recommends \
    ffmpeg \
    imagemagick \
    nodejs \
    yarn \
    build-essential \
    git \
  && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Install Ruby dependencies
COPY Gemfile Gemfile.lock ./
RUN bundle install

# Install frontend dependencies (if package.json exists)
COPY package.json* yarn.lock* ./
RUN if [ -f package.json ]; then yarn install; fi

# Copy application code
COPY . .

# Expose Puma port
EXPOSE 3000

# Set environment variables
ENV RAILS_ENV=production
ENV RAILS_LOG_TO_STDOUT=true
ENV RAILS_SERVE_STATIC_FILES=true

# Start Puma
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
