{
  description = "go-template";

  nixConfig = {
    extra-substituters = [
      "https://trevnur.cachix.org"
    ];
    extra-trusted-public-keys = [
      "trevnur.cachix.org-1:hBd15IdszwT52aOxdKs5vNTbq36emvEeGqpb25Bkq6o="
    ];
  };

  inputs = {
    systems.url = "systems";
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };
    nur = {
      url = "github:spotdemo4/nur";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    semgrep-rules = {
      url = "github:semgrep/semgrep-rules";
      flake = false;
    };
  };

  outputs = {
    nixpkgs,
    utils,
    nur,
    semgrep-rules,
    ...
  }:
    utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [nur.overlays.default];
      };
    in {
      devShells = {
        default = pkgs.mkShell {
          packages = with pkgs; [
            # go
            go
            gotools
            gopls

            # lint
            golangci-lint
            alejandra
            prettier

            # util
            air
            trev.bumper
          ];
          shellHook = pkgs.trev.shellhook.ref;
        };

        release = pkgs.mkShell {
          packages = with pkgs; [
            skopeo
          ];
        };

        update = pkgs.mkShell {
          packages = with pkgs; [
            trev.renovate
          ];
        };

        vulnerable = pkgs.mkShell {
          packages = with pkgs; [
            govulncheck
            flake-checker
          ];
        };
      };

      checks = pkgs.trev.lib.mkChecks {
        go = {
          src = ./.;
          deps = with pkgs; [
            go
            golangci-lint
            trev.opengrep
          ];
          script = ''
            go test ./...
            golangci-lint run ./...
            opengrep scan --quiet --error --config="${semgrep-rules}/go"
          '';
        };

        nix = {
          src = ./.;
          deps = with pkgs; [
            alejandra
          ];
          script = ''
            alejandra -c .
          '';
        };

        actions = {
          src = ./.;
          deps = with pkgs; [
            prettier
            action-validator
            trev.renovate
          ];
          script = ''
            prettier --check .
            action-validator .github/**/*.yaml
            renovate-config-validator .github/renovate.json
          '';
        };
      };

      packages = with pkgs.trev.lib; rec {
        default = pkgs.buildGoModule (finalAttrs: {
          pname = "go-template";
          version = "0.0.1";
          src = ./.;
          goSum = ./go.sum;
          vendorHash = null;
          env.CGO_ENABLED = 0;

          meta = {
            description = "a go template project";
            mainProgram = "go-template";
            homepage = "https://github.com/spotdemo4/go-template";
            changelog = "https://github.com/spotdemo4/go-template/releases/tag/v${finalAttrs.version}";
            license = pkgs.lib.licenses.mit;
            platforms = pkgs.lib.platforms.all;
          };
        });

        linux-amd64 = go.moduleToPlatform default "linux" "amd64";
        linux-arm64 = go.moduleToPlatform default "linux" "arm64";
        linux-arm = go.moduleToPlatform default "linux" "arm";
        darwin-arm64 = go.moduleToPlatform default "darwin" "arm64";
        windows-amd64 = go.moduleToPlatform default "windows" "amd64";

        image = pkgs.dockerTools.streamLayeredImage {
          name = "${default.pname}";
          tag = "${default.version}";
          created = "now";
          contents = with pkgs; [
            default
            dockerTools.caCertificates # needed for https
          ];
          config = {
            Cmd = [
              "${pkgs.lib.meta.getExe default}"
            ];
          };
        };
      };

      formatter = pkgs.alejandra;
    });
}
