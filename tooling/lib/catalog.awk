# Shared parser for a tool catalog. Read by the validator, preflight and the
# interview, so none of them can disagree about what the organization has.
#
# Populates: CAT["catalog.<key>"] · TID[1..t] · T["<id>.<key>"]
#            SKID[1..ns] · SK["<id>.<key>"]
#
# A TOOL reaches something and has a permission. A SKILL is know-how a step
# applies and reaches nothing. They are both catalogued, for the same reason:
# permissions are inherited and not authored, and so is know-how. Two designs
# encoding the same clinical lookup table differently is the failure a catalogue
# exists to prevent, and it is worse for know-how than for tools because nothing
# at run time will notice.
/^[[:space:]]*#/ { next }
/^[[:space:]]*$/ { next }
/^@catalog/ { sec="catalog"; next }
/^@tool[ \t]/  { t++;  TID[t]=$2;   sec="tool";  cur=$2; next }
/^@skill[ \t]/ { ns++; SKID[ns]=$2; sec="skill"; cur=$2; next }
{
  line=$0; sub(/^[ \t]+/,"",line); sub(/[ \t]+$/,"",line)
  i=index(line,":"); if (i==0) next
  ky=substr(line,1,i-1); v=substr(line,i+1); sub(/^[ \t]+/,"",v); sub(/[ \t]+$/,"",v)
  if (sec=="catalog") CAT["catalog." ky]=v
  else if (sec=="tool")  T[cur "." ky]=v
  else if (sec=="skill") SK[cur "." ky]=v
}
