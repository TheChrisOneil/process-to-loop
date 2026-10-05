# Shared parser for a tool catalog. Read by the validator, preflight and the
# interview, so none of them can disagree about what the organization has.
#
# Populates: CAT["catalog.<key>"] · TID[1..t] · T["<id>.<key>"]
/^[[:space:]]*#/ { next }
/^[[:space:]]*$/ { next }
/^@catalog/ { sec="catalog"; next }
/^@tool[ \t]/ { t++; TID[t]=$2; sec="tool"; cur=$2; next }
{
  line=$0; sub(/^[ \t]+/,"",line); sub(/[ \t]+$/,"",line)
  i=index(line,":"); if (i==0) next
  ky=substr(line,1,i-1); v=substr(line,i+1); sub(/^[ \t]+/,"",v); sub(/[ \t]+$/,"",v)
  if (sec=="catalog") CAT["catalog." ky]=v
  else if (sec=="tool") T[cur "." ky]=v
}
