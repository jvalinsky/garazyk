#!/bin/bash

# kaszlak bash completion
# Install: source this file or copy to /etc/bash_completion.d/

_kaszlak() {
    local cur prev words cword
    _init_completion || return

    local commands="serve status account admin invite repo init daemon nuke oauth help version"
    local serve_opts="--port --data-dir --config --log-level --log-components --foreground --help"
    local account_opts="list info create deactivate reactivate delete update-email update-handle update-plc-endpoint"
    local invite_opts="list create revoke"
    local admin_opts="list add remove create"
    local repo_opts="list get root create-record delete-record repair"

    # Complete command names
    if [[ $cword -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
        return
    fi

    local cmd="${words[1]}"
    case "$cmd" in
        serve|s|start|run|server)
            if [[ "$cur" == --* ]]; then
                COMPREPLY=( $(compgen -W "$serve_opts" -- "$cur") )
            fi
            ;;
        account|a)
            if [[ $cword -eq 2 ]]; then
                COMPREPLY=( $(compgen -W "$account_opts" -- "$cur") )
            elif [[ "$cur" == --* ]]; then
                COMPREPLY=( $(compgen -W "--limit --filter --email --handle --password" -- "$cur") )
            fi
            ;;
        invite|i)
            if [[ $cword -eq 2 ]]; then
                COMPREPLY=( $(compgen -W "$invite_opts" -- "$cur") )
            elif [[ "$cur" == --* ]]; then
                COMPREPLY=( $(compgen -W "--max-uses" -- "$cur") )
            fi
            ;;
        admin)
            if [[ $cword -eq 2 ]]; then
                COMPREPLY=( $(compgen -W "$admin_opts" -- "$cur") )
            elif [[ "$cur" == --* ]]; then
                COMPREPLY=( $(compgen -W "--email --handle --password" -- "$cur") )
            fi
            ;;
        repo|r)
            if [[ $cword -eq 2 ]]; then
                COMPREPLY=( $(compgen -W "$repo_opts" -- "$cur") )
            fi
            ;;
        help)
            COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
            ;;
        status|health|h)
            if [[ "$cur" == --* ]]; then
                COMPREPLY=( $(compgen -W "--verbose --json" -- "$cur") )
            fi
            ;;
    esac
}

complete -F _kaszlak kaszlak
