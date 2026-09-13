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

      editableOverlay = workspace.mkEditablePyprojectOverlay {
        root = "$REPO_ROOT";
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
          #pythonSet = pythonSets.${system}.overrideScope editableOverlay;
          #virtualenv = pythonSet.mkVirtualEnv "dev-env" workspace.deps.all;
        in
        {
          #impure
          default = pkgs.mkShell {
            packages = [
              pkgs.python3
              pkgs.uv
              pkgs.stdenv.cc.cc
            ];

            shellHook = ''
              unset PYTHONPATH
    	        export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath [
      	        pkgs.stdenv.cc.cc
                pkgs.zlib
                pkgs.libuv
    	        ]}:$LD_LIBRARY_PATH
              uv sync
              if [ ! -d .venv ]; then
                uv venv
              fi
              . .venv/bin/activate
            '';
          };

          ##pure
          #default = pkgs.mkShell {
          #  packages = [
          #    virtualenv
          #    pkgs.uv
          #  ];
          #  env = {
          #    UV_NO_SYNC = "1";
          #    UV_PYTHON = pythonSet.python.interpreter;
          #    UV_PYTHON_DOWNLOADS = "never";
          #  };
          #  shellHook = ''
          #    unset PYTHONPATH
          #    export REPO_ROOT=$(git rev-parse --show-toplevel)
          #  '';
          #};

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
          pythonEnv = pythonSets.${system}.mkVirtualEnv "env" workspace.deps.default;
        in
        {
          docker = pkgs.dockerTools.buildLayeredImage {
            name = "registry.project_name/image_name";
            tag = "latest";

            contents = [pythonEnv];

            config = {
              Cmd = [ "${pythonEnv}/bin/python" "/main.py" ];
            };
          };
        }
      );
    };
}
