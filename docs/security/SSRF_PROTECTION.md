# SSRF Protection for Handle Resolution

Server-Side Request Forgery (SSRF) allows attackers to induce the server to make HTTP requests to unintended locations. In handle resolution, an attacker could:
1. **Access internal services**: Query internal APIs, databases, or cloud metadata endpoints (e.g., `169.254.169.254`)
2. **Bypass network segmentation**: Reach services not exposed to the internet
3. **Exfiltrate data**: Use the server as a proxy to access internal resources

## Handle Resolution Attack Vector

ATProto handles resolve to DIDs through HTTP requests to `.well-known/atproto-did` endpoints. Without SSRF protection:

```
Handle: attacker-controlled.domain.internal
↓
Resolver makes HTTPS request to: https://attacker-controlled.domain.internal/.well-known/atproto-did
↓
Attacker could return internal IP addresses pointing to sensitive services
```

## Protected IP Ranges

The HandleResolver validates that resolved IP addresses are public by blocking the following ranges:

### IPv4 Private Addresses (RFC 1918)

| CIDR Range | Description | Blocked |
|------------|-------------|---------|
| `10.0.0.0/8` | Class A private network | Yes |
| `172.16.0.0/12` | Class B private network | Yes |
| `192.168.0.0/16` | Class C private network | Yes |

### IPv4 Loopback (RFC 5735)

| Address | Description | Blocked |
|---------|-------------|---------|
| `127.0.0.0/8` | Loopback addresses | Yes |

### IPv4 Link-Local (RFC 3927)

| CIDR Range | Description | Blocked |
|------------|-------------|---------|
| `169.254.0.0/16` | Link-local addresses (APIPA) | Yes |

### IPv4 Multicast (RFC 5771)

| CIDR Range | Description | Blocked |
|------------|-------------|---------|
| `224.0.0.0/4` | Multicast addresses | Yes |

### Documentation Addresses (RFC 5737)

| CIDR Range | Description | Blocked |
|------------|-------------|---------|
| `192.0.2.0/24` | TEST-NET-1 | Yes |
| `198.51.100.0/24` | TEST-NET-2 | Yes |
| `203.0.113.0/24` | TEST-NET-3 | Yes |

### IPv6 Private Addresses (RFC 4291)

| CIDR Range | Description | Blocked |
|------------|-------------|---------|
| `fc00::/7` | Unique local addresses (ULA) | Yes |
| `::1/128` | Loopback | Yes |
| `fe80::/10` | Link-local unicast | Yes |

## Implementation

The SSRF protection is implemented in `ATProtoPDS/Sources/Identity/HandleResolver.m`:

```objective-c
- (BOOL)validateHandleResolvesToPublicIP:(NSString *)handle error:(NSError **)error {
    // Resolve hostname using CFHost
    // Validate each resolved IP address against private/reserved ranges
}
```

The `skipSSRFCheck` property allows disabling SSRF checks for testing purposes only.

## Test Coverage

Tests are located in `ATProtoPDS/Tests/Identity/HandleResolverSSRFTests.m` with coverage for:

### Private IPv4 Detection
- Class A (`10.x.x.x`)
- Class B (`172.16.x.x`)
- Class C (`192.168.x.x`)
- Loopback (`127.x.x.x`)
- Link-local (`169.254.x.x`)
- Multicast (`224.x.x.x`)

### Documentation Ranges
- TEST-NET-1 (`192.0.2.x`)
- TEST-NET-2 (`198.51.100.x`)
- TEST-NET-3 (`203.0.113.x`)

### Public IP Verification
- Google DNS (`8.8.8.8`)
- Cloudflare (`1.1.1.1`)
- OpenDNS (`208.67.222.222`)

## References

### RFCs
- [RFC 1918](https://tools.ietf.org/html/rfc1918) - Address Allocation for Private Internets
- [RFC 3927](https://tools.ietf.org/html/rfc3927) - Dynamic Configuration of IPv4 Link-Local Addresses
- [RFC 4291](https://tools.ietf.org/html/rfc4291) - IP Version 6 Addressing Architecture
- [RFC 5735](https://tools.ietf.org/html/rfc5735) - Special Use IPv4 Addresses
- [RFC 5737](https://tools.ietf.org/html/rfc5737) - IPv4 Address Blocks Reserved for Documentation

### Security Resources
- [OWASP SSRF](https://owasp.org/www-community/attacks/Server_Side_Request_Forgery)
- [CWE-918: Server-Side Request Forgery (SSRF)](https://cwe.mitre.org/data/definitions/918.html)
- [PortSwigger SSRF](https://portswigger.net/web-security/ssrf)

### Cloud Metadata Protection
- [AWS Instance Metadata Service](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html)
- [GCP Metadata Server](https://cloud.google.com/compute/docs/metadata)

## Future Work

1. **IPv6 Support**: Complete IPv6 private address detection tests
2. **DNS Rebinding**: Add protection against DNS rebinding attacks
3. **Rate Limiting**: Per-handle rate limits for resolution
4. **Timeout Configuration**: Timeouts to prevent slow-loris attacks
