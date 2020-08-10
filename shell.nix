{ pkgs ? import <nixpkgs> {}
}:
pkgs.mkShell {
  name = "bss";
  buildInputs = [
    pkgs.perl # important!
    pkgs.perlPackages.TextMarkdown 
    pkgs.perlPackages.TemplateToolkit 
    pkgs.perlPackages.LogDispatch
  ];
}
