# Pack On My Back Server

## Future Considerations

- Interesting Docker setup https://medium.com/@tiangolo/angular-in-docker-with-nginx-supporting-environments-built-with-multi-stage-docker-builds-bb9f1724e984

## Migration

- Haven't done this yet, but will need to write out the process eventually
- Seems to be a popular package for it https://github.com/db-migrate/node-db-migrate
- Would recommend spinning up a dummy instance, testing with it and figuring out how to change scheme, then doing for first time on real db (after a snapshot of course)

## Run server

`$ node server.js`

## Logging Into Digital Ocean Server

- SSH into server
    - `$ ssh <user>@<ip_address>`
    - `$ ssh bclynch@138.68.63.87`
- Switch user
    - `$ su - bclynch`
- Go to root
    - `$ exit`

## Digital Ocean

### Server Setup

- Linux terminal basics series https://www.digitalocean.com/community/tutorials/an-introduction-to-the-linux-terminal
- Create droplet
- Setup SSH https://www.digitalocean.com/community/tutorials/how-to-use-ssh-keys-with-digitalocean-droplets
- Inital server setup (user + firewall) https://www.digitalocean.com/community/tutorials/initial-server-setup-with-ubuntu-16-04
    - Common firewall rules / commands https://www.digitalocean.com/community/tutorials/ufw-essentials-common-firewall-rules-and-commands
- Setup hostname https://www.digitalocean.com/community/tutorials/how-to-set-up-a-host-name-with-digitalocean
    - Create 'A' records
    - Point nameservers from registrar to DO https://www.digitalocean.com/community/tutorials/how-to-point-to-digitalocean-nameservers-from-common-domain-registrars#registrar-namecheap
- Install nginx https://www.digitalocean.com/community/tutorials/how-to-install-nginx-on-ubuntu-16-04
- Create server blocks for multiple domains https://www.digitalocean.com/community/tutorials/how-to-set-up-nginx-server-blocks-virtual-hosts-on-ubuntu-16-04
- Secure nginx with SSL https://www.digitalocean.com/community/tutorials/how-to-secure-nginx-with-let-s-encrypt-on-ubuntu-16-04#step-4-%E2%80%94-obtaining-an-ssl-certificate
    - Issue as of writing https://github.com/certbot/certbot/issues/5405#issuecomment-356498627
    - Webroot aka path is how its set up in nginx. Example would be /var/www/bclynch.com/html
- Get node app rolling https://www.digitalocean.com/community/tutorials/how-to-set-up-a-node-js-application-for-production-on-ubuntu-16-04
    - Install node
    - Setup pm2
    - Setup reverse proxy for nginx
- Setup SFTP https://www.digitalocean.com/community/tutorials/how-to-use-sftp-to-securely-transfer-files-with-a-remote-server
- Setup mail https://www.digitalocean.com/community/tutorials/how-to-set-up-zoho-mail-with-a-custom-domain-managed-by-digitalocean-dns

#### Add New Key To Existing Server

- Suppose you have a new computer you want to log in with and need to setup ssh. Our server does not allow for password login so we need a workaround
- Login to digital ocean and head to the access console. Login to root
- `$ sudo nano /etc/ssh/sshd_config`
    - Change the line PasswordAuthentication from no to yes
- Save and exit the file and run `$ sudo systemctl reload sshd.service` and `sudo systemctl reload ssh` for config to take effect
- We can now login to root from our own terminal via password (where copy / paste actually works)
- `$ cd ~/.ssh`
- `$ nano authorized_keys`
- Copy the pub key from the local computer and paste in here
    - `$ cat ~/.ssh/id_rsa.pub` will display the pub key so we can copy
- Now we should be able to access root via ssh. Go ahead and revert the PasswordAuthentication from yes to no
- Save and exit the file and run `$ sudo systemctl reload sshd.service` and `sudo systemctl reload ssh` for config to take effect
- Do the same for any users you have to login as well so we can directly login through them

### Putting code on server

- First we want to build our code to minify and all. With Ionic we can do this with the following command
    - `$ npm run ionic:build -- --prod`

### Updating Servers

- Server should be updated frequently with the following:
    - `$ apt-get update && apt-get upgrade`

### ENV Variables

- Used to pass in secret information from the server into Node application
- Use .env file to maintain your vars
    - Syntax: MYAPIKEY=ndsvn2g8dnsb9hsg
    - Env vars are always all capital letters + underscores
    - This can be used in Node with process.env.MYAPIKEY variable
    - Always put .env it gitignore
- Check out your existing variables with printenv command in bash
- AWS automatically pulls env vars https://docs.aws.amazon.com/sdk-for-javascript/v2/developer-guide/loading-node-credentials-environment.html

### nginx

- To stop your web server, you can type:
`$ sudo systemctl stop nginx`

- To start the web server when it is stopped, type:
`$ sudo systemctl start nginx`

- To stop and then start the service again, type:
`$ sudo systemctl restart nginx`

- If you are simply making configuration changes, Nginx can often reload without dropping connections. To do this, this command can be used:
`$ sudo systemctl reload nginx`

- By default, Nginx is configured to start automatically when the server boots. If this is not what you want, you can disable this behavior by typing:
`$ sudo systemctl disable nginx`

- To re-enable the service to start up at boot, you can type:
`$ sudo systemctl enable nginx`

### SFTP 

- Login: `$ sftp username@remote_hostname_or_IP`
- Current directory: `$ pwd`
- Get files: `$ get remoteFile`
- Get directory and all its contents: `$ get -r someDirectory`
- Transfer to remote: `$ put localFile`
- Transfer entire directory: `$ put -r localDirectory`
- End session: `$ bye`

Also cyberduck makes this easier.....

### Bash

#### Handy Commands

- Open file in editor
    - `$ sudo nano <path>`
    - ^x to quit then y to save
- Remove folder and all contents
    - `$ rm -rf <name>`
- Create folder
    - `$ mkdir <name>`
- Create file
    - `$ touch <name>`

### PM2

- PM2 provides an easy way to manage and daemonize applications (run them in the background as a service).
- Applications that are running under PM2 will be restarted automatically if the application crashes or is killed, but an additional step needs to be taken to get the application to launch on system startup (boot or reboot).

#### Start App

- `$ pm2 start <file>`

- The startup subcommand generates and configures a startup script to launch PM2 and its managed processes on server boots:

- `$ pm2 startup systemd`

- Run the command that was generated to set PM2 up to start on boot

- This will create a systemd unit which runs pm2 for your user on boot. This pm2 instance, in turn, runs hello.js. You can check the status of the systemd unit with systemctl:

- `$ systemctl status pm2-bclynch`

#### Sub Commands

PM2 provides many subcommands that allow you to manage or look up information about your applications. Note that running pm2 without any arguments will display a help page, including example usage, that covers PM2 usage in more detail than this section of the tutorial.

- Stop an application with this command (specify the PM2 App name or id):

`$ pm2 stop app_name_or_id`

- Restart an application with this command (specify the PM2 App name or id):

`$ pm2 restart app_name_or_id`

- The list of applications currently managed by PM2 can also be looked up with the list subcommand:

`$ pm2 list`

- More information about a specific application can be found by using the info subcommand (specify the PM2 App name or id):

`$ pm2 info example`

- The PM2 process monitor can be pulled up with the monit subcommand. This displays the application status, CPU, and memory usage:

`$ pm2 monit`

- Now that your Node.js application is running, and managed by PM2, let's set up the reverse proxy.

## Local Postgraphql Setup

- Run `$ psql -f laze_schema.sql`
- Run `$ psql -f laze_data.sql`
- To update: 
    - Run `$ psql -f schema_drop.sql`
    - Run the above setup again

## AWS

*AWS allows multiple schemas whereas Heorku does not!*
### Creating an RDS DB

- Important reminders:
    - Set the option for making the db public so you get an endpoint for it. Must be done on creation!
    - Set inbound security group to be all traffic (something like 0.0.0.0) otherwise it hangs and doesn't work
### Basic Setup
- Install AWS CLI `$ brew install awscli`
- Launch a new RDS instance from AWS console
- Run `$ aws rds describe-db-instances` to check on your db's info
- Change the parameter group of your instance to force ssl. (set to one)
### Connect to Postgres GUI
- http://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_ConnectToPostgreSQLInstance.html
    - In the SSL tab check 'Use SSL' and require it.
- Can right click on a db and select 'Execute SQL File'. Load up the schema then load up any data.
### Connect to psql
- psql --host=<instance_endpoint> --port=<port_number> --username <username> --password --dbname=<dbname>
- psql --host=laze.c0up3bfsdxiy.us-east-1.rds.amazonaws.com --port=5432 --username bclynch --password --dbname=laze
- Make sure you identify the schema with your query statements + semicolons to get it to work properly.
- Need to change the security group setting to allow inbound traffic from anywhere to avoid 503