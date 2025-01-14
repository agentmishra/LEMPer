#!/usr/bin/env bash

# Dry run
DRYRUN=false

# Decorator
RED=31
GREEN=32
YELLOW=33

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

function continue_or_exit() {
    local prompt="$1"
    echo_color "$YELLOW" -n "$prompt"
    read -p " [Y/n] " yn
    if [[ "$yn" == N* || "$yn" == n* ]]; then
        echo "Cancelled."
        exit 0
    fi
}

function header_msg() {
clear
cat <<- _EOF_
#========================================================================#
#         LEMPer v1.0.0 for Ubuntu Server , Written by ESLabs.ID         #
#========================================================================#
#     A small tool to install Nginx + MariaDB (MySQL) + PHP on Linux     #
#                                                                        #
#       For more information please visit https://eslabs.id/lemper       #
#========================================================================#
_EOF_
}

function footer_msg() {
cat <<- _EOF_
#==========================================================================#
#         Thank's for installing LNMP stack using LEMPer Installer         #
#        Found any bugs / errors / suggestions? please let me know         #
#    If this script useful, don't forget to buy me a coffee or milk :D     #
#   My PayPal is always open for donation, here https://paypal.me/masedi   #
#                                                                          #
#         (c) 2014-2019 - ESLabs.ID - https://eslabs.id/lemper ;)          #
#==========================================================================#
_EOF_
}
