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
# gem 'bcrypt', '~> 3.1.7'

# Use Capistrano for deployment
# gem 'capistrano-rails', group: :development

# Reduces boot times through caching; required in config/boot.rb
#gem 'bootsnap', '>= 1.1.0', require: false

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin AJAX possible
#gem 'rack-cors', '~>2'

group :development, :test do
  gem 'debug', platforms: [:mri, :mingw, :x64_mingw]
end

group :development do
  gem 'listen'
end

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
# gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]
gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]

# Stash

# API
gem 'graphql', '~> 1.13'
gem 'graphql-errors' #, '0.2.0'
gem 'ostruct'    # required explicitly for Ruby 3.4+ (removed from default load path)
gem 'benchmark'  # required explicitly for Ruby 3.5+ (mini_magick dependency)

# Scraper
gem 'mechanize'
gem 'nkf' # required explicitly for Ruby 3.4+ (removed from default load path)
gem 'selenium-webdriver'#, '3.11.0'

# gem 'passenger', '5.1.2', require: "phusion_passenger/rack_handler"
gem 'kaminari'#, '1.1.1'
gem 'scoped_search'#, '4.1.3'
gem 'streamio-ffmpeg'#, '3.0.2'
gem 'fastimage'#, '2.1.3'
gem 'figaro'#, '1.1.1'
gem 'rubyzip'#, '1.2.1'
gem 'naturally'#, '2.1.0'
gem 'mini_magick'#, '4.8.0'
#gem 'ruby-filemagic'#, '0.7.2'
#gem 'filemagic'#, '0.7.2'
gem 'activerecord-import'#, '0.23.0'
