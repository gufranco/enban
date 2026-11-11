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
    COMPREPLY=($(compgen -W "--drive --json --speed --copies --delete-image --mode --no-finalize --opc --retries --ignore-errors --cue --ignore-miscompares --verify --no-verify --eject --no-eject --fs --label --publisher --preparer --application --system-id --volume-set --date --iso-level --boot --emulation --platform --load-sectors --boot-info-table --dvd-video --full --sectors --csv --lba --title --performer --pregap --raw --finalize --test --set --theme" -- "${cur}"))
    return
  fi
  if [[ "${COMP_WORDS[1]}" =~ ^(write|read|verify|build|checksum|queue|sector|cue|convert|label|layerbreak|mount|unmount)$ && "${COMP_CWORD}" -gt 1 ]]; then
    COMPREPLY=($(compgen -f -- "${cur}"))
    return
  fi
  COMPREPLY=($(compgen -W "info write read verify build erase checksum queue discovery sector cue close speed region booktype convert label layerbreak mount unmount speeds doctor version help" -- "${cur}"))
}

complete -F _enban enban
