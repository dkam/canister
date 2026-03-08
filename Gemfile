source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '~> 8.1.0'
# Use sqlite3 as the database for Active Record
gem 'sqlite3', '~> 2.1'
# Use Puma as the app server
gem 'puma', '~>6'
# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
# gem 'jbuilder', '~> 2.5'
# Solid Trifecta — database-backed cache, queue, and cable (replaces Redis)
gem 'solid_cache'
gem 'solid_queue'
gem 'solid_cable'
# Use ActiveModel has_secure_password
gem 'bcrypt', '~> 3.1.7'

# Reduces boot times through caching; required in config/boot.rb
#gem 'bootsnap', '>= 1.1.0', require: false

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin AJAX possible
#gem 'rack-cors', '~>2'

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
# gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]
gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]

# Stash

gem 'xxhash'
gem 'ostruct'    # required explicitly for Ruby 3.4+ (removed from default load path)
gem 'benchmark'  # required explicitly for Ruby 3.5+ (mini_magick dependency)

# Scraper
gem 'mechanize'
gem 'nkf' # required explicitly for Ruby 3.4+ (removed from default load path)
gem 'selenium-webdriver'#, '3.11.0'

gem 'pagy'
gem 'scoped_search'#, '4.1.3'
gem 'streamio-ffmpeg'#, '3.0.2'
gem 'fastimage'#, '2.1.3'
gem 'dotenv-rails'
gem 'rubyzip'#, '1.2.1'
gem 'naturally'#, '2.1.0'
gem 'mini_magick'#, '4.8.0'
gem 'ruby-vips'
#gem 'ruby-filemagic'#, '0.7.2'
#gem 'filemagic'#, '0.7.2'
gem 'activerecord-import'#, '0.23.0'

# Frontend
gem 'propshaft'
gem 'tailwindcss-rails'
gem 'turbo-rails'
gem 'stimulus-rails'
gem 'importmap-rails'

group :development, :test do
  gem 'debug', platforms: [:mri, :mingw, :x64_mingw]
end

group :test do
  gem 'webmock'
  gem 'vcr'
end


