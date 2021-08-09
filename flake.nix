{
  description = "(insert short project description here)";

  # Nixpkgs / NixOS version to use.
  inputs.nixpkgs.url = "nixpkgs/nixpkgs-unstable";

  # Upstream source tree(s).
  inputs.sonar-src = { url = "github:arso-project/sonar"; flake = false; };

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

      pname = "sonar";

      node_modules = (pkgs:
        pkgs.mkYarnModules {
          pname = "${pname}-node_modules";
          inherit version;
          packageJSON = ./package.json;
          yarnNix = ./yarn.nix;
          yarnLock = ./yarn.lock;
          workspaceDependencies = [{
            pname = "${pname}-ui";
            packageJSON = "${sonar-src}/packages/ui/package.json";
          }];
        });
    in

    {

      # A Nixpkgs overlay.
      overlay = final: prev:
        with final;
        let
          deps = node_modules final;
        in
        {
          sonar = stdenv.mkDerivation {
            inherit version pname;
            src = sonar-src;
            buildInputs = [ nodejs ];

            configurePhase = ''
              ln -s ${deps}/node_modules node_modules
              ln -s ${deps}/node_modules packages/ui/node_modules
              cd node_modules
              ls -lah
              cd ..
            '';

            buildPhase = ''
              npm run build:ui 
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
            deps = node_modules pkgs;
          in
          with pkgs; mkShell {
            buildInputs = [ nodejs yarn ];
            shellHook = ''
              export PATH="${deps}/bin:$PATH"
              ln -s ${deps} node_modules
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
