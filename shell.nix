{ pkgs ? import <nixpkgs> {}
}:
pkgs.mkShell {
  name = "bss";
  buildInputs = [
    pkgs.perl # important!
    pkgs.perlPackages.PerlTidy
    pkgs.perlPackages.ConfigIniFiles
    pkgs.perlPackages.TextMarkdown 
    pkgs.perlPackages.TemplateToolkit 
    pkgs.perlPackages.YAML
    pkgs.perlPackages.AppFatPacker
    pkgs.rsync
  ];
}
