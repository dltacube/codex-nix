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
  version = "0.146.1";
  repo = "openai/codex";

  platformMap = {
    "x86_64-linux" = "x86_64-unknown-linux-musl";
    "aarch64-linux" = "aarch64-unknown-linux-musl";
    "x86_64-darwin" = "x86_64-apple-darwin";
    "aarch64-darwin" = "aarch64-apple-darwin";
  };

  hashes = {
    "x86_64-unknown-linux-musl" = "1jrlzjlmnx10g6yjza0k58x9w15njsmzi0b54r1jgq3yljmbdn8m";
    "aarch64-unknown-linux-musl" = "0pwf5d5lnq0x989jg5vnisra9ksfqf5l2jjqymvwx7nngp9jnax7";
    "x86_64-apple-darwin" = "01ify4ngajqlial3rx8ibq6yzy51zkc0mlbaxbhlfix1p93y8qav";
    "aarch64-apple-darwin" = "1imflpvd4c46ddk9bhkgcda87brdhhgxwh4v3zl053gkf9ckigm0";
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
