# shellcheck shell=bash
# shellcheck disable=SC2207

_enban() {
  local cur prev
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"
  if [[ "${prev}" == "--theme" ]]; then
    COMPREPLY=($(compgen -W "kodougu catppuccin-mocha catppuccin-latte dracula nord gruvbox tokyo-night mono" -- "${cur}"))
    return
  fi
  if [[ "${cur}" == -* ]]; then
    COMPREPLY=($(compgen -W "--theme" -- "${cur}"))
    return
  fi
  COMPREPLY=($(compgen -W "doctor version help" -- "${cur}"))
}

complete -F _enban enban
