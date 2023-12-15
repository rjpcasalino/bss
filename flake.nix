{
  description = "A flake for building bss";

  inputs.nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable-small;
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      with nixpkgs.legacyPackages.${system};
      let
        bss =
          perlPackages.buildPerlPackage {
            pname = "bss";
            version = "0.1";
            src = self;
            propagatedBuildInputs = with perlPackages; [
              DateTime
              TemplateToolkit
              ModuleInstall
              ConfigIniFiles
              YAML
              TextMarkdown
            ];
            buildInputs = [
              makeWrapper
            ] ++ lib.optionals stdenv.isDarwin [ shortenPerlShebang ];
            postInstall = ''
              mkdir -p $out/bin
              ${if stdenv.isDarwin then "shortenPerlShebang $out/lib/perl5/site_perl/${perl.version}/bss.pl" else ""}
              wrapProgram $out/lib/perl5/site_perl/${perl.version}/bss.pl --prefix PATH : ${lib.makeBinPath[ rsync ]}
              ln -fs $out/lib/perl5/site_perl/${perl.version}/bss.pl $out/bin/bss
            '';
          };
      in
      {
        packages.default = bss;
      }
    );
}

