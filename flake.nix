{
  description = "(insert short project description here)";

  # Nixpkgs / NixOS version to use.
  inputs.nixpkgs.url = "nixpkgs/nixpkgs-unstable";

  # Upstream source tree(s).
  inputs.sonar-src = { url = "github:arso-project/sonar/8a48325389a3dbd39af741d1c3a017a12806aaa8"; flake = false; };

  outputs = { self, nixpkgs, sonar-src }:
    let

      # Generate a user-friendly version numer.
      version = builtins.substring 0 8 sonar-src.lastModifiedDate;

      # System types to support.
      supportedSystems = [ "x86_64-linux" "x86_64-darwin" ];

      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f system);

      # Nixpkgs instantiated for supported system types.
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; overlays = [ self.overlay ]; });

      # pname = "sonar";

      # node_modules = (pkgs:
      #   pkgs.mkYarnModules {
      #     pname = "${pname}-node_modules";
      #     inherit version;
      #     packageJSON = ./package.json;
      #     yarnNix = ./yarn.nix;
      #     yarnLock = ./yarn.lock;
      #     workspaceDependencies = [{
      #       pname = "${pname}-ui";
      #       packageJSON = "${sonar-src}/packages/ui/package.json";
      #     }];
      #   });
    in

    {

      # A Nixpkgs overlay.
      overlay = final: prev:
        with final;
        let
          # installation on package.json with no version fails silently
          # jsdoc is used as a global dependency
          # express and open are used in ui and are missing in package.json
          patchedPackageJSON = final.runCommand "package.json" { } ''
            ${jq}/bin/jq '.version = "0.4.0" |
              .devDependencies."@jsdoc/cli" = "^0.2.5" |
              .devDependencies.express = "^4.17.1" |
              .devDependencies.open = "^8.2.1" |
              .devDependencies.yargs = "^17.1.1"' ${sonar-src}/package.json > $out
          '';
        in
        {
          sonar = mkYarnPackage {
            pname = "sonar";
            inherit version;
            src = sonar-src;
            yarnNix = ./yarn.nix;
            yarnLock = ./yarn.lock;
            packageJSON = patchedPackageJSON;

            # needs to be overridden because sonar depends on sonar
            # original configure phase will try to make a conflicting symlink
            configurePhase = ''
              ln -s $node_modules node_modules;
            '';

            buildPhase = ''
              # Yarn writes cache directories etc to $HOME.
              export HOME=$PWD/yarn_home
              yarn build:ui
            '';

            meta = {
              homepage = "https://arso.xyz/sonar";
              description = "A p2p content database and search engine";
            };
          };
        };

      # Provide some binary packages for selected system types.
      packages = forAllSystems (system:
        {
          inherit (nixpkgsFor.${system}) sonar;
        });

      # The default package for 'nix build'. This makes sense if the
      # flake provides only one package or there is a clear " main "
      # package.
      defaultPackage = forAllSystems (system: self.packages.${system}.sonar);

      # # A NixOS module, if applicable (e.g. if the package provides a system service).
      # nixosModules.hello =
      #   { pkgs, ... }:
      #   {
      #     nixpkgs.overlays = [ self.overlay ];

      #     environment.systemPackages = [ pkgs.hello ];

      #     #systemd.services = { ... };
      #   };
      devShell = forAllSystems
        (system:
          let
            pkgs = nixpkgsFor.${system};
          in
          with pkgs; mkShell {
            buildInputs = [ nodejs yarn ];
            shellHook = ''
            '';
          }
        );

      # Tests run by 'nix flake check' and by Hydra.
      # checks = forAllSystems (system: {
      #   inherit (self.packages.${system}) hello;

      #   # Additional tests, if applicable.
      #   test =
      #     with nixpkgsFor.${system};
      #     stdenv.mkDerivation {
      #       name = "hello-test-${version}";

      #       buildInputs = [ hello ];

      #       unpackPhase = "true";

      #       buildPhase = ''
      #         echo 'running some integration tests'
      #         [[ $(hello) = 'Hello, world!' ]]
      #       '';

      #       installPhase = "mkdir -p $out";
      #     };

      # A VM test of the NixOS module.
      # vmTest =
      #   with import (nixpkgs + "/nixos/lib/testing-python.nix")
      #     {
      #       inherit system;
      #     };

      #   makeTest {
      #     nodes = {
      #       client = { ... }: {
      #         imports = [ self.nixosModules.hello ];
      #       };
      #     };

      #     testScript =
      #       ''
      #         start_all()
      #         client.wait_for_unit("multi-user.target")
      #         client.succeed("hello")
      #       '';
      #   };
      # });

    };
}
