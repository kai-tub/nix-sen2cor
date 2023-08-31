{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # nix-filter.url = "github:numtide/nix-filter";
    systems.url = "github:nix-systems/x86_64-linux";
  };
  outputs = { self, nixpkgs, systems, ... }:
    let
      # filter = nix-filter.lib;
      lib = nixpkgs.lib;
      # lib = pkgs.lib;
      # system = "x86_64-linux";
      # function that requires a function that
      # will by applied to each element of system to generate the
      # value; key = list element
      eachSystem = lib.genAttrs (import systems);
      pkgsFor = eachSystem (system:
        nixpkgs.legacyPackages.${system}
      );
    in
    rec {
      # looks like this needs to be removed
      # in order for it to be moved to a flake check build target
      # passthru.tests = {
      #   check_python = pkgsFor.${system}.runCommand "python-test" {} ''
      #     $out/bin/python -c 'print hello'
      #   '';
      # };
      devShells = eachSystem (system: {
        default = pkgsFor.${system}.mkShell {
          name = "sen2cor-shell";
          nativeBuildInputs = with pkgsFor.${system}; [ nushell ];
        };
      });
      packages = eachSystem (system: {
        default = packages.${system}.sen2cor;
        sen2cor = 
          let
            sen2cor-deps = packages.${system}.sen2cor-deps;
          in
            pkgsFor.${system}.writeShellScriptBin "L2A_Process" ''
              # unset some variables that allows to have an isolate python environment
              unset LD_LIBRARY_PATH
              unset PYTHONPATH
              unset PYTHONHOME
              unset PYTHONEXECUTABLE
              unset PYTHONUSERBASE

              export LC_NUMERIC=C
              export GDAL_DATA=${sen2cor-deps}/share/gdal
              export GDAL_DRIVER=disable
              # added by patch
              export SEN2COR_LOG=''${SEN2COR_LOG:-$HOME/.local/sen2cor-v${sen2cor-deps.version}}

              if [ ! -d "$SEN2COR_LOG" ]; then
                mkdir -p "$SEN2COR_LOG"
              fi

              # By default puts the processed tile "next" to the input tile in toolbox mode
              # can be changed by setting "work-dir"
              exec ${sen2cor-deps}/bin/python -s ${sen2cor-deps}/lib/python2.7/site-packages/sen2cor/L2A_Process.py "$@"
            '';
        sen2cor-deps =
         pkgsFor.${system}.stdenv.mkDerivation rec {
          name = "sen2cor-deps";
          version = "2.11.0";

          src = pkgsFor.${system}.fetchurl {
            # just to make sure version is kept in-sync!
            url = "https://step.esa.int/thirdparties/sen2cor/${version}/Sen2Cor-02.11.00-Linux64.run";
            sha256 = "jEqtMlSdGRz1flNJ3JeFv4B94HyT6hgtcRrIng0Ib3U=";
          };

          unpackCmd = "bash $curSrc --noexec --nox11 --target source";

          patches = [ ./0001-add-logDir-env.patch];

          installPhase = ''
        		runHook preInstall
        		mkdir -p $out/bin
        		cp bin/* $out/bin/
        		# should also make autoPatchElf search
        		# for libraries in lib/
        		mkdir -p $out/lib
        		cp -r lib/* $out/lib/
        		mkdir -p $out/share
        		cp -r share/* $out/share/

            # L2A_GIPP.xml is resolved realtive to the script directory!
            # may require SEN2COR_CONFIG_FILE=SEN2COR_HOME/cfg/L2A_GIPP.xml for use!
            mkdir $out/cfg
            #lib/python2.7/site-packages/sen2cor/cfg
            cp -r lib/python2.7/site-packages/sen2cor/cfg/L2A_GIPP.xml $out/cfg/

        		cp make_symlinks $out/

        		# custom build steps
        		OUT_DIR=$out bash $out/make_symlinks
        		ln -sf "$out/lib/ld-musl-x86_64.so.1" "$out/lib/libc.musl-x86_64.so.1"

            cp $test/bin/* $out/bin/
        		runHook postInstall
        	'';

          dontAutoPatchelf = true;

          postFixup = ''
        		# This successfully fixes all issues with linking
        		# to the dynamic libraries but it does NOT
        		# set the interpreter correctly, as we are relying
        		# on a hack by manually defining the interpreter
        		autoPatchelfLibs=$out/lib
        		autoPatchelf --no-recurse $out/bin

        		# so it requires a manual step to fix it
        		# might need to fix the GDAL/share path before calling +
        		# the python path
        		patchelf --set-interpreter $out/lib/ld-musl-x86_64.so.1 $out/bin/python2.7
        		# can run through all files (skipping symbolic links)
        		# and checking if patchelf --print-interpreter returns a non-zero exit code
            # FUTURE: Could improve this by using `nuenv` and creating a `writeScriptBin` method
        		${pkgsFor.${system}.nushell}/bin/nu -c 'ls $env.out | where type == "file" | get name | filter {|x| (patchelf $x | complete | get exit_code) == 0 } | each {|p| patchelf --set-interpreter $env.out + "/lib/ld-musl-x86_64.so.1" $p }'
        		# looks like there is no easy way to overwrite the
        		# standard interpreter
        		# dynamic-linker correctly
        	'';

          dontStrip = false;
          dontPatchELF = true;

          doInstallCheck = true;

          nativeBuildInputs = [
            pkgsFor.${system}.autoPatchelfHook
          ];
        };
      });
    };
}
