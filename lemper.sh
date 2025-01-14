#!/bin/bash

# +-------------------------------------------------------------------------+
# | LEMPer.sh is a Simple LNMP Installer for Ubuntu                         |
# |-------------------------------------------------------------------------+
# | Features    :                                                           |
# |     - Nginx 1.10                                                        |
# |     - PHP 5.6/7.0/7.1/7.2/7.3                                           |
# |     - Zend OpCache 7.0.3                                                |
# |     - Memcached 1.4.14                                                  |
# |     - ionCube Loader                                                    |
# |     - SourceGuardian Loader                                             |
# |     - MariaDB 10 (MySQL drop-in replacement)                            |
# |     - Adminer (PhpMyAdmin replacement)                                  |
# | Min requirement   : GNU/Linux Ubuntu 14.04 or Linux Mint 17             |
# | Last Update       : 24/06/2019                                          |
# | Author            : ESLabs.ID (eslabs.id@gmail.com)                     |
# | Version           : 1.0.0                                               |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2019 ESLabs (https://eslabs.id/lemper)               |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@eslabs.id so we can send you a copy immediately.             |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <eslabs.id@gmail.com>                          |
# +-------------------------------------------------------------------------+

set -e  # Work even if somebody does "sh thisscript.sh".

# Include decorator
if [ "$(type -t run)" != "function" ]; then
    . scripts/decorator.sh
fi

# Make sure only root can run this installer script
if [ $(id -u) -ne 0 ]; then
    error "This script must be run as root..."
    exit 1
fi

# Make sure this script only run on Ubuntu install
if [ ! -f "/etc/lsb-release" ]; then
    warning -e "\nThis installer only work on Ubuntu server..."
    exit 1
else
    # Variables
    arch=$(uname -p)
    IPAddr=$(hostname -i)

    # export lsb-release vars
    . /etc/lsb-release

    MAJOR_RELEASE_NUMBER=$(echo $DISTRIB_RELEASE | awk -F. '{print $1}')

    if [[ "$DISTRIB_ID" == "LinuxMint" ]]; then
        DISTRIB_RELEASE="LM${MAJOR_RELEASE_NUMBER}"
    fi
fi

function create_swap() {
    echo "Enabling 1GiB swap..."

    L_SWAP_FILE="/lemper-swapfile"
    fallocate -l 1G $L_SWAP_FILE && \
    chmod 600 $L_SWAP_FILE && \
    chown root:root $L_SWAP_FILE && \
    mkswap $L_SWAP_FILE && \
    swapon $L_SWAP_FILE
}

function check_swap() {
    echo -e "\nChecking swap..."

    if free | awk '/^Swap:/ {exit !$2}'; then
        swapsize=$(free -m | awk '/^Swap:/ { print $2 }')
        status "Swap size ${swapsize}MiB."
    else
        warning "No swap detected"
        create_swap
        status "Adding swap completed..."
    fi
}

function create_account() {
    if [[ -n $1 ]]; then
        username="$1"
    else
        username="lemper" # default account
    fi

    echo -e "\nCreating default LEMPer account..."

    if [[ -z $(getent passwd "${username}") ]]; then
        katasandi=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)
        run useradd -d /home/${username} -m -s /bin/bash ${username}
        echo "${username}:${katasandi}" | chpasswd
        run usermod -aG sudo ${username}

        if [ -d /home/${username} ]; then
            run mkdir /home/${username}/webapps
            run chown -hR ${username}:${username} /home/${username}/webapps
        fi

        status "Username ${username} created."
    else
        warning "Username ${username} already exists."
    fi
}

### Main ###
case $1 in
    --install)
        header_msg
        echo -e "\nStarting LEMP stack installation...\nPlease ensure that you're on a fresh box install!\n"
        read -t 10 -p "Press [Enter] to continue..." </dev/tty

        ### Clean up ###
        . scripts/cleanup_server.sh

        ### ADD Repos ###
        . scripts/add_repo.sh

        ### Chcek swap ###
        check_swap

        ### Create default account ###
        create_account "lemper"

        ### Nginx Installation ###
        . scripts/install_nginx.sh

        ### PHP Installation ###
        . scripts/install_php.sh
        . scripts/install_memcache.sh

        ### MySQL Database Installation ###
        . scripts/install_mariadb.sh

        ### Redis Database Installation ###
        . scripts/install_redis.sh

        ### Mail Server Installation ###
        . scripts/install_postfix.sh

        ### Install Let's Encrypt SSL ###
        . scripts/install_letsencrypt.sh

        ### Addon Installation ###
        . scripts/install_tools.sh

        ### FINAL STEP ###
        # Cleaning up all build dependencies hanging around on production server?
        run apt-get autoremove -y

        status -e "\nLEMPer installation has been completed."

        ### Recap ###
        if [[ ! -z "$katasandi" ]]; then
            status -e "\nHere is your default system account information:

        Server IP : ${IPAddr}
        SSH Port  : 22
        Username  : lemper
        Password  : ${katasandi}

        Access to your Database administration (Adminer):
        http://${IPAddr}:8082/

        Access to your File manager (FileRun):
        http://${IPAddr}:8083/

        Please keep it private!
        "
        fi

        echo -e "\nNow, you can reboot your server and enjoy it!\n"
    ;;
    --uninstall)
        header_msg
        echo -e "\nAre you sure to remove LEMP stack installation?\n"
        read -t 10 -p "Press [Enter] to continue..." </dev/tty

        # Remove nginx
        echo -e "\nUninstalling Nginx...\n"

        if [[ -n $(which nginx) ]]; then
            # Stop Nginx web server process
            run service nginx stop

            # Remove Nginx
            if [ $(dpkg-query -l | grep nginx-common | awk '/nginx-common/ { print $2 }') ]; then
            	echo "Nginx-common package found. Removing..."
                run apt-get remove -y nginx-common
            elif [ $(dpkg-query -l | grep nginx-custom | awk '/nginx-custom/ { print $2 }') ]; then
            	echo "Nginx-custom package found. Removing..."
                run apt-get remove -y nginx-custom
            elif [ $(dpkg-query -l | grep nginx-stable | awk '/nginx-stable/ { print $2 }') ]; then
            	echo "Nginx-stable package found. Removing..."
                run apt-get remove -y nginx-stable
            else
            	echo "Nginx package not found. Possibly installed from source."

                # Only if nginx package not installed / nginx installed from source)
                if [ -f /usr/sbin/nginx ]; then
                    run rm -f /usr/sbin/nginx
                fi

                if [ -f /etc/init.d/nginx ]; then
                    run rm -f /etc/init.d/nginx
                fi

                if [ -f /lib/systemd/system/nginx.service ]; then
                    run rm -f /lib/systemd/system/nginx.service
                fi

                if [ -d /usr/lib/nginx/ ]; then
                    run rm -fr /usr/lib/nginx/
                fi

                if [ -d /etc/nginx/modules-available ]; then
                    run rm -fr /etc/nginx/modules-available
                fi

                if [ -d /etc/nginx/modules-enabled ]; then
                    run rm -fr /etc/nginx/modules-enabled
                fi
            fi

            echo -en "Completely remove Nginx configuration files (This action is not reversible)? [Y/n]: "
            read rmngxconf
            if [[ "${rmngxconf}" == Y* || "${rmngxconf}" == y* ]]; then
        	    echo "All your Nginx configuration files deleted permanently..."
        	    run rm -fr /etc/nginx
        	    # Remove nginx-cache
        	    run rm -fr /var/cache/nginx
        	    # Remove nginx html
        	    run rm -fr /usr/share/nginx
            fi
        else
            warning "Nginx installation not found."
        fi

        # Remove PHP
        echo -e "\nUninstalling PHP FPM...\n"

        if [[ -n $(which php-fpm5.6) \
            || -n $(which php-fpm7.0) \
            || -n $(which php-fpm7.1) \
            || -n $(which php-fpm7.2) \
            || -n $(which php-fpm7.3) ]]; then

            # Stop default PHP FPM process
            if [[ $(ps -ef | grep -v grep | grep php-fpm | grep 7.3 | wc -l) > 0 ]]; then
                service php7.3-fpm stop
            fi

            # Stop Memcached server process
            run service memcached stop

            # Stop Redis server process
            run service redis-server stop

            run apt-get --purge remove -y php* php*-* pkg-php-tools spawn-fcgi geoip-database snmp memcached redis-server

            echo -n "\nCompletely remove PHP-FPM configuration files (This action is not reversible)? [Y/n]: "
            read rmfpmconf
            if [[ "${rmfpmconf}" == Y* || "${rmfpmconf}" == y* ]]; then
        	    echo "All your PHP-FPM configuration files deleted permanently..."
        	    run rm -fr /etc/php/
        	    # Remove ioncube
                run rm -fr /usr/lib/php/loaders/
            fi
        else
            warning "PHP installation not found."
        fi

        # Remove MySQL
        echo -e "\nUninstalling MariaDB (SQL DBMS)...\n"

        if [[ -n $(which mysql) ]]; then
            # Stop MariaDB mysql server process
            run service mysql stop

            run apt-get remove -y mariadb-server-10.1 mariadb-client-10.1 mariadb-server-core-10.1 mariadb-common mariadb-server libmariadbclient18 mariadb-client-core-10.1

            echo -n "\nCompletely remove MariaDB SQL database and configuration files (This action is not reversible)? [Y/n]: "
            read rmsqlconf
            if [[ "${rmsqlconf}" == Y* || "${rmsqlconf}" == y* ]]; then
        	    echo "All your SQL database and configuration files deleted permanently."
        	    run rm -fr /etc/mysql
        	    run rm -fr /var/lib/mysql
            fi
        else
            warning "MariaDB installation not found."
        fi

        # Remove default user
        echo -n "\nRemove default LEMPer account? [Y/n]: "
        read rmdefaultuser
        if [[ "${rmdefaultuser}" == Y* || "${rmdefaultuser}" == y* ]]; then
            if [[ -z $(getent passwd "${username}") ]]; then
                run userdel -r lemper
                status "Default LEMPer account deleted."
            else
                warning "Default LEMPer account not found."
            fi
        fi

        # Remove unnecessary packages
        #run apt-get autoremove -y
    ;;
    --help)
        echo "Please read the README file for more information!"
        exit 0
    ;;
    *)
        fail "Invalid argument: $1"
        exit 1
    ;;
esac

footer_msg
