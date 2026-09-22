{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  zlib,
  libcap,
  openssl,
  ncurses,
}:

let
  version = "0.156.0";
  repo = "openai/codex";

  platformMap = {
    "x86_64-linux" = "x86_64-unknown-linux-musl";
    "aarch64-linux" = "aarch64-unknown-linux-musl";
    "x86_64-darwin" = "x86_64-apple-darwin";
    "aarch64-darwin" = "aarch64-apple-darwin";
  };

  hashes = {
    "x86_64-unknown-linux-musl" = "0jd7vgsq8vpw7nfy9019kldylxby2qlqlb33pybb546v7aq49dz8";
    "aarch64-unknown-linux-musl" = "1nxqnr5v9bv4cs087x9n8salhk0n6768gagg6ci1kqvvn22sa1zz";
    "x86_64-apple-darwin" = "12adkzhk3cw7a1ajarwd6vg1fw915xgvrjcgkha79bqiwr5rpva1";
    "aarch64-apple-darwin" = "12wgyh23npgf57w5c9dn0zzbyvxdfza28vxd8shn9x4kav9dlyvg";
  };

  platform = platformMap.${stdenv.hostPlatform.system}
    or (throw "Unsupported system: ${stdenv.hostPlatform.system}");

  isLinux = stdenv.hostPlatform.isLinux;
in

stdenv.mkDerivation {
  pname = "codex";
  inherit version;

  src = fetchurl {
    url = "https://github.com/${repo}/releases/download/rust-v${version}/codex-package-${platform}.tar.gz";
    sha256 = hashes.${platform};
  };

  sourceRoot = ".";

  nativeBuildInputs = lib.optionals isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals isLinux [
    stdenv.cc.cc.lib
    zlib
    libcap
    openssl
    ncurses
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -R bin codex-package.json codex-path codex-resources $out/
    chmod -R u+w $out

    runHook postInstall
  '';

  dontFixup = !isLinux;

  meta = {
    description = "OpenAI Codex CLI — an AI coding agent for your terminal";
    homepage = "https://github.com/openai/codex";
    changelog = "https://github.com/${repo}/releases/tag/rust-v${version}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = builtins.attrNames platformMap;
    mainProgram = "codex";
  };
}
