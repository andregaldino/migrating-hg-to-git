mkcommit() {
   name="$1"
   shift
   echo "$name" > "$name"
   hg add "$name"
   hg ci -m "$name" "$@"
}
