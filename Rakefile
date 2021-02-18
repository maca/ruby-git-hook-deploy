# Rakefile
require "./app/app"
require "sinatra/activerecord/rake"


namespace :deploy do
  task :rsync do
    cmd = %w[
    rsync --exclude='/.git'
    --filter="dir-merge,- .gitignore"
    -a . rails@172.105.78.116:/var/www/smallest-of-worlds/
  ].join(' ')

    system cmd
  end
end
