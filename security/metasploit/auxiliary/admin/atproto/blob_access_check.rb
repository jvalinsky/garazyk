##
# This module requires Metasploit: https://metasploit.com/download
##

class MetasploitModule < Msf::Auxiliary
  include Msf::Exploit::Remote::HttpClient

  def initialize(info = {})
    super(update_info(info,
      'Name'           => 'AT Protocol Blob Access Control Check',
      'Description'    => %q{
        This module verifies if the AT Protocol PDS properly enforces access
        controls on blobs via the com.atproto.sync.getBlob XRPC endpoint.
        It tests for unauthorized retrieval of blobs by trying to access
        a blob without authentication or with a different user's JWT.
      },
      'Author'         => ['OpenCode'],
      'License'        => MSF_LICENSE
    ))

    register_options([
      Opt::RPORT(2583),
      OptString.new('TARGET_DID', [true, 'The DID of the repository owner', 'did:plc:admin']),
      OptString.new('CID', [true, 'The CID of the blob to retrieve', 'bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi']),
      OptString.new('JWT', [false, 'JWT token (optional, to test cross-user access)', nil])
    ])
  end

  def run
    target_did = datastore['TARGET_DID']
    cid = datastore['CID']
    jwt = datastore['JWT']

    print_status("Checking blob access for CID #{cid} in repo #{target_did} on #{peer}...")

    # 1. Test getBlob without auth
    test_get_blob(target_did, cid, nil, "Unauthenticated")

    # 2. Test getBlob with provided JWT
    if jwt
      test_get_blob(target_did, cid, jwt, "Authenticated (JWT provided)")
    end
  end

  def test_get_blob(did, cid, token, context)
    print_status("Testing com.atproto.sync.getBlob (#{context})...")
    
    headers = {}
    headers['Authorization'] = "Bearer #{token}" if token

    res = send_request_cgi({
      'method' => 'GET',
      'uri'    => normalize_uri(target_uri.path, 'xrpc', 'com.atproto.sync.getBlob'),
      'vars_get' => { 'did' => did, 'cid' => cid },
      'headers' => headers
    })

    if res && res.code == 200
      print_good("VULNERABLE: Successfully retrieved blob for #{did}/#{cid} (#{context})")
      print_status("Blob Content-Type: #{res.headers['Content-Type']}")
      print_status("Blob size: #{res.body.length} bytes")
    elsif res && res.code == 401
      print_status("Secure: Server rejected getBlob (401 Unauthorized) as expected for #{context}")
    elsif res && res.code == 403
      print_status("Secure: Server rejected getBlob (403 Forbidden) for #{context}")
    elsif res && res.code == 404
      print_status("Notice: Server returned 404 Not Found for #{context}. Verify DID and CID.")
    elsif res
      print_status("Server returned #{res.code} for getBlob (#{context})")
    else
      print_error("No response from server for getBlob (#{context})")
    end
  end
end
