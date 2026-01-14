##
# This module requires Metasploit: https://metasploit.com/download
##

class MetasploitModule < Msf::Auxiliary
  include Msf::Exploit::Remote::HttpClient

  def initialize(info = {})
    super(update_info(info,
      'Name'           => 'AT Protocol Repository Sync Probe',
      'Description'    => %q{
        This module checks if the AT Protocol PDS allows unauthorized repository
        synchronization via com.atproto.sync XRPC endpoints. It probes
        com.atproto.sync.getRepo to see if repository data (CAR files) can be
        retrieved without proper authorization or by unauthorized users.
      },
      'Author'         => ['OpenCode'],
      'License'        => MSF_LICENSE
    ))

    register_options([
      Opt::RPORT(2583),
      OptString.new('TARGET_DID', [true, 'The DID of the repository to sync', 'did:plc:admin']),
      OptString.new('JWT', [false, 'JWT token (optional, to test cross-user sync)', nil])
    ])
  end

  def run
    target_did = datastore['TARGET_DID']
    jwt = datastore['JWT']

    print_status("Probing repo sync for #{target_did} on #{peer}...")

    # 1. Test getRepo without auth
    test_get_repo(target_did, nil, "Unauthenticated")

    # 2. Test getRepo with provided JWT (could be a valid but unauthorized user's token)
    if jwt
      test_get_repo(target_did, jwt, "Authenticated (JWT provided)")
    end
  end

  def test_get_repo(did, token, context)
    print_status("Testing com.atproto.sync.getRepo (#{context})...")
    
    headers = {}
    headers['Authorization'] = "Bearer #{token}" if token

    res = send_request_cgi({
      'method' => 'GET',
      'uri'    => normalize_uri(target_uri.path, 'xrpc', 'com.atproto.sync.getRepo'),
      'vars_get' => { 'did' => did },
      'headers' => headers
    })

    if res && res.code == 200
      print_good("CAUTION: Successfully retrieved repo CAR file for #{did} (#{context})")
      print_status("Response size: #{res.body.length} bytes")
    elsif res && res.code == 401
      print_status("Secure: Server rejected getRepo (401 Unauthorized) as expected for #{context}")
    elsif res && res.code == 403
      print_status("Secure: Server rejected getRepo (403 Forbidden) for #{context}")
    elsif res
      print_status("Server returned #{res.code} for getRepo (#{context})")
    else
      print_error("No response from server for getRepo (#{context})")
    end
  end
end
