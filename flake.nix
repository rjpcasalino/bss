{
  description = "A flake for building bss";

  inputs.nixpkgs.url = github:NixOS/nixpkgs/af0a54285ed4ff131f205517aeafb94a9a5898cb;

  outputs = { self, nixpkgs }: {
    defaultPackage.x86_64-darwin =
    with import nixpkgs { system = "x86_64-darwin"; };
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
      ];
    };
  };
}
