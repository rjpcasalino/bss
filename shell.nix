{ pkgs ? import <nixpkgs> {}
}:
pkgs.mkShell {
  name = "boring";
  buildInputs = [
    pkgs.perl # important!
    pkgs.perlPackages.TextMarkdown 
    pkgs.perlPackages.TemplateToolkit 
    pkgs.perlPackages.LogDispatch
  ];
}
