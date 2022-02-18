# setup config and various utility to test new heads checks on push

cat >> $HGRCPATH <<EOF
[command-templates]
# simpler log output
log ="{node|short} ({phase}): {desc}\n"

[phases]
# non publishing server
publish=False

[extensions]
# we need to strip some changeset for some test cases
strip=

[experimental]
# enable evolution
evolution=all

[alias]
# fix date used to create obsolete markers.
debugobsolete=debugobsolete -d '0 0'
EOF

mkcommit() {
   echo "$1" > "$1"
   hg add "$1"
   hg ci -m "$1"
}

getid() {
   hg log --hidden --template '{node}\n' --rev "$1"
}

setuprepos() {
    echo creating basic server and client repo
    hg init server
    cd server
    mkcommit root
    hg phase --public .
    mkcommit A0
    cd ..
    hg clone server client

    if [ "$1" = "single-head" ]; then
        echo >> "server/.hg/hgrc" "[experimental]"
        echo >> "server/.hg/hgrc" "# enforce a single name per branch"
        echo >> "server/.hg/hgrc" "single-head-per-branch = yes"
    fi
}
