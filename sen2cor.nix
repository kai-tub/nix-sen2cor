{ lib, stdenv, fetchurl, makeself }:

stdenv.mkDerivation {
	name = "sen2cor";

	src = fetchurl {
		url = "https://step.esa.int/thirdparties/sen2cor/2.11.0/Sen2Cor-02.11.00-Linux64.run";
		sha256 = "jEqtMlSdGRz1flNJ3JeFv4B94HyT6hgtcRrIng0Ib3U=";
	};

	# Maybe makeself, doesn't need makeself itself? --nochown (?)
	# The path to the current source file is contained in the curSrc variable.
  unpackCmd = "bash $curSrc --noexec --nox11 --target source";

	# buildPhase needs to be updated to execute the pkgsetup bash script
	# I have the feeling that it needs to be used in the 
	# installPhase and NOT buildPhase, as it creates the
	# symbolic links here...
	# buildPhase = ''
	# 	bash pkgsetup
	# '';

	# gotta fix call to $HOME/$XDG_CONFIG_HOME
	# needs to be linked back to the current directory
	# These are used in the script to create the default xml file
	# but this fails in the current version
	postPatch = ''
	# could be set to some config folder maybe?
	echo 'Patching references to $HOME'
	substituteInPlace pkgsetup \
     --replace '$HOME' '$OUT_DIR'
	echo 'Do not remove build scripts after executing'
	substituteInPlace pkgsetup \
		--replace 'rm -f' '#rm -f'
	echo 'Try my best to patch out patchelf call'
	# They use this strategy to call their OWN patchelf binary!
	# I kinda understand it. But it, but then I really do not understand why it isn't
	# working...
	# substituteInPlace pkgsetup \
	# 	--replace '"$INTERPRETER" "$PATCHELF_EXE"' 'patchelf --set-interpreter "$INTERPRETER"'
	substituteInPlace pkgsetup \
		--replace '> /dev/null 2>&1' ""
	'';

	# make_symlinks links all of the shared libraries in lib to the
	# "desired" output name, such as from 
	# ln -sf "$OUT_DIR/lib/libfreetype.so.6.12.6" "$OUT_DIR/lib/libfreetype.so" 
	# ln -sf "$OUT_DIR/lib/libfreetype.so.6.12.6" "$OUT_DIR/lib/libfreetype.so.6" 
	# IMO even if I do not fully grasp why they do it like this, I think
	# there is no harm in having them link them manually like this.
	# So make_symlinks should be "fine" to keep/execute

	# Ok, patching may require a bit more thought on my end to get right...
	# The general idea should be very similar to what Nix is "normally doing".

	# 
	
	# L2A_Bashrc
	# contains #!/bin/sh -> Needs to be fixed
	# Just executing the PostInstall hook seems to already fix the issue:
	# /nix/store/m3s60wydnnfzwg7ig4x9g1f06b3na3m0-sen2cor/bin/L2A_Process: interpreter directive changed from "#!/bin/sh" to "/nix/store/dsd5gz46hdbdk2rfdimqddhq6m8m8fqs-bash-5.1-p16/bin/sh"

	# unsets a lot of environment variables (PYTHONPATH,LD_LIBRARY_PATH etc)
	# unsets the GDAL_DRIVER_PATH=disable and sets the path to
	# GDAL_DATA to $out_dir/share/gdal
	# sets the home directories that will be used by the application
	# and which are the binary paths
	# Sets LC_NUMERIC=C

	# The binary L2A_Process
	# sources L2A_Bashrc by itself
	# Then calls the binary L2A_Process.py and provides the additional arguments.

	# Maybe I should create that shell file manually be generating a wrapperfile?
	# 

	# Debug:
	# nix-shell --pure --run env /nix/store/39ah25v6iwlka3jl2angxrlx00mk2ijd-env.drv

	
	installPhase = ''
		runHook preInstall
		# $outputBin
		mkdir -p $out/bin
		cp bin/* $out/bin/
		# $outputLib
		mkdir -p $out/lib
		cp -r lib/* $out/lib/
		mkdir -p $out/share
		cp -r share/* $out/share/

		cp pkgsetup $out/
		cp make_symlinks $out/
		bash $out/pkgsetup
		runHook postInstall
	'';

	dontStrip = true;
	dontPatchELF = true;

	# postInstall helps us with:
	# - patching script interpreter paths
	# -> fixes use of /bin/sh for us
	# - Rewriting symbolic links to be relative to root

	# segmentation fault in "$INTERPRETER" "$PATHELF_EXE"

	# notes on pkgsetup:
	# LIB_FILES is something like:
	# bin/gdalwarp
	# lib/libncursesw.so.6.0
	# lib/libopencv_video.so.3.4.13
	# by searching for all files that are of type elf
	# and manually sets LD_LIBRARY_PATH to OUT_DIR/lib
	
	

	
	# unpackCmd should be used to set the output
	nativeBuildInputs = [
		makeself
	];
}
