{
  description = "It's a RANCID^WOxidized replacement!";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";

    advisory-db = {
      url = "github:rustsec/advisory-db";
      flake = false;
    };

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    crane = {
      url = "github:ipetkov/crane";
    };
  };

  outputs =
    {
      self,
      advisory-db,
      crane,
      nixpkgs,
      utils,
      ...
    }:
    utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        craneLib = crane.mkLib pkgs;

        src = craneLib.cleanCargoSource ./.;

        cargoArtifacts = craneLib.buildDepsOnly {
          inherit src;
          pname = "rusted-deps";
        };

        rusted = craneLib.buildPackage {
          inherit src cargoArtifacts;
        };
      in
      rec {
        checks = {
          inherit rusted;

          rusted-clippy = craneLib.cargoClippy {
            inherit src cargoArtifacts;
            cargoClippyExtraArgs = "--all-targets -- --deny warnings";
          };

          rusted-doc = craneLib.cargoDoc { inherit src cargoArtifacts; };
          rusted-fmt = craneLib.cargoFmt { inherit src cargoArtifacts; };
          rusted-audit = craneLib.cargoAudit { inherit src cargoArtifacts advisory-db; };
        };

        packages.default = pkgs.stdenv.mkDerivation {
          name = "rusted";

          dontUnpack = true;
          dontConfigure = true;
          dontBuild = true;
          nativeBuildInputs = [ pkgs.makeWrapper ];

          installPhase = ''
            mkdir -vp $out/{bin,etc/systemd/system}
            ln -sf ${rusted}/bin/rusted $out/bin/rusted
            wrapProgram "$out/bin/rusted" \
              --prefix PATH ":" "${pkgs.lib.makeBinPath [ pkgs.expect ]}"
            cp -v ${./etc}/rusted.{service,timer} $out/etc/systemd/system
            cp -vr ${./expect_scripts} $out/expect_scripts
          '';
        };

        apps.default = utils.lib.mkApp { drv = packages.default; };

        devShells.default = pkgs.mkShell {
          inputsFrom = builtins.attrValues self.checks;

          nativeBuildInputs = with pkgs; [
            cargo
            clippy
            pre-commit
            rustc
            rustfmt
            expect
            rust-analyzer
          ];
          RUST_SRC_PATH = pkgs.rustPlatform.rustLibSrc;
        };
      }
    );
}
