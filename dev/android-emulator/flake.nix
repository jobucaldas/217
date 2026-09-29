{
  description = "217 Android Web Push validation harness";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
        };
      };
      android = pkgs.androidenv.composeAndroidPackages {
        abiVersions = [ "x86_64" ];
        buildToolsVersions = [ "34.0.0" ];
        includeEmulator = true;
        includeExtras = [ ];
        includeNDK = false;
        includeSources = false;
        includeSystemImages = true;
        platformToolsVersion = "34.0.5";
        platformVersions = [ "34" ];
        systemImageTypes = [ "google_apis_playstore" ];
        toolsVersion = "26.1.1";
        useGoogleAPIs = true;
      };
      runtimeInputs = [
        android.androidsdk.out
        pkgs.bash
        pkgs.coreutils
        pkgs.curl
        pkgs.findutils
        pkgs.gawk
        pkgs.gnused
        pkgs.gnugrep
        pkgs.jq
        pkgs.nodejs_22
        pkgs.postgresql
        pkgs.procps
        pkgs.python3
      ];
      app = pkgs.writeShellApplication {
        name = "android-emulator-harness";
        runtimeInputs = runtimeInputs;
        text = ''
          export ANDROID_SDK_ROOT=${android.androidsdk.out}/libexec/android-sdk
          export ANDROID_HOME=$ANDROID_SDK_ROOT
          export ANDROID_EMULATOR_BIN=${android.emulator}/bin/emulator
          export ANDROID_ADB_BIN=${android."platform-tools"}/bin/adb
          export ANDROID_AVDMANAGER_BIN=${android."cmdline-tools-package".path}/bin/avdmanager
          exec ${./scripts/android.sh} "$@"
        '';
      };
    in
    {
      packages.${system}.default = app;
      apps.${system}.default = {
        type = "app";
        program = "${app}/bin/android-emulator-harness";
      };
      devShells.${system}.default = pkgs.mkShell {
        packages = runtimeInputs;
        shellHook = ''
          export ANDROID_SDK_ROOT=${android.androidsdk.out}/libexec/android-sdk
          export ANDROID_HOME=$ANDROID_SDK_ROOT
          export ANDROID_EMULATOR_BIN=${android.emulator}/bin/emulator
          export ANDROID_ADB_BIN=${android."platform-tools"}/bin/adb
          export ANDROID_AVDMANAGER_BIN=${android."cmdline-tools-package".path}/bin/avdmanager
        '';
      };
    };
}
