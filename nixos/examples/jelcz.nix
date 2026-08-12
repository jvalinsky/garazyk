# Dummy example: a Garazyk Jelcz video processing service deployed alongside
# a local PDS. All values are placeholders — replace them for a real deployment.
#
# From a NixOS flake, wire it up like:
#
#   specialArgs = { jelczPackage = self.packages.x86_64-linux.jelcz; };
#   modules = [ ./jelcz.nix ];
{ config, lib, pkgs, jelczPackage, ... }:

{
  imports = [
    ../modules/jelcz.nix
  ];

  services.jelcz = {
    enable = true;
    package = jelczPackage;
    port = 2586;
    dataDir = "/var/lib/jelcz";
    pdsURL = "http://127.0.0.1:2583";
    # Supply this from sops-nix, agenix, or another runtime secret manager.
    adminPasswordFile = "/run/secrets/jelcz_admin_password";

    # --- Storage backend ---
    # Uncomment for S3-backed blob storage:
    # s3Bucket = "jelcz-blobs";
    # s3Region = "us-east-1";
    # s3Endpoint = "https://s3.example.com";

    # --- HLS output ---
    # Uncomment for HLS streaming output:
    # hlsDir = "/var/lib/jelcz/hls";
    # hlsBaseURL = "https://video.example.com";
    # hls1080p = true;
  };
}
