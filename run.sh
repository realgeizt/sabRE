#!/bin/bash

compile() {
  C=$(which coffee)
  if [[ $? != 0 ]] ; then
    C='./node_modules/coffee-script/bin/coffee'
    [[ ! -e "$C" ]] && output 'error' 'coffee executable not found (did you forget "npm install"?)' && return 1
  fi
  
  ! "$C" --bare --compile --output public/js cs_public/js && return 1
  ! "$C" --bare --compile --output app cs_app && return 1
  
  return 0
}

stopnode() {
  kill $Z > /dev/null 2>&1
  return 0
}

startnode() {
  output 'starting node...'
  C=$(which node)
  [[ $? != 0 ]] && C=$(which nodejs)
  if [[ $1 == 2 ]] ; then
    "$C" app/app.js &
    Z=$!
    sleep 1
    ! (ps -p $Z > /dev/null 2>&1) && output 'error' 'failed to start node' && return 1 || return 0
  else
    "$C" app/app.js
  fi
}

hash() {
  echo `ls -lR . | grep .coffee | sha1sum`
}

output() {
  [[ $1 == "info" ]] && echo -e '\e[1;36minfo: \e[0;35m'$2'\e[00m'
  [[ $1 == "error" ]] && echo -e '\e[0;31merror: \e[0;35m'$2'\e[00m'
  return 0
}

run() {
  output 'info' 'starting up...'

  # erstmal alles kompilieren
  ! compile && output 'error' 'error compiling file, exiting...' && exit 1

  if [[ $1 == 'dev' ]] ; then
    ! startnode 2 && output 'error' 'error starting node, exiting...' && exit 1
      
    # jetzt das fs beobachten
    previous_sha=$(hash)
    while true; do
      sha=$(hash)
      if [[ $sha != $previous_sha ]] ; then
        # es hat sich was geändert. 2 sek warten und nochmal prüfen
        sleep 2
        sha2=$(hash)
        
        # wenn sich in den 2 sek noch mehr geändert hat, alles von vorne
        [[ $sha != $sha2 ]] && continue
        
        output 'info' 'changes detected, restarting...'
        
        # stillstand, neu bauen und so      
        previous_sha=$sha
        
        if compile; then
          stopnode
          ! startnode 2 && output 'error' 'error starting node, waiting for changes...'
        else
          output 'error' 'error compiling file, waiting for changes...'
        fi
      fi
      
      if (read -s -t 2); then
        output 'info' 'restarting...'
        stopnode
        startnode 2
      fi
    done
  else
    startnode 1
  fi
}

control_c() {
  output 'info' 'exiting...' && stopnode && exit 0
}

trap control_c SIGINT

run $@
exit 0
