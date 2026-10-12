# Shared parser for a tool catalog. Read by the validator, preflight and the
# interview, so none of them can disagree about what the organization has.
#
# Populates: CAT["catalog.<key>"] · TID[1..t] · T["<id>.<key>"]
#            SKID[1..ns] · SK["<id>.<key>"]
#            SKNF[id] · SKF[id,1..SKNF[id]] · SKFV[id,1..SKNF[id]]
#
# SKF/SKFV keep a skill's fields in the order they were written, repeats
# included. SK keeps only the last value of a key, which is right for a reader
# asking "what is the owner" and wrong for a person reviewing the entry: every
# `refined:` line is a record of who changed what, and the review page shows
# all of them, not the most recent.
#
# A TOOL reaches something and has a permission. A SKILL is know-how a step
# applies and reaches nothing. They are both catalogued, for the same reason:
# permissions are inherited and not authored, and so is know-how. Two designs
# encoding the same clinical lookup table differently is the failure a catalogue
# exists to prevent, and it is worse for know-how than for tools because nothing
# at run time will notice.
#
# A skill with `status: proposed` is catalogued and NOT in force. It names an
# owner and waits for them: no step may depend on it (V40), and the bundle never
# logs it as in force. `skills.sh accept` is what turns it into a dependency.
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
  else if (sec=="skill") { SK[cur "." ky]=v; SKNF[cur]++; SKF[cur, SKNF[cur]]=ky; SKFV[cur, SKNF[cur]]=v }
}
