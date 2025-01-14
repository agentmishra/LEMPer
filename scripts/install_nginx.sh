#!/usr/bin/env bash

# Include decorator
BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )

if [ "$(type -t run)" != "function" ]; then
    . ${BASEDIR}/decorator.sh
fi

function nginx_install_menu() {
    echo -e "\nAvailable Nginx installer to use:
    1). Repository
    2). Source
    -------------------"
    echo -n "Select your Nginx installer [1-2]: "
    read NgxInstaller

    case $NgxInstaller in
        1)
            echo -e "\nInstalling Nginx from package repository..."
            run apt-get install -y --allow-unauthenticated ${NGX_PACKAGE}
        ;;
        2)
            echo -e "\nInstalling Nginx from source..."
            run ${BASEDIR}/install_nginx_from_source.sh -v latest-stable -n latest \
                --dynamic-module --extra-modules -y
        ;;
        *)
            warning "No installer found."
            continue_or_exit "Retry Nginx installation?"
            nginx_install_menu
        ;;
    esac

    if [ ! -d /etc/nginx/modules-available ]; then
        run mkdir /etc/nginx/modules-available
    fi

    if [ ! -d /etc/nginx/modules-enabled ]; then
        run mkdir /etc/nginx/modules-enabled
    fi

    if [ ! -d /etc/nginx/sites-available ]; then
        run mkdir /etc/nginx/sites-available
    fi

    if [ ! -d /etc/nginx/sites-enabled ]; then
        run mkdir /etc/nginx/sites-enabled
    fi

    # Custom Nginx dynamic modules configuration
    if [[ "$NgxInstaller" == "2" ]]; then

        if [[ -f /usr/lib/nginx/modules/ngx_pagespeed.so && ! -f /etc/nginx/modules-available/mod-pagespeed.conf ]]; then
            run bash -c 'echo "load_module \"/usr/lib/nginx/modules/ngx_pagespeed.so\";" > \
                /etc/nginx/modules-available/mod-pagespeed.conf'
        fi

        if [[ -f /usr/lib/nginx/modules/ngx_http_geoip_module.so && ! -f /etc/nginx/modules-available/mod-http-geoip.conf ]]; then
            run bash -c 'echo "load_module \"/usr/lib/nginx/modules/ngx_http_geoip_module.so\";" > \
                /etc/nginx/modules-available/mod-http-geoip.conf'
        fi

        if [[ -f /usr/lib/nginx/modules/ngx_http_image_filter_module.so && ! -f /etc/nginx/modules-available/mod-http-image-filter.conf ]]; then
            run bash -c 'echo "load_module \"/usr/lib/nginx/modules/ngx_http_image_filter_module.so\";" > \
                /etc/nginx/modules-available/mod-http-image-filter.conf'
        fi

        if [[ -f /usr/lib/nginx/modules/ngx_http_xslt_filter_module.so && ! -f /etc/nginx/modules-available/mod-http-xslt-filter.conf ]]; then
            run bash -c 'echo "load_module \"/usr/lib/nginx/modules/ngx_http_xslt_filter_module.so\";" > \
                /etc/nginx/modules-available/mod-http-xslt-filter.conf'
        fi

        if [[ -f /usr/lib/nginx/modules/ngx_mail_module.so && ! -f /etc/nginx/modules-available/mod-mail.conf ]]; then
            run bash -c 'echo "load_module \"/usr/lib/nginx/modules/ngx_mail_module.so\";" > \
                /etc/nginx/modules-available/mod-mail.conf'
        fi

        if [[ -f /usr/lib/nginx/modules/ngx_stream_module.so && ! -f /etc/nginx/modules-available/mod-stream.conf ]]; then
            run bash -c 'echo "load_module \"/usr/lib/nginx/modules/ngx_stream_module.so\";" > \
                /etc/nginx/modules-available/mod-stream.conf'
        fi

        echo -en "\nEnable Nginx dynamic modules? [Y/n]: "
        read enableDM
        if [[ "$enableDM" == Y* || "$enableDM" == y* ]]; then

            if [ ! -f /etc/nginx/modules-enabled/50-mod-pagespeed.conf ]; then
                run ln -s /etc/nginx/modules-available/mod-pagespeed.conf /etc/nginx/modules-enabled/50-mod-pagespeed.conf
            fi

            #run ln -s /etc/nginx/modules-available/mod-http-geoip.conf /etc/nginx/modules-enabled/50-mod-http-geoip.conf
        fi

        # Nginx init script
        if [ ! -f /etc/init.d/nginx ]; then
            run cp nginx/init.d/nginx /etc/init.d/
            run chmod ugo+x /etc/init.d/nginx
        fi

        # Nginx systemd script
        if [ ! -f /lib/systemd/system/nginx.service ]; then
            run cp nginx/systemd/nginx.service /lib/systemd/system/
        fi
    fi

    #run chown -hR www-data:root /etc/nginx/modules-available
}

function init_nginx_install() {
    echo -e "\nWelcome to Nginx installation script"

    # Install Nginx custom
    nginx_install_menu

    # Copy custom Nginx Config
    if [ -f /etc/nginx/nginx.conf ]; then
        run mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.old
    fi

    run cp -f nginx/nginx.conf /etc/nginx/
    run cp -f nginx/fastcgi_cache /etc/nginx/
    run cp -f nginx/fastcgi_https_map /etc/nginx/
    run cp -f nginx/fastcgi_params /etc/nginx/
    run cp -f nginx/http_cloudflare_ips /etc/nginx/
    run cp -f nginx/http_proxy_ips /etc/nginx/
    run cp -f nginx/proxy_cache /etc/nginx/
    run cp -f nginx/proxy_params /etc/nginx/
    run cp -f nginx/upstream.conf /etc/nginx/
    run cp -fr nginx/conf.vhost/ /etc/nginx/
    run cp -fr nginx/ssl/ /etc/nginx/

    if [ -f /etc/nginx/sites-available/default ]; then
        run mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.old
    fi

    run cp -f nginx/sites-available/default /etc/nginx/sites-available/
    run cp -f nginx/sites-available/sample-site-phpmyadmin.dev.conf /etc/nginx/sites-available/
    run cp -f nginx/sites-available/sample-wordpress.dev.conf /etc/nginx/sites-available/
    run cp -f nginx/sites-available/sample-wordpress-ms.dev.conf /etc/nginx/sites-available/
    run cp -f nginx/sites-available/ssl.sample-site.dev.conf /etc/nginx/sites-available/

    if [ -f /etc/nginx/sites-enabled/default ]; then
        run unlink /etc/nginx/sites-enabled/default
    fi

    run ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/01-default

    if [ -d /usr/share/nginx/html ]; then
        run chown -hR www-data:root /usr/share/nginx/html
    fi

    # Nginx cache directory
    if [ ! -d /var/cache/nginx ]; then
        run mkdir /var/cache/nginx
        run chown -hR www-data:root /var/cache/nginx
    fi

    if [ ! -d /var/cache/nginx/fastcgi_cache ]; then
        run mkdir /var/cache/nginx/fastcgi_cache
        run chown -hR www-data:root /var/cache/nginx/fastcgi_cache
    fi

    if [ ! -d /var/cache/nginx/proxy_cache ]; then
        run mkdir /var/cache/nginx/proxy_cache
        run chown -hR www-data:root /var/cache/nginx/proxy_cache
    fi

    # Check IP Address
    IPAddr=$(curl -s http://ipecho.net/plain)
    # Make default server accessible from IP address
    run sed -i s@localhost.localdomain@${IPAddr}@g /etc/nginx/sites-available/default

    # Restart Nginx server
    if [[ $(ps -ef | grep -v grep | grep nginx | wc -l) > 0 ]]; then
        run service nginx restart
        status -e "\nNginx web server restarted successfully."
    elif [[ -n $(which nginx) ]]; then
        run service nginx start

        if [[ $(ps -ef | grep -v grep | grep nginx | wc -l) > 0 ]]; then
            status -e "\nNginx web server started successfully."
        else
            warning -e "\nSomething wrong with Nginx installation."
        fi
    fi
}

# Start running things from a call at the end so if this script is executed
# after a partial download it doesn't do anything.
if [[ -n $(which nginx) && -d /etc/nginx/sites-available ]]; then
    warning -e "\nNginx web server already exists. Installation skipped..."
else
    init_nginx_install "$@"
fi
