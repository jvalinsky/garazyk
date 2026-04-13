#compdef kaszlak

_kaszlak_commands=(
  'serve:Start the kaszlak server'
  'status:Check kaszlak status'
  'account:Manage accounts'
  'admin:Manage administrators'
  'invite:Manage invite codes'
  'repo:Inspect user repositories'
  'init:Initialize a new kaszlak instance'
  'daemon:Run kaszlak as a background daemon'
  'nuke:Delete all kaszlak data'
  'oauth:OAuth operations'
  'help:Show help information'
  'version:Show version information'
)

_kaszlak_serve_opts=(
  '--port:Port to listen on (default: 2583)'
  '--data-dir:Data directory'
  '--config:Config file path (default: ./config.json)'
  '--log-level:Log level (debug, info, warn, error)'
  '--log-components:Comma-separated components to enable'
  '--foreground:Run in foreground'
  '--help:Show help'
)

_kaszlak_account_subcommands=(
  'list:List all accounts'
  'info:Show account details'
  'create:Create a new account'
  'deactivate:Deactivate an account'
  'reactivate:Reactivate an account'
  'delete:Permanently delete an account'
  'update-email:Update account email'
  'update-handle:Update account handle'
  'update-plc-endpoint:Update PLC service endpoint'
)

_kaszlak_invite_subcommands=(
  'list:List all invite codes'
  'create:Create a new invite code'
  'revoke:Revoke an invite code'
)

_kaszlak_admin_subcommands=(
  'list:List all administrators'
  'add:Grant admin privileges'
  'remove:Revoke admin privileges'
  'create:Create a new admin account'
)

_kaszlak_repo_subcommands=(
  'list:List all records in repository'
  'get:Fetch a specific record'
  'root:Return current repository root CID'
  'create-record:Create a new record'
  'delete-record:Delete a record'
  'repair:Force reinitialize corrupted repository'
)

_kaszlak() {
  local -a commands
  commands=($_kaszlak_commands)

  local -a serve_opts
  serve_opts=($_kaszlak_serve_opts)

  local -a account_subcommands
  account_subcommands=($_kaszlak_account_subcommands)

  local -a invite_subcommands
  invite_subcommands=($_kaszlak_invite_subcommands)

  local -a admin_subcommands
  admin_subcommands=($_kaszlak_admin_subcommands)

  local -a repo_subcommands
  repo_subcommands=($_kaszlak_repo_subcommands)

  case "$words[1]" in
    serve|s|start|run|server)
      _describe 'options' serve_opts
      ;;
    account|a)
      if [[ $CURRENT -eq 2 ]]; then
        _describe 'subcommands' account_subcommands
      else
        case "$words[2]" in
          list)
            _describe 'options' \
              '--limit:Limit results' \
              '--filter:Filter by handle, email, or DID'
            ;;
          create)
            _describe 'options' \
              '--email:Email address' \
              '--handle:Handle' \
              '--password:Password'
            ;;
        esac
      fi
      ;;
    invite|i)
      if [[ $CURRENT -eq 2 ]]; then
        _describe 'subcommands' invite_subcommands
      else
        case "$words[2]" in
          create)
            _describe 'options' \
              '--max-uses:Maximum uses'
          ;;
        esac
      fi
      ;;
    admin)
      if [[ $CURRENT -eq 2 ]]; then
        _describe 'subcommands' admin_subcommands
      else
        case "$words[2]" in
          create)
            _describe 'options' \
              '--email:Email address' \
              '--handle:Handle' \
              '--password:Password'
            ;;
        esac
      fi
      ;;
    repo|r)
      if [[ $CURRENT -eq 2 ]]; then
        _describe 'subcommands' repo_subcommands
      fi
      ;;
    help)
      _describe 'commands' commands
      ;;
    status|health|h)
      _describe 'options' \
        '--verbose:Verbose output' \
        '--json:JSON output'
      ;;
    *)
      _describe 'commands' commands
      ;;
  esac
}

_kaszlak "$@"
