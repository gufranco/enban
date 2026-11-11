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
  if [[ "${prev}" == "--drive" ]]; then
    COMPREPLY=($(compgen -f -- "${cur}"))
    return
  fi
  if [[ "${cur}" == -* ]]; then
    COMPREPLY=($(compgen -W "--drive --json --speed --verify --no-verify --eject --no-eject --fs --label --full --sectors --csv --lba --title --performer --pregap --raw --finalize --set --theme" -- "${cur}"))
    return
  fi
  if [[ "${COMP_WORDS[1]}" =~ ^(write|read|verify|build|checksum|queue|sector|cue|convert)$ && "${COMP_CWORD}" -gt 1 ]]; then
    COMPREPLY=($(compgen -f -- "${cur}"))
    return
  fi
  COMPREPLY=($(compgen -W "info write read verify build erase checksum queue discovery sector cue close speed region booktype convert doctor version help" -- "${cur}"))
}

complete -F _enban enban
