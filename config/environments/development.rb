Rails.application.configure do
  # Code is reloaded on every request.
  config.enable_reloading = true

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports.
  config.consider_all_requests_local = true

  # Enable server timing.
  config.server_timing = true

  # Use Solid Cache.
  config.action_controller.perform_caching = true
  config.cache_store = :solid_cache_store

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local_media

  # Don't care if the mailer can't send.
  config.action_mailer.raise_delivery_errors = false
  config.action_mailer.perform_caching = false

  # Print deprecation notices to the Rails logger.
  config.active_support.report_deprecations = true

  # Raise an error on page load if there are pending migrations.
  config.active_record.migration_error = :page_load

  # Highlight code that triggered database queries in logs.
  config.active_record.verbose_query_logs = true

  # Append comments with runtime information tags to SQL queries in logs.
  config.active_record.query_log_tags_enabled = true

  # Highlight code that enqueued background job in logs.
  config.active_job.verbose_enqueue_logs = true

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Uncomment if you wish to allow Action Cable access from any origin.
  # config.action_cable.disable_request_forgery_protection = true

  # Use polling file watcher (evented watcher breaks with Solid Cache's db/cache_schema.rb file)
  config.file_watcher = ActiveSupport::FileUpdateChecker

  # Verbose redirect logs.
  config.action_dispatch.verbose_redirect_logs = true
end
