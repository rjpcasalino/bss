{
  description = "A flake for building bss";

  inputs.nixpkgs.url = github:NixOS/nixpkgs/af0a54285ed4ff131f205517aeafb94a9a5898cb;
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }: 
  flake-utils.lib.eachDefaultSystem (system:
    with nixpkgs.legacyPackages.${system};
    let bss = 
        buildPerlPackage {
        pname = "bss";
        version = "0.1";
        src = self;
        propagatedBuildInputs = [
         perlPackages.TemplateToolkit
         perlPackages.ModuleInstall
         perlPackages.ConfigIniFiles
         perlPackages.YAML
         perlPackages.TextMarkdown
        ];
        buildInputs = [ 
         rsync
       ] ++ lib.optional stdenv.isDarwin shortenPerlShebang;
        postInstall = lib.optional stdenv.isDarwin ''
          shortenPerlShebang $out/lib/perl5/site_perl/${perl.version}/bss.pl
        '';
      };
    in rec {
      defaultPackage = bss;
      }
  );
}
