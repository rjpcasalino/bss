{
  description = "A flake for building bss";

  inputs.nixpkgs.url = github:NixOS/nixpkgs/nixos-20.03;

  outputs = { self, nixpkgs }: {
  
    defaultPackage.x86_64-linux =
      with import nixpkgs { system = "x86_64-linux"; };
      stdenv.mkDerivation {
        name = "bss";
        src = self;
        buildInputs = [ perl ];
        preInstall = ''
         echo -n "$src"
        '';
        installPhase = "mkdir -p $out/bin; cp bss.pl $out/bin/bss";
      };

  };
}
