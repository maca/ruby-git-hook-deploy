# Change to match your CPU core count You can check available worker
# numbers with $ grep -c processor /proc/cpuinfo
# also see the comment in the nginx.conf
workers 2
threads 1, 6


app = 'ruby_test_app'
shared_dir = "/home/ops_user/web/#{app}"


# Set up socket location
bind "unix:///tmp/#{app}.sock"


# Logging
#stdout_redirect "#{shared_dir}/log/puma.stdout.log", "#{shared_dir}/log/puma.stderr.log", true


# Set master PID and state locations
pidfile "#{shared_dir}/#{app}.pid"
#state_path "#{shared_dir}/pids/puma.state"
#activate_control_app


#on_worker_boot do
#  require "active_record"
#  ActiveRecord::Base.connection.disconnect! rescue ActiveRecord::ConnectionNotEstablished
#  ActiveRecord::Base.establish_connection(YAML.load_file("#{app_dir}/config/database.yml")[rails_env])
#end
