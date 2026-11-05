# Package the existing Cargo project. Templates and static assets are
# compiled into the binary (see src/web/assets.rs); the NixOS module supplies
# git, HH_BIND, and HH_DATA at runtime.
{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage {
  pname = "hugginghub";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../Cargo.toml
      ../Cargo.lock
      ../src
      ../static
      ../templates
    ];
  };

  cargoLock.lockFile = ../Cargo.lock;

  # Upstream tests are live end-to-end scripts (tests/e2e_*.sh, tests/e2e_hub.py),
  # not `cargo test`.
  doCheck = false;

  meta = {
    description = "Self-hosted Hugging Face Hub compatible server";
    longDescription = ''
      HuggingHub reimplements the Hugging Face Hub HTTP API so huggingface_hub,
      the hf CLI, and git can use a server you run. This package is the
      OnixResearch fork of empero-org/hugginghub.
    '';
    homepage = "https://github.com/OnixResearch/hugginghub";
    # PolyForm Noncommercial is not an OSI/FSF free license. Nix will refuse
    # to build this unless the host allows it (see the NixOS section of the README).
    license = {
      fullName = "PolyForm Noncommercial License 1.0.0";
      shortName = "PolyForm-Noncommercial-1.0.0";
      url = "https://polyformproject.org/licenses/noncommercial/1.0.0";
      free = false;
      redistributable = true;
    };
    mainProgram = "hugginghub";
    platforms = lib.platforms.linux;
  };
}
