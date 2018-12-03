#!/bin/bash

LOG_INFO()
{
    local date format
    if [ $# -lt 1 ]; then
        return
    fi
    
    date="$(date "+%Y-%m-%d %H:%M:%S:%3N")"
    format="\\e[32m[${date}] \\e[34m${1}\\e[0m\\n"

    shift 1

    printf "${format}" "${@}"
}

LOG_WARN()
{
    local date format

    if [ $# -lt 1 ]; then
        return
    fi
    
    date="$(date "+%Y-%m-%d %H:%M:%S:%3N")"
    format="\\e[32m[${date}] \\e[33m${1}\\e[0m\\n"

    shift 1

    printf "${format}" "${@}"
}

LOG_ERROR()
{
    local date format

    if [ $# -lt 1 ]; then
        return
    fi
    
    date="$(date "+%Y-%m-%d %H:%M:%S:%3N")"
    format="\\e[32m[${date}] \\e[31m${1}\\e[0m\\n"

    shift 1

    printf "${format}" "${@}"
}

LOG_ERROR_AND_EXIT()
{
    local date format

    if [ $# -lt 1 ]; then
        return
    fi
    
    date="$(date "+%Y-%m-%d %H:%M:%S:%3N")"
    format="\\e[32m[${date}] \\e[31m${1}\\e[0m\\n"

    shift 1

    printf "${format}" "${@}"

    exit 1
}