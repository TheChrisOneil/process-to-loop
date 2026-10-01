# The intake screen. A RULE, applied to text written outside this system, before any model
# reads it. A rule cannot be talked out of its answer.
{ all = all " " tolower($0); chars += length($0) + 1 }
END {
  if (chars > MAXCHARS) { print "TOO_LONG\t" chars; exit }
  if (chars < 60)       { print "TOO_SHORT\t" chars; exit }
  if (all ~ /ignore (all )?(previous|prior|above)/ ||
      all ~ /system (note|prompt|message)/ ||
      all ~ /disregard (the )?(rules|instructions)/ ||
      all ~ /you are now|new instructions|act as/ ||
      all ~ /reveal (your|the) (prompt|instructions|system)/) { print "INJECTION_SUSPECT\t" chars; exit }
  print "OK\t" chars
}
