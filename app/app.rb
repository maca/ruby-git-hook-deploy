ENV['DATABASE_URL'] ||=
  'postgresql://localhost/test_app_development?pool=5'


require 'rubygems'
require 'bundler'

Bundler.require(:default, ENV['RACK_ENV'] ||= 'development')


$LOAD_PATH.unshift File.join(__dir__, '..', 'lib')
$LOAD_PATH.unshift File.join(__dir__, '.')

require 'models/post'


Time.zone_default = Time.find_zone!('Berlin')


class App < Sinatra::Base
  set :root,    File.expand_path('..', __dir__)
  set :views,   File.join(root, 'app', 'views')
  set :static,  true
  set :logging, true

  get '/' do
    erb :index
  end
end
