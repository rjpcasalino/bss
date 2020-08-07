{ pkgs ? import <nixpkgs> {}
}:
pkgs.mkShell {
  name = "dev-discovery";
  buildInputs = [
    pkgs.perl # important!
    pkgs.perlPackages.TextMarkdown 
    pkgs.perlPackages.TemplateToolkit 
    pkgs.perlPackages.LogDispatch
  ];
}
