{
  description = "impure pyproject-nix dev shell and pure uv2nix deployment build";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, pyproject-nix, uv2nix, pyproject-build-systems, ... }:
    let
      inherit (nixpkgs) lib; #import nixpkgs stl
      forAllSystems = lib.genAttrs lib.systems.flakeExposed; #all platforms

      workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };
      overlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };
      pythonSets = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          python = pkgs.python3;
        in
        (pkgs.callPackage pyproject-nix.build.packages {
          inherit python;
        }).overrideScope
          (
            lib.composeManyExtensions [
              pyproject-build-systems.overlays.wheel
              overlay
            ]
          )
      );

    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          #impure
          default = pkgs.mkShell {
            packages = [
              pkgs.python3
              pkgs.uv
            ];
            shellHook = ''
              unset PYTHONPATH
              uv sync
              . .venv/bin/activate
            '';
          };

        }
      );

      # uv2nix build
      packages = forAllSystems (system: {
        default = pythonSets.${system}.mkVirtualEnv "env" workspace.deps.default;
      });

      # docker build
      containers = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          env = pythonSets.${system}.mkVirtualEnv "env" workspace.deps.default;
        in
        {
          docker = pkgs.dockerTools.buildLayeredImage {
            name = "registry.microdot/random_number_generator";
            tag = "latest";
            contents = [env
                        ./.
                       ];
            config = {
              Cmd = [ "${env}/bin/python" "./main.py" ];
            };
          };
        }
      );
    };
}

