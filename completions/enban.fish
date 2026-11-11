complete -c enban -n __fish_use_subcommand -a info -d 'describe the drive and the disc in it'
complete -c enban -n __fish_use_subcommand -a doctor -d 'check the tools enban needs'
complete -c enban -n __fish_use_subcommand -a version -d 'print the version'
complete -c enban -n __fish_use_subcommand -a help -d 'print usage'

complete -c enban -l drive -r -F -d 'the drive to read'
complete -c enban -l json -d 'print the result as one JSON object'
complete -c enban -l theme -r -a 'kodougu catppuccin-mocha catppuccin-latte dracula nord gruvbox tokyo-night mono' -d 'colours of the terminal interface'
