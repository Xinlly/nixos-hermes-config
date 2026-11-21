{ lib, pkgs, hermes, extraKeys ? [ ] }:

let
  keys = [
    "ARK_API_KEY"
    "MINIMAX_CN_API_KEY"
    "MINIMAX_CN_BASE_URL"
    "HERMES_TIMEZONE"
  ] ++ extraKeys;
  assignments = lib.concatMapStringsSep "\n" (key: ''allowed["${key}"] = 1'') keys;
  helper = pkgs.writeShellScript "hermes-profile-environment" ''
    exec ${lib.getExe pkgs.gawk} '
      BEGIN {
        ${assignments}
      }
      match($0, /^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z_0-9]*)[[:space:]]*=/, fields) {
        if (fields[2] in allowed) print
      }
    ' ${lib.escapeShellArg "${hermes.stateDir}/.hermes/.env"}
  '';
in
{
  enabled = true;
  command = "${helper}";
}
