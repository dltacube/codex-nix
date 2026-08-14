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
  version = "0.147.0";
  repo = "openai/codex";

  platformMap = {
    "x86_64-linux" = "x86_64-unknown-linux-musl";
    "aarch64-linux" = "aarch64-unknown-linux-musl";
    "x86_64-darwin" = "x86_64-apple-darwin";
    "aarch64-darwin" = "aarch64-apple-darwin";
  };

  hashes = {
    "x86_64-unknown-linux-musl" = "1nngcjnycn52ab5ss4d0jz8qw0wsyyfmix25w1jxqhbfsm9qsxdx";
    "aarch64-unknown-linux-musl" = "008lm2rfkws21l3kri69a29j310w66ghgs27v9c9qvxfsndzgjw9";
    "x86_64-apple-darwin" = "0qwxdqxmgkd0im41inii08mgd7mfz15dmqvnbp23p4mg7l9mj7nr";
    "aarch64-apple-darwin" = "0cjld2mb3ka5kxnrmlxsfvj11xchzi984wi51hypwq1bn979ichp";
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
