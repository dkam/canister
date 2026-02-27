ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __dir__)

require 'bundler/setup' # Set up gems listed in the Gemfile.
require 'ostruct' # Required explicitly for Ruby 3.4+ (removed from default load path)

# TODO: The docker container doesn't like bootsnap
#require 'bootsnap/setup' # Speed up boot time by caching expensive operations.
