# Linux-only GNUstep toolchain for building the Garazyk binaries (zuk, pds).
#
# nixpkgs' gnustep-base 1.29.0 cannot build this codebase: it lacks
# NSJSONWritingSortedKeys, which the PDS uses for RFC 7638 JWK thumbprints.
# The method landed on libs-base master and is still absent from 1.31.1, so
# this toolchain pins libs-base to the commit below.
#
# nixpkgs applies three extra patches to the release tarball that are not
# needed against master: bd5f2909 is a stale revert and 37913d00 / b4feee31
# are already present upstream. The remaining fixup-paths.patch (which teaches
# NSPathUtilities about Nix store paths) is regenerated against master as
# patches/fixup-paths-master.patch.
#
# nixpkgs' swift-corelibs-libdispatch drags in a full Swift 5.10 toolchain
# (hence an LLVM build) purely for its Swift bindings -- hours of compute that
# will not fit in this machine's 7.7 GB. Garazyk only needs the C API
# (CMakeLists.txt links plain `dispatch`), so libdispatch is built standalone
# with clang and no Swift, exactly as docker/Dockerfile.gnustep does.
#
# This file is the flake-side home of what docker/Dockerfile.gnustep does
# manually; keep the two in sync when either moves.
{ pkgs }:

let
  libsBaseRev = "6930c840b6a0d95554f2f76f41f001e47b941d37";
  libsBaseHash = "sha256-DPQDwkZwf6w7TAWbacjEgJGW1lyuC93kFSaoJarj4x8=";

  gnustepBase = pkgs.gnustep-base.overrideAttrs (old: {
    version = "1.31.1-unstable-${libsBaseRev}";
    src = pkgs.fetchzip {
      url = "https://github.com/gnustep/libs-base/archive/${libsBaseRev}.tar.gz";
      sha256 = libsBaseHash;
    };
    # Deliberately NOT autoreconfHook, even though this is a git checkout:
    # libs-base commits its generated ./configure (534 KB), and its
    # configure.ac sets AC_CONFIG_AUX_DIR to a shell expression that queries
    # gnustep-config, which autoreconf cannot evaluate. Using the committed
    # configure is also what Dockerfile.gnustep does.
    #
    # nixpkgs' fixup-paths.patch is a gnustep-base 1.24.7-era patch that
    # teaches GNUstep to resolve its directories inside the Nix store. It no
    # longer applies to master: 23 of its 25 hunks land, two do not.
    #
    #   * The hunk declaring the `static NSArray *gnustep*Nix` globals lost
    #     its context when master added gnustepSystemServices to that block.
    #     All 11 declarations are re-added verbatim -- without them the other
    #     23 hunks reference undeclared identifiers.
    #   * The hunk adding a Nix CoreServices path is obsolete: master rewrote
    #     NSCoreServicesDirectory to use ADD_PLATFORM_PATH against a dedicated
    #     gnustepSystemServices, so the ADD_PATH call it meant to shadow no
    #     longer exists. Dropped rather than reinvented -- it only affected
    #     CoreServices lookup, which a headless server never performs.
    #
    # Regenerated as one patch against the pinned rev.
    #
    # The other three nixpkgs patches are dropped entirely (see header).
    patches = [ ./patches/fixup-paths-master.patch ];

    # Without libcurl the build reports GS_HAVE_NSURLSESSION=0 and DID.m
    # (record DID document fetches) cannot compile. nixpkgs' package never
    # depended on curl (TLS via gnutls alone). docker/Dockerfile.gnustep passes
    # --with-libcurl; replicate that.
    buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.curl ];
    configureFlags = (old.configureFlags or [ ]) ++ [ "--with-libcurl" ];
  });

  # libdispatch with the C API only. Swift toolchain avoided (see header).
  libdispatch = pkgs.clangStdenv.mkDerivation {
    pname = "libdispatch";
    version = "swift-5.9.2-RELEASE";

    src = pkgs.fetchFromGitHub {
      owner = "swiftlang";
      repo = "swift-corelibs-libdispatch";
      rev = "swift-5.9.2-RELEASE";
      hash = "sha256-pta3wJj2LJ/lsYAWQpw0wSGLDMO41mN8Zbl78LUCaQo=";
    };

    nativeBuildInputs = with pkgs; [ cmake ninja pkg-config ];
    buildInputs = with pkgs; [ libbsd ];

    cmakeFlags = [
      "-DCMAKE_BUILD_TYPE=Release"
      "-DINSTALL_PRIVATE_HEADERS=YES"
      "-DBUILD_TESTING=OFF"
    ];

    env.NIX_CFLAGS_COMPILE = "-Wno-error";
  };

  # A single prefix that mirrors a GNUstep install: headers under include/ and
  # Library/Headers, libraries under lib/. CMakeLists reads GNUSTEP_PREFIX.
  # nixpkgs splits gnustep-base into out/dev/lib and ships libobjc separately,
  # so join them into one tree. This is what Dockerfile.gnustep's
  # /usr/GNUstep layout represents.
  gnustepPrefix = pkgs.symlinkJoin {
    name = "gnustep-prefix";
    paths = [
      gnustepBase.dev
      gnustepBase.lib
      gnustepBase
      pkgs.gnustep-libobjc
      libdispatch
    ];
  };

  # Libraries the built binaries link directly. Their store paths land in the
  # binaries' RUNPATH, so they must be present in the derivation closure and
  # referenced so Nix keeps them alive.
  runtimeLibs = [
    gnustepBase.lib
    pkgs.gnustep-libobjc
    libdispatch
    pkgs.openssl.out
    pkgs.sqlite.out
    pkgs.curl.out
    pkgs.qrencode.out
    pkgs.libxml2.out
    pkgs.libffi
    pkgs.icu
    pkgs.zlib
    pkgs.readline
    pkgs.libbsd
    pkgs.gnutls
  ];
in
{
  inherit gnustepBase libdispatch gnustepPrefix runtimeLibs;
}
