##
# This module requires Metasploit: https://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

class MetasploitModule < Msf::Auxiliary
  include Msf::Exploit::Remote::HttpClient

  def initialize(info = {})
    super(update_info(info,
      'Name'           => 'AT Protocol PDS Discovery',
      'Description'    => %q{
        This module identifies an AT Protocol Personal Data Server (PDS) by querying
        the public XRPC endpoints. It attempts to retrieve the server description,
        version information, and supported schemas.
      },
      'Author'         => ['OpenCode'],
      'License'        => MSF_LICENSE,
      'References'     => [
        ['URL', 'https://atproto.com/specs/xrpc']
      ]
    ))

    register_options([
      Opt::RPORT(8080),
      OptString.new('TARGETURI', [true, 'The base path to the PDS', '/'])
    ])
  end

  def run
    print_status("Probing ATProto PDS at #{peer}...")

    # Check describeServer
    res = send_request_cgi({
      'method' => 'GET',
      'uri'    => normalize_uri(target_uri.path, 'xrpc', 'com.atproto.server.describeServer')
    })

    if res && res.code == 200
      print_good("Found ATProto PDS via describeServer")
      
      begin
        json = JSON.parse(res.body)
        print_status("Server DID: #{json['did']}") if json['did']
        print_status("Available User Domains: #{json['availableUserDomains'].join(', ')}") if json['availableUserDomains']
      rescue JSON::ParserError
        print_error("Failed to parse describeServer response")
      end
    elsif res
      print_error("Server responded with code #{res.code} to describeServer probe")
    else
      print_error("No response from server")
    end

    # Check health endpoint
    res = send_request_cgi({
      'method' => 'GET',
      'uri'    => normalize_uri(target_uri.path, 'health')
    })

    if res && res.code == 200
      print_good("Health endpoint exposed: #{res.body.strip}")
    end
  end
end
