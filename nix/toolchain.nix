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
# NSPathUtilities about Nix store paths) is rebased against master as
# patches/fixup-paths-master.patch.
#
# nixpkgs' swift-corelibs-libdispatch requires a full Swift/LLVM toolchain;
# libdispatch is built from the standalone C dispatcher instead.
{ pkgs }:

let
  libsBaseRev = "6930c840b6a0d95554f2f76f41f001e47b941d37";
  libsBaseHash = "sha256-DPQDwkZwf6w7TAWbacjEgJGW1lyuC93kFSaoJarj4x8=";

  gnustepBase = pkgs.gnustep-base.overrideAttrs (old: {
    version = "master-${libsBaseRev}";
    src = pkgs.fetchzip {
      url = "https://github.com/gnustep/libs-base/archive/${libsBaseRev}.tar.gz";
      sha256 = libsBaseHash;
    };
    patches = [ ./patches/fixup-paths-master.patch ];
    # Without libcurl the build reports GS_HAVE_NSURLSESSION=0 and
    # DID.m (record DID document fetches) cannot compile.
    buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.curl ];
    configureFlags = (old.configureFlags or [ ]) ++ [ "--with-libcurl" ];
  });

  libdispatch = pkgs.clangStdenv.mkDerivation {
    pname = "libdispatch";
    version = "swift-5.9.2-RELEASE";
    src = pkgs.fetchzip {
      url = "https://github.com/apple/swift-corelibs-libdispatch/archive/refs/tags/swift-5.9.2-RELEASE.tar.gz";
      sha256 = "sha256-pta3wJj2LJ/lsYAWQpw0wSGLDMO41mN8Zbl78LUCaQo=";
    };
    nativeBuildInputs = [ pkgs.cmake pkgs.ninja ];
    buildInputs = [ pkgs.libblocksruntime ];
    cmakeFlags = [
      "-DINSTALL_PRIVATE_HEADERS=YES"
      "-DBUILD_TESTING=OFF"
    ];
    NIX_CFLAGS_COMPILE = "-Wno-error";
  };

  # A single prefix that mirrors a GNUstep install: headers under include/ and
  # Library/Headers, libraries under lib/. CMakeLists reads GNUSTEP_PREFIX.
  gnustepPrefix = pkgs.symlinkJoin {
    name = "gnustep-prefix";
    paths = [
      gnustepBase
      pkgs.gnustep-make
      pkgs.gnustep-libobjc
      libdispatch
    ];
  };

  # Libraries the built binaries link directly. Their store paths land in the
  # binaries' RUNPATH, so they must be present in the derivation closure and
  # referenced so Nix keeps them alive.
  runtimeLibs = [
    gnustepBase
    pkgs.gnustep-libobjc
    libdispatch
    pkgs.libblocksruntime
    pkgs.curl
    pkgs.openssl
    pkgs.sqlite
    pkgs.qrencode
    pkgs.icu
    pkgs.gmp
    pkgs.libgcrypt
    pkgs.gnutls
    pkgs.aspell
    pkgs.libxml2
    pkgs.libxslt
    pkgs.libffi
    pkgs.zlib
    pkgs.readline
    pkgs.ncurses
    pkgs.libpng
    pkgs.libjpeg
    pkgs.libtiff
    pkgs.giflib
    pkgs.portaudio
    pkgs.audiofile
    pkgs.cups
    pkgs.libiconv
    pkgs.libiberty
    pkgs.binutils-unwrapped
  ];
in
{
  inherit gnustepBase libdispatch gnustepPrefix runtimeLibs;
}
