{ pkgs ? import <nixpkgs> {}
}:
pkgs.mkShell {
  name = "bss";
  buildInputs = [
    pkgs.perl # important!
    pkgs.perlPackages.PerlTidy
    pkgs.perlPackages.ConfigIniFiles
    pkgs.perlPackages.FileSlurp
    pkgs.perlPackages.TextMarkdown 
    pkgs.perlPackages.TemplateToolkit 
    pkgs.perlPackages.YAML
    pkgs.perlPackages.AppFatPacker
    pkgs.perlPackages.DistZilla
    pkgs.perlPackages.Carton
    pkgs.rsync
  ];
}
