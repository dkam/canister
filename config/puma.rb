# Puma configuration

# Max threads
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
threads threads_count, threads_count

# Port
port ENV.fetch("PORT") { 3000 }

# Environment
environment ENV.fetch("RAILS_ENV") { "development" }

# Workers for multi-process mode (uncomment in production)
# workers ENV.fetch("WEB_CONCURRENCY") { 2 }
# preload_app!

# Worker timeout (kill workers that hang for 60 seconds)
worker_timeout 3600 if ENV.fetch("RAILS_ENV", "development") == "production"

# Allow puma to be restarted by `rails restart` command.
plugin :tmp_restart

# On worker boot
# on_worker_boot do
#   ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
# end
