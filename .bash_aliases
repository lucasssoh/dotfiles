# Couleurs pour Linux pur
alias ls='ls --color=auto --group-directories-first'
alias grep='grep --color=auto'
alias diff='diff --color=auto'

# Navigation simple
alias ..='cd ..'
alias ...='cd ../..'
alias ll='ls -lh'
alias la='ls -lAh'

# Tes commandes actuelles
alias refresh-brave='rm ~/.config/BraveSoftware/Brave-Browser/SingletonLock'

# Paths ()
export PATH="$HOME/.symfony5/bin:$HOME/.symfony/bin:$PATH"
. "$HOME/.cargo/env" 2>/dev/null
