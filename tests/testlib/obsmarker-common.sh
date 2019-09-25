mkcommit() {
   name="$1"
   shift
   echo "$name" > "$name"
   hg add "$name"
   hg ci -m "$name" "$@"
}

getid() {
   hg log --hidden --template '{node}\n' --rev "$1"
}

cat >> $HGRCPATH <<EOF
[alias]
debugobsolete=debugobsolete -d '0 0'
EOF
