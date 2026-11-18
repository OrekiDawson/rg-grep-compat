Linux x86_64 static binary is distributed from the GitHub v0.1.0 Release page:
  https://github.com/OrekiDawson/rg-grep-compat/releases/tag/v0.1.0

After downloading the binary into this directory, install from the repository root:
  bash scripts/install-user.sh "$PWD/dist/rg-grep-compat-linux-x86_64-static"

Alternatively, build the project from source with 'make' and 'make install-user'.
GNU grep remains a required dependency. Do not overwrite /usr/bin/grep.
