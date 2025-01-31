#!/bin/bash

# +-------------------------------------------------------------------------+
# | NgxVhost - Simple Nginx vHost Configs File Generator                    |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2019 ESLabs (https://eslabs.id/ngxvhost)             |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@eslabs.id so we can send you a copy immediately.             |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <eslabs.id@gmail.com>                          |
# | Original concept: Fideloper <https://gist.github.com/fideloper/9063376> |
# +-------------------------------------------------------------------------+

# Version Control
APP_NAME=$(basename "$0")
APP_VERSION="1.6.0"
LAST_UPDATE="24/06/2019"

INSTALL_DIR=$(pwd)


# Decorator
RED=91
GREEN=92
YELLOW=93

DRYRUN=false

function begin_color() {
    color="$1"
    echo -e -n "\e[${color}m"
}

function end_color() {
    echo -e -n "\e[0m"
}

function echo_color() {
    color="$1"
    shift
    begin_color "$color"
    echo "$@"
    end_color
}

function error() {
    local error_message="$@"
    echo_color "$RED" -n "Error: " >&2
    echo "$@" >&2
}

# Prints an error message and exits with an error code.
function fail() {
    error "$@"

    # Normally I'd use $0 in "usage" here, but since most people will be running
    # this via curl, that wouldn't actually give something useful.
    echo >&2
    echo "For usage information, run this script with --help" >&2
    exit 1
}

function status() {
    echo_color "$GREEN" "$@"
}

function warning() {
    echo_color "$YELLOW" "$@"
}

# If we set -e or -u then users of this script will see it silently exit on
# failure.  Instead we need to check the exit status of each command manually.
# The run function handles exit-status checking for system-changing commands.
# Additionally, this allows us to easily have a dryrun mode where we don't
# actually make any changes.
INITIAL_ENV=$(printenv | sort)
function run() {
    if "$DRYRUN"; then
        echo_color "$YELLOW" -n "would run"
        echo " $@"
        env_differences=$(comm -13 <(echo "$INITIAL_ENV") <(printenv | sort))

        if [ -n "$env_differences" ]; then
            echo "  with the following additional environment variables:"
            echo "$env_differences" | sed 's/^/    /'
        fi
    else
        if ! "$@"; then
            error "Failure running '$@', exiting."
            exit 1
        fi
    fi
}

# May need to run this as sudo!
# I have it in /usr/local/bin and run command from anywhere, using sudo.
if [ $(id -u) -ne 0 ]; then
    error "You must be root: sudo ${APP_NAME}"
    exit 1  #error
fi

# Check prerequisite packages
if [[ ! -f $(which unzip) || ! -f $(which git) || ! -f $(which rsync) ]]; then
    warning "Ngxvhost requires rsync, unzip and git, please install it first"
    echo "help: sudo apt-get install rsync unzip git"
    exit 0
fi

#
# Show Usage, Output to STDERR
#
function show_usage {
cat <<- _EOF_
$APP_NAME $APP_VERSION
Creates Nginx virtual host (vHost) configuration file.

Requirements:
  * Nginx setup uses /etc/nginx/sites-available and /etc/nginx/sites-enabled
  * PHP FPM setup uses /etc/php/{version_number}/fpm/

Usage: $APP_NAME [options]...

Options:
  -u, --username <virtual-host username>
      Use username added from adduser/useradd. Do not use root user.

  -d, --domain-name <server domain name>
      Any valid domain name and/or sub domain name is allowed.
      i.e. example.com or sub.example.com

  -w, --webroot <web root>
      Web root is absolute path to the website root directory.
      i.e. /home/username/Webs/example.test

  -f, --framework <website framework>
      Type of web framework and cms, i.e. default.
      Currently supported framework and cms: default (vanilla php), codeigniter, laravel, phalcon, wordpress, wordpress-ms.

      Another framework and cms will be added soon.

  -s, --clone-skeleton
      Clone default skeleton for selected framework.

  -c, --enable-fastcgi-cache
      Enable PHP FastCGI cache module.

  -h, --help
      Print this message and exit.

Example:
$APP_NAME -u username -d example.com -f default -w /home/username/Webs/example.dev

For more details visit https://ngxtools.eslabs.id !
Mail bug reports and suggestions to <eslabs.id@gmail.com>
_EOF_
}

#
# Output Default virtual host (vHost) skeleton, fill with user input
# To be outputted into new file
# Work for default and WordPress site
#
function create_vhost_default() {
cat <<- _EOF_
server {
    listen 80;
    #listen [::]:80 default_server ipv6only=on;

    ## Make site accessible from world web.
    server_name ${SERVERNAME} www.${SERVERNAME};

    ## Log Settings.
    access_log /var/log/nginx/${SERVERNAME}_access.log;
    error_log  /var/log/nginx/${SERVERNAME}_error.log error;

    #charset utf-8;

    ## Virtual host root directory.
    set \$root_path '${WEBROOT}';
    root \$root_path;
    index index.php index.html index.htm;

    ## Mod PageSpeed directives configuration.
    include /etc/nginx/conf.vhost/pagespeed_disabled.conf;

    ## Global directives configuration.
    include /etc/nginx/conf.vhost/block.conf;
    include /etc/nginx/conf.vhost/staticfiles.conf;
    include /etc/nginx/conf.vhost/restrictions.conf;

    ## Default vhost directives configuration.
    include /etc/nginx/conf.vhost/site_${FRAMEWORK}.conf;

    ## Pass the PHP scripts to FastCGI server listening on Unix socket.
    location ~ \.php$ {
        try_files \$uri =404;

        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_index index.php;

        # Include FastCGI Params.
        include /etc/nginx/fastcgi_params;

        # Include FastCGI Configs.
        include /etc/nginx/conf.vhost/fastcgi.conf;

        # Uncomment to Enable PHP FastCGI cache.
        include /etc/nginx/conf.vhost/fastcgi_cache_disabled.conf;

        # FastCGI socket, change to fits your own socket!
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;
    }

    ## Uncomment to enable error page directives configuration.
    #include /etc/nginx/conf.vhost/errorpage.conf;

    ## Add your custom site directives here.
}
_EOF_
}

#
# Output Laravel virtual host skeleton, fill with user input
# To be outputted into new file
#
function create_vhost_laravel() {
cat <<- _EOF_
server {
    listen 80;
    #listen [::]:80 default_server ipv6only=on;

    ## Make site accessible from world web.
    server_name ${SERVERNAME} www.${SERVERNAME};

    ## Log Settings.
    access_log /var/log/nginx/${SERVERNAME}_access.log;
    error_log  /var/log/nginx/${SERVERNAME}_error.log error;

    #charset utf-8;

    ## Virtual host root directory.
    set \$root_path '${WEBROOT}/public';
    root \$root_path;
    index index.php index.html index.htm;

    ## Mod PageSpeed directives configuration.
    include /etc/nginx/conf.vhost/pagespeed_disabled.conf;

    ## Global directives configuration.
    include /etc/nginx/conf.vhost/block.conf;
    include /etc/nginx/conf.vhost/staticfiles.conf;
    include /etc/nginx/conf.vhost/restrictions.conf;

    ## Default vhost directives configuration.
    include /etc/nginx/conf.vhost/site_${FRAMEWORK}.conf;

    ## Pass the PHP scripts to FastCGI server listening on Unix socket.
    location ~ \.php$ {
        fastcgi_split_path_info    ^(.+\.php)(/.+)$;
        fastcgi_index index.php;

        # Include FastCGI Params.
        include /etc/nginx/fastcgi_params;

        # Overwrite FastCGI Params here.
        #fastcgi_param PATH_INFO        \$fastcgi_path_info;
        fastcgi_param SCRIPT_FILENAME    \$document_root\$fastcgi_script_name;
        #fastcgi_param SCRIPT_NAME        \$fastcgi_script_name;

        # Include FastCGI Configs.
        include /etc/nginx/conf.vhost/fastcgi.conf;

        # Uncomment to Enable PHP FastCGI cache.
        include /etc/nginx/conf.vhost/fastcgi_cache_disabled.conf;

        # FastCGI socket, change to fits your own socket!
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;
    }

    ## Uncomment to enable error page directives configuration.
    #include /etc/nginx/conf.vhost/errorpage.conf;

    ## Add your custom site directives here.
}
_EOF_
}

#
# Output Phalcon virtual host skeleton, fill with user input
# To be outputted into new file
#
function create_vhost_phalcon() {
cat <<- _EOF_
server {
    listen 80;
    #listen [::]:80 default_server ipv6only=on;

    ## Make site accessible from world web.
    server_name ${SERVERNAME} www.${SERVERNAME};

    ## Log Settings.
    access_log /var/log/nginx/${SERVERNAME}_access.log;
    error_log  /var/log/nginx/${SERVERNAME}_error.log error;

    #charset utf-8;

    ## Virtual host root directory.
    set \$root_path '${WEBROOT}/public';
    root \$root_path;
    index index.php index.html index.htm;

    ## Mod PageSpeed directives configuration.
    include /etc/nginx/conf.vhost/pagespeed_disabled.conf;

    ## Global directives configuration.
    include /etc/nginx/conf.vhost/block.conf;
    include /etc/nginx/conf.vhost/staticfiles.conf;
    include /etc/nginx/conf.vhost/restrictions.conf;

    ## Default vhost directives configuration.
    include /etc/nginx/conf.vhost/site_${FRAMEWORK}.conf;

    ## Pass the PHP scripts to FastCGI server listening on Unix socket.
    location ~ \.php {
        fastcgi_split_path_info    ^(.+\.php)(/.+)$;
        fastcgi_index index.php;

        # Include FastCGI Params.
        include /etc/nginx/fastcgi_params;

        # Overwrite FastCGI Params here.
        fastcgi_param PATH_INFO            \$fastcgi_path_info;
        fastcgi_param SCRIPT_FILENAME    \$document_root\$fastcgi_script_name;
        fastcgi_param SCRIPT_NAME        \$fastcgi_script_name;

        # Phalcon PHP custom params.
        fastcgi_param APPLICATION_ENV    development;

        # Include FastCGI Configs.
        include /etc/nginx/conf.vhost/fastcgi.conf;

        # Uncomment to Enable PHP FastCGI cache.
        include /etc/nginx/conf.vhost/fastcgi_cache_disabled.conf;

        # FastCGI socket, change to fits your own socket!
        fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.${USERNAME}.sock;
    }

    ## Uncomment to enable error page directives configuration.
    #include /etc/nginx/conf.vhost/errorpage.conf;

    ## Add your custom site directives here.
}
_EOF_
}

#
# Output Wordpress Multisite vHost header
#
function prepare_vhost_wpms() {
cat <<- _EOF_
# Wordpress Multisite Mapping for Nginx (Requires Nginx Helper plugin).
map \$http_host \$blogid {
    default     0;
    include     ${WEBROOT}/wp-content/uploads/nginx-helper/map.conf;
}

_EOF_
}

#
# Output index.html skeleton for default index page
# To be outputted into new index.html file in document root
#
function create_index_file() {
cat <<- _EOF_
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
    body {
        width: 35em;
        margin: 0 auto;
        font-family: Tahoma, Verdana, Arial, sans-serif;
    }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed using LEMPer. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
LEMPer and ngxTools support is available at
<a href="https://github.com/joglomedia/LEMPer/issues">LEMPer git</a>.</p>

<p><em>Thank you for using nginx, ngxTools, and LEMPer.</em></p>

<p style="font-size:90%;">Generated using <em>LEMPer</em> from <a href="https://eslabs.id/lemper">Nginx vHost Tool</a>, a simple nginx web server management tool.</p>
</body>
</html>
_EOF_
}

function create_fpm_pool_conf() {

cat <<- _EOF_
[$USERNAME]
user = $USERNAME
group = $USERNAME

listen = /run/php/php${PHP_VERSION}-fpm.\$pool.sock
listen.owner = $USERNAME
listen.group = $USERNAME
listen.mode = 0666
;listen.allowed_clients = 127.0.0.1

pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.process_idle_timeout = 30s;
pm.max_requests = 500

request_slowlog_timeout = 6s
slowlog = /var/log/php${PHP_VERSION}-fpm_slow.\$pool.log

chdir = /

security.limit_extensions = .php .php3 .php4 .php5 .php7 .php${PHP_VERSION//./}

;php_admin_value[sendmail_path] = /usr/sbin/sendmail -t -i -f you@yourmail.com
php_flag[display_errors] = on
php_admin_value[error_log] = /var/log/php${PHP_VERSION}-fpm.\$pool.log
php_admin_flag[log_errors] = on
;php_admin_value[memory_limit] = 32M
_EOF_
}

function install_wordpress() {
    # Check WordPress install directory
    if [ $CLONE_SKELETON == true ]; then
        #echo -n "Should we copy WordPress skeleton into document root? [Y/n]: "
        #read instal

        # Clone new WordPress files
        if [ ! -d ${WEBROOT}/wp-admin ]; then
            status "Copying WordPress skeleton files..."

            run wget --no-check-certificate -q https://wordpress.org/latest.zip
            run unzip -q latest.zip
            run rsync -r wordpress/ ${WEBROOT}
            run rm -f latest.zip
            run rm -fr wordpress
            #git clone https://github.com/WordPress/WordPress.git $WEBROOT/
        else
            warning "It seems that WordPress installation file already exists."
        fi
    else
        # create default index file
        status "Creating default WordPress index file..."

        create_index_file > ${WEBROOT}/index.html
        run chown $USERNAME:$USERNAME ${WEBROOT}/index.html
    fi

    # Pre-install nginx helper plugin
    if [[ -d ${WEBROOT}/wp-content/plugins && ! -d ${WEBROOT}/wp-content/plugins/nginx-helper ]]; then
        status "Copying Nginx Helper plugin into WordPress install..."
        warning "Please activate the plugin after WordPress installation."

        run wget --no-check-certificate -q https://downloads.wordpress.org/plugin/nginx-helper.zip
        run unzip -q nginx-helper.zip
        run mv nginx-helper ${WEBROOT}/wp-content/plugins/
        run rm -f nginx-helper.zip
        #git clone https://github.com/rtCamp/nginx-helper.git $WEBROOT/wp-content/plugins/nginx-helper
    fi
}

# Main App
#
function init_app() {
    getopt --test
    if [ "$?" != 4 ]; then
        # Even Centos 5 and Ubuntu 10 LTS have new-style getopt, so I don't expect
        # this to be hit in practice on systems that are actually able to run
        # Nginx web server.
        fail "Your version of getopt is too old.  Exiting with no changes made."
    fi

    opts=$(getopt -o u:d:f:w:p:cshv \
      -l username:,domain-name:,framework:,webroot:,php-version: \
      -l enable-fastcgi-cache,clone-skeleton,help,version \
      -n "$APP_NAME" -- "$@")

    # Sanity Check - are there an arguments with value?
    if [ $? != 0  ]; then
        fail "Terminating..."
        exit 1
    fi

    eval set -- "$opts"

    # Default value
    FRAMEWORK="default"
    PHP_VERSION="7.3"
    ENABLE_FASTCGI_CACHE=false
    ENABLE_PAGESPEED=false
    #ENABLE_HTTPS=false
    CLONE_SKELETON=false
    DRYRUN=false

    COUNT_ARGS=0

    # Parse flags
    while true; do
        case $1 in
            -u | --username) shift
                USERNAME="$1"
                COUNT_ARGS=$(($COUNT_ARGS + 1))
                shift
            ;;
            -d | --domain-name) shift
                SERVERNAME="$1"
                COUNT_ARGS=$(($COUNT_ARGS + 1))
                shift
            ;;
            -w | --webroot) shift
                WEBROOT="${1%%+(/)}"
                COUNT_ARGS=$(($COUNT_ARGS + 1))
                shift
            ;;
            -f | --framework) shift
                FRAMEWORK="$1"
                COUNT_ARGS=$(($COUNT_ARGS + 1))
                shift
            ;;
            -p | --php-version) shift
                PHP_VERSION="$1"
                shift
            ;;
            -c | --enable-fastcgi-cache) shift
                ENABLE_FASTCGI_CACHE=true
            ;;
            -s | --clone-skeleton) shift
                CLONE_SKELETON=true
            ;;
            -h | --help) shift
                show_usage
                exit 0
            ;;
            -v | --version) shift
                echo "$APP_NAME version $APP_VERSION"
                exit 1
            ;;
            --) shift
                break
            ;;
            *)
                fail "Invalid argument: $1"
                exit 1
            ;;
        esac
    done

    if [ $COUNT_ARGS -ge 4 ]; then
        # Additional Check - are user already exist?
        if [[ -z $(getent passwd $USERNAME) ]]; then
            fail -e "\nError: The user ${USERNAME} does not exist, please add new user first! Aborting...
                Help: useradd username, try ${APP_NAME} -h for more helps"
        fi

        # Check PHP fpm version is exists?
        if [[ -n $(which php-fpm${PHP_VERSION}) && -d /etc/php/${PHP_VERSION}/fpm ]]; then
            # Additional check - is FPM user's pool already exist
            if [ ! -f "/etc/php/${PHP_VERSION}/fpm/pool.d/${USERNAME}.conf" ]; then
                warning "The PHP${PHP_VERSION} FPM pool configuration for user ${USERNAME} doesn't exist."
                echo "Creating new PHP-FPM pool [${USERNAME}] configuration..."

                create_fpm_pool_conf > /etc/php/${PHP_VERSION}/fpm/pool.d/${USERNAME}.conf
                run touch "/var/log/php${PHP_VERSION}-fpm_slow.${USERNAME}.log"

                # Restart PHP FPM
                echo "Restart php${PHP_VERSION}-fpm configuration..."
                run service "php${PHP_VERSION}-fpm" restart

                status "New PHP-FPM pool [${USERNAME}] has been created."
            fi
        else
            fail "There is no PHP${PHP_VERSION} version installed, please install it first! Aborting..."
        fi

        # Additional Check - ensure that Nginx's configuration meets the requirement
        if [ ! -d /etc/nginx/sites-available ]; then
            fail "It seems that your Nginx installation doesn't meet ${APP_NAME} requirements. Aborting..."
        fi

        # Vhost file
        vhost_file="/etc/nginx/sites-available/${SERVERNAME}.conf"

        # Check if vhost not exists.
        if [ ! -f "${vhost_file}" ]; then
            echo "Adding domain ${SERVERNAME} to virtual host..."

            # Creates document root
            if [ ! -d ${WEBROOT} ]; then
                echo "Creating web root directory: ${WEBROOT}..."

                run mkdir -p ${WEBROOT}
                run chown -R ${USERNAME}:${USERNAME} ${WEBROOT}
                run chmod 755 ${WEBROOT}
            fi

            echo "Selecting ${FRAMEWORK^} framewrok..."

            # Ugly hacks for custom framework-specific configs + Skeleton auto installer.
            case $FRAMEWORK in
                laravel)
                    echo "Setting up Laravel framework virtual host..."

                    # Install Laravel framework skeleton
                    if [ ! -f ${WEBROOT}/server.php ]; then
                        #echo -n "Should we install Laravel skeleton into document root? [Y/n]: "
                        #read INSTALL_LV

                        # Clone new Laravel files
                        if [ $CLONE_SKELETON == true ]; then
                            echo "Copying Laravel skeleton files..."
                            run git clone "https://github.com/laravel/laravel.git" \
                                          "${WEBROOT}"
                        else
                            # Create default index file
                            echo "Creating default index files..."
                            create_index_file > ${WEBROOT}/index.html
                            run chown $USERNAME:$USERNAME ${WEBROOT}/index.html
                        fi
                    else
                        warning "Laravel skeleton files already exists."
                    fi

                    # Create vhost
                    echo "Creating virtual host file: ${vhost_file}..."
                    create_vhost_laravel > ${vhost_file}

                    status "New domain ${SERVERNAME} has been added to virtual host."
                ;;

                phalcon)
                    echo "Setting up Phalcon framework virtual host..."
                    # TODO: Auto install Phalcon PHP framework skeleton

                    # Create vhost
                    echo "Creating virtual host file: ${vhost_file}..."
                    create_vhost_phalcon > ${vhost_file}

                    status "New domain ${SERVERNAME} has been added to virtual host."
                ;;

                wordpress)
                    echo "Setting up WordPress virtual host..."

                    # Install WordPress
                    install_wordpress

                    # Create vhost
                    echo "Creating virtual host file: ${vhost_file}..."
                    create_vhost_default > ${vhost_file}

                    status "New domain ${SERVERNAME} has been added to virtual host."
                ;;

                wordpress-ms)
                    echo "Setting up WordPress Multi-site virtual host..."

                    # Install WordPress
                    install_wordpress

                    # Pre-populate blog id mapping, used by Nginx vhost conf
                    run mkdir ${WEBROOT}/wp-content/uploads
                    run mkdir ${WEBROOT}/wp-content/uploads/nginx-helper
                    run touch ${WEBROOT}/wp-content/uploads/nginx-helper/map.conf

                    echo "Creating virtual host file: ${vhost_file}..."

                    # Prepare vhost specific rule for WordPress Multisite
                    prepare_vhost_wpms > ${vhost_file}

                    # Create vhost
                    create_vhost_default >> ${vhost_file}

                    status "New domain ${SERVERNAME} has been added to virtual host."
                ;;

                filerun)
                    echo "Setting up FileRun virtual host..."

                    # Install Laravel framework skeleton
                    if [ ! -f ${WEBROOT}/system/classes/filerun.php ]; then
                        # Clone new Filerun files
                        if [ $CLONE_SKELETON == true ]; then
                            echo "Copying FileRun skeleton files..."
                            run wget -q -O FileRun.zip http://www.filerun.com/download-latest
                            run unzip -q FileRun.zip -d ${WEBROOT}
                            run rm -f FileRun.zip
                        else
                            # Create default index file
                            echo "Creating default index files..."
                            create_index_file > ${WEBROOT}/index.html
                            run chown $USERNAME:$USERNAME ${WEBROOT}/index.html
                        fi
                    else
                        warning "FileRun skeleton files already exists."
                    fi

                    # Create default vhost
                    echo "Creating virtual host file: ${vhost_file}..."
                    create_vhost_default > ${vhost_file}

                    status "New domain ${SERVERNAME} has been added to virtual host."
                ;;

                codeigniter|mautic|default)
                    # Create default index file
                    create_index_file > ${WEBROOT}/index.html
                    run chown $USERNAME:$USERNAME ${WEBROOT}/index.html

                    # Create default vhost
                    echo "Creating virtual host file: ${vhost_file}..."
                    create_vhost_default > ${vhost_file}

                    status "New domain ${SERVERNAME} has been added to virtual host."
                ;;

                *)
                    # Not supported framework/cms, abort.
                    fail "Sorry, your framework/cms [${FRAMEWORK^}] is not supported yet. Aborting..."
                    exit 1
                ;;
            esac

            # Enable FastCGI cache?
            if [ $ENABLE_FASTCGI_CACHE == true ]; then
                echo "Enable FastCGI cache for ${SERVERNAME}..."

                if [ -f /etc/nginx/conf.vhost/site_${FRAMEWORK}_cached.conf ]; then
                    # enable cached directives
                    sed -i "s/site_${FRAMEWORK}.conf/site_${FRAMEWORK}_cached.conf/g" ${vhost_file}

                    # enable fastcgi_cache conf
                    sed -i "s/fastcgi_cache_disabled.conf/fastcgi_cache.conf/g" ${vhost_file}
                else
                    warning "FastCGI cache is not enabled. There is no cached version of ${FRAMEWORK^} directives."
                fi
            fi

            # Enable PageSpeed?
            if [ $ENABLE_PAGESPEED == true ]; then
                echo "Enable Mod PageSpeed for ${SERVERNAME}..."

                if [[ -f /etc/nginx/conf.vhost/pagespeed.conf && -f /etc/nginx/modules-enabled/50-mod-pagespeed.conf ]]; then
                    # enable mod pagespeed
                    sed -i "s/pagespeed_disabled.conf/pagespeed.conf/g" ${vhost_file}
                else
                    warning "Mod PageSpeed is not enabled."
                fi
            fi

            # Fix document root ownership
            run chown -R $USERNAME:$USERNAME ${WEBROOT}

            # Fix document root permission
            if [ "$(ls -A ${WEBROOT})" ]; then
                run find "${WEBROOT}" -type d -print0 | xargs -0 chmod 755
                run find "${WEBROOT}" -type f -print0 | xargs -0 chmod 644
            fi

            echo "Enable ${SERVERNAME} virtual host..."

            # Enable site
            #cd "/etc/nginx/sites-enabled"
            run ln -s /etc/nginx/sites-available/${SERVERNAME}.conf /etc/nginx/sites-enabled/${SERVERNAME}.conf

            # Reload Nginx
            echo "Reloading Nginx configuration..."
            #service nginx reload -s
            run service nginx reload -s

            if [[ -f /etc/nginx/sites-enabled/${SERVERNAME}.conf && -e /var/run/nginx.pid ]]; then
                status "Your ${SERVERNAME} successfully added to Nginx virtual host.";
            fi

            if [ "${FRAMEWORK}" = "wordpress-ms" ]; then
                echo >&2
                warning "Note: You're installing Wordpress Multisite."
                warning "You should activate Nginx Helper plugin to work properly."
            fi
        else
            error "vHost config file for ${SERVERNAME} already exists. Aborting..."
        fi
    else
        echo "$APP_NAME: missing optstring argument."
        echo "Try '$APP_NAME --help' for more information."
    fi
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
init_app "$@"
