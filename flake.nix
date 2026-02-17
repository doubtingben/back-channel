{
  description = "Analyze This dev environment";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
  in {
    devShells.${system}.default = pkgs.mkShell {
      packages = with pkgs; [
        python312
        uv
        nodejs_22
        # add build tools here if you hit native deps:
        # gcc pkg-config openssl zlib
      ];

      shellHook = ''
        git config user.email "doubtingben@gmail.com"
        git config user.name "Ben Wilson"

        # Setup Ansible environment
        if [ -d "infra/terraform/ansible" ]; then
          echo "Setting up Ansible environment..."
          export ANSIBLE_HOME="$PWD/infra/terraform/ansible"
          export VIRTUAL_ENV="$ANSIBLE_HOME/.venv"
          
          # Create/sync the virtual environment if needed
          (cd "$ANSIBLE_HOME" && uv sync)
          
          # Activate the environment
          source "$VIRTUAL_ENV/bin/activate"
          
          # Set ansible config path if it exists
          if [ -f "$ANSIBLE_HOME/ansible.cfg" ]; then
            export ANSIBLE_CONFIG="$ANSIBLE_HOME/ansible.cfg"
          fi
        fi

        if [ -d agent ]; then
          cd agent
        fi
      '';
    };
  };
}
