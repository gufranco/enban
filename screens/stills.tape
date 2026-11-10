Source common.tape
Output scratch.gif
Set Height 1100
Hide
Type ". ./setup.sh"
Enter
Sleep 1s
Show
Sleep 800ms
Type "enban burn"
Enter
Sleep 3s
Screenshot error.png
Sleep 1s
Hide
Type "clear"
Enter
Show
Sleep 800ms
Type "enban doctor"
Enter
Sleep 10s
Screenshot doctor.png
Sleep 1s
Hide
Type "clear"
Enter
Show
Sleep 800ms
Type "for t in kodougu catppuccin-mocha dracula nord gruvbox tokyo-night; do enban --theme $t version; done"
Enter
Sleep 8s
Screenshot themes.png
Sleep 1s
