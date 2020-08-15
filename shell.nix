{ pkgs ? import <nixpkgs> {}
}:
pkgs.mkShell {
  name = "bss";
  buildInputs = [
    pkgs.perl # important!
    pkgs.perlPackages.ConfigIniFiles
    pkgs.perlPackages.FileSlurp
    pkgs.perlPackages.TextMarkdown 
    pkgs.perlPackages.TemplateToolkit 
    pkgs.perlPackages.HTTPServerSimple 
    pkgs.rsync
  ];
}
