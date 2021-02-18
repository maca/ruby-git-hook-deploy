# Deploy an app using git hooks, or poor man's Heroku.


Apart from briefly using capistrano for deploying Ruby applications,
most of my earlier deployment experience and tooling expectations
comes from Heroku.

As powerful as Kubernetes is, I believe that Heroku
is a great solution for organizations that don't want to have a
dedicated ops team, and the user interface and ease is just
unbeatable.

Here are a few of the things I appreciate the most about Heroku:


- Deploy and check what has been deployed using git
- Stream app logs
- Run jobs for the deployed app
- Spawn a console
- Edit environment variables from command line interface
- Dump and restore a database
- Set autoscale parameters
- Provision services
- Set up domains
- etc...


## Twelve-Factor

Heroku requires the app to conform to a set of conventions called
[The Twelve-Factor App](https://12factor.net/).

Among the requirements is that the app logs to stdout and stderr,
that all of the configuration is performed via environment variables,
that a single code base can be deployed to multiple environments,
and that the app is stateless and disposable in order to facilitate
horizontal scaling. This last requirement might not be suitable for
all kind of services, such as Elixir/Erlang ones that hold a state and
might not function so well in dynamic environments.


## Poor man's Heroku

I usually go to Heroku when I have to do client work because I
can just transfer the ownership to the customer later.

One of my last micro projects was a favour for friends, and I wanted
to keep it as simple as I could. They needed enough space to let users
upload videos and I didn't want to mess with S3, which is usual when
deploying an app to Heroku, given the disposable nature of 12 factor
apps.

I wanted to set everything up for them to edit
content and styles, and deploy on their own. I asked them to get a
small linode server, wrote a simple sinatra app, set up some
simple deploy script using git, taught them to use git, and off they
went.

The first version was just a non bare git repository and a script that
pushes to the repo, resets git HEAD to latest commit, and restarts the
service.

Git has to be instructed to allow pushing a branch to a non bare repo:
`$ git config receive.denyCurrentBranch ignore`.


Later I iterated through this idea using git hooks to build the
app and reject push in case build failed, systemd to supervise the
process, and journalctl to capture and stream logs comming from stdout
and stderr.


## Setup

Here I am going step by step on the setup process for demostration
purposes, though I've hacked together a shell script that automates
the setup, including creating the deploy user, uploading ssh keys,
setting up systemd unit, setting up nginx virtual host with ssl, and
sudo configuration to allow the deploy user to run as sudo only
relevant service commands.

The script also provides an interface for some of the herokuish
features I use the most: log streaming, terminal spawning, running
jobs, process management (start, stop, restart, etc.).

One thing I appreciate about this setup is that git log is
the authoritative source on what has been deployed and where, and I can
do ops stuff all from the local repo directory.

My server and my local machine both run Arch Linux, but mainstream
distros are using systemd to the dismay of many Linux users. I don't
have a strong adverse opinion about this, and I like systemd's
interface.



The following asumptions are made about the server:

- Postgres is running
- Ruby and Ruby Bundler binaries are globally available
- Nginx is running
- Let's Encrypt's Certbot with Nginx plugin is installed


### Deploy user

I am using the same user for my local machine and the server, the
user has sudo privileges in the server.
First, we need to create a deploy user on the remote server,

```Shell
[local] $ ssh -t bitmunge.com "sudo useradd -m ops_user"
```

and copy our local ssh keys.

```Shell
[local] $ scp ~/.ssh/id_rsa.pub bitmunge.com:/tmp && \
  ssh -t bitmunge.com "sudo su ops_user -c 'mkdir ~/.ssh && \
    chmod 700 ~/.ssh && \
    cat /tmp/id_rsa.pub >> ~/.ssh/authorized_keys'"; \
  ssh bitmunge.com "rm /tmp/id_rsa.pub"
```

Since we're going to use postgres we need to create a postgres user
that is allowed to create databases.
```Shell
[local] $ ssh -t bitmunge.com \
  "sudo su - postgres -c 'createuser --createdb ops_user'"
```

### Repo setup

Next we set up the bare git repository we're going to push to,

```Shell
[local] $ ssh -t ops_user@bitmunge.com \
  "mkdir -p ~/web/ruby_test_app/repo && \
  cd ~/web/ruby_test_app/repo && \
  git init --bare"

```


and an environment file that will provide configuration for the
systemd unit running the app and the transient run commands.

Here I am using vim to edit the path below, but you can use whatever
text editor is available at your server.


```Shell
[local] $ ssh -t ops_user@bitmunge.com \
  "vim /home/ops_user/web/ruby_test_app/env"
```
```Shell
DATABASE_URL='postgresql://localhost/ruby_test_app_production?pool=5'
RACK_ENV=production
```


### Git hook

Similarly, we create the git `update` hook with the contents below.
This script will run after a change has been pushed to the
repo's master branch, and it will checkout the code in a directory in the
same level as the repo.

There it will run a `bin/deploy` script part of the codebase, the
option `-e` means that if any of the steps of the script fail
execution will be interrupted, returning a non zero exit code.

If the script fails the hook fails, and if the hook fails no push is
allowed.


```Shell
[local] $ ssh -t ops_user@bitmunge.com \
  "vim /home/ops_user/web/ruby_test_app/repo/hooks/update"
```
```Shell
#!/usr/bin/env sh

TARGET="$PWD/../build_dir"

# only deploy on master
if [ "$1" = "refs/heads/master" ]; then
  mkdir -p $TARGET
  git --work-tree=$TARGET --git-dir=$PWD checkout -f $3
  cd $TARGET

  set -a
  source ../env

  PS4="\033[1;33m>>>\033[0m " sh -ex bin/deploy
  EXIT_CODE=$?
  rm $TARGET -rf
  exit $EXIT_CODE
fi
```

The git hook has to be executable.
```Shell
ssh -t ops_user@bitmunge.com \
  "chmod +x /home/ops_user/web/ruby_test_app/repo/hooks/update"
```

### Systemd unit

And we need a systemd unit.
```Shell
[local] $ ssh -t bitmunge.com \
  "sudo vim /etc/systemd/system/ruby_test_app.service"
```
```
[Unit]
Description=Run Ruby Test App
After=network.target

[Service]
WorkingDirectory=/home/ops_user/web/ruby_test_app/service
ExecStart=/home/ops_user/web/ruby_test_app/service/bin/run
Restart=always
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ruby_test_app
User=ops_user
EnvironmentFile=/home/ops_user/web/ruby_test_app/env

[Install]
WantedBy=multi-user.target
```


### Limited sudo for deploy user

By creating this file with the following content our deploy user
will be able to run these commands and only these commands as super user.

```Shell
[local] $ ssh -t bitmunge.com "sudo visudo -f /etc/sudoers.d/ops_user-ruby_test_app"
```
```Shell
Cmnd_Alias OPS_USER_RUBY_TEST_APP = \
    /bin/systemctl start   ruby_test_app.service, \
    /bin/systemctl stop    ruby_test_app.service, \
    /bin/systemctl status  ruby_test_app.service, \
    /bin/systemctl enable  ruby_test_app.service, \
    /bin/systemctl disable ruby_test_app.service, \
    /bin/systemctl restart ruby_test_app.service, \
    /usr/bin/journalctl -u ruby_test_app.service, \
    /usr/bin/journalctl -u ruby_test_app.service -f

ops_user ALL = (root) NOPASSWD: OPS_USER_RUBY_TEST_APP
```


### First deploy

Next we set up our deploy remote and push local changes to it.

```Shell
[local] $ git clone ruby_test_app
[local] $ cd ruby_test_app
[local] $ git remote add production \
  ssh://ops_user@bitmunge.com/home/ops_user/web/ruby_test_app/repo
[local] $ git push production master
```


### Try again

Did it fail? Maybe adding `bundle exec rake db:create` before `bundle
exec rake db:migrate` in the `bin/deploy` script only for this one
occassion, and pushing again will do...


### Process management

We can manage and inspect the process like this. `enable` is for
starting the process on server boot.

```Shell
[local] $ ssh -t ops_user@bitmunge.com \
  "sudo systemctl start ruby_test_app.service"

[local] $ ssh -t ops_user@bitmunge.com \
  "sudo systemctl enable ruby_test_app.service"

[local] $ ssh -t ops_user@bitmunge.com \
  "sudo systemctl status ruby_test_app.service"
```


### Nginx virtual host

Make sure that nginx config in the server includes sites-enabled
directory, and the directory exists.
```Nginx
# /etc/nginx/nginx.conf
http {
    ...
    include /etc/nginx/sites-enabled/*;
}
```


Then we can create the nginx virtual host.
I am using unix socket instead of port, the socket path is hardcoded in
puma.rb #TODO: fix

```
[local] ssh -t bitmunge.com \
  "sudo vim /etc/nginx/sites-enabled/ruby-test-app.bitmunge.com"
```
```Nginx
upstream ruby-test-app {
    server unix:/tmp/ruby_test_app.sock;
}

server {
    server_name ruby-test-app.bitmunge.com;
    listen 80;

    location / {
        proxy_pass http://ruby-test-app;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $http_host;
        proxy_redirect off;
    }
}
```


### SSL certificate

Of course there is no excuse not to always serve web apps using https.

This will take care of updating the nginx virtual host with a
[Let's encrypt](https://letsencrypt.org/donate/) certificate
automatically.
```Shell
[local] $ ssh -t bitmunge.com \
  "sudo certbot --nginx -d ruby-test-app.bitmunge.com"
```


### Roll your own

Inside the bin directory for the local repo there is a shell script
named `sushi`.

`setup` task is an automation of the previous steps.


Running


```
$ git remote add production \
  ssh://ops_user@bitmunge.com/home/ops_user/app
$ sushi setup
$ git push production master
```

Would produce the following structure:

```
home
└─ ops_user
   └─ app
      ├── env
      ├── build_dir (temporary)
      │   ├── bin
      │   │   ├── ...
      │   │   └── deploy
      │   └── ...
      ├── repo
      │   ├── ...
      │   ├── hooks
      │   │   ├── ...
      │   │   └── update
      └── service
          ├── bin
          │   ├── ...
          │   └── run
          └── ...

/tmp
 └── app.socket
```

The app should have a `bin/deploy` and `bin/run` scripts, and it
should be deployed to `service`.
Repo will be checked out to `build_dir`, which is temporary.
service should contain the build artifact, in the simplest case might
just be a checkout of the repo.

This is meant to be used only by me ;)


```
$ bin/sushi
Usage: sushi [-r git-remote] task [args1 [args2]]
  -r git-remote:
    git remote hosting the app repo and deployment

  task
    setup       # server set up
    ps:start    # start process
    ps:stop     # stop process
    ps:status   # obtain information on the process status
    ps:restart  # restart process
    ps:enable   # enable process startup on server boot
    ps:disable  # disable process startup on server boot
    env         # cat environment
    env:edit    # edit and validate environment locally using $EDITOR
    logs        # display latest log entries
    logs:follow # stream logs in realtime
    run         # run a command on the server
        examples:
          \`$ sushi run rake db:migrate\`
          \`$ sushi run bin/console\`

Configuration
  configuration is through git
    git config sushi.remote # default remote, when not providing -r
    git config sushi.host   # override default host
    git config sushi.run    # wrap sushi run command
       examples:
          \`$ git config sushi.remote staging\`
          \`$ git config sushi.run \"bundle exec\"\`
```
