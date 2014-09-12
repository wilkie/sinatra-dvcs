require 'bundler'
Bundler::require

# Application root
class Application < Sinatra::Base
end

require_relative 'git'
require_relative 'hg'
