# One pack directory -> its capability manifest, as sorted TSV.
#
# Public-API diffing, applied to a pack. The pack's own version field is
# unusable — 0.x.y formally permits breaking changes in any release, and every
# version of this pack on disk declares 0.1.0 — so the surface is computed,
# never consumed.
#
# Six properties. The first four are what the pack COMMITS TO. The last two are
# the judgment question, split into the part that can be computed and the part
# that can only be detected.
#
#   PROVIDES   commands and agents the pack ships
#   MANDATES   commands its prompts require an agent to run
#   DEMANDS    output contracts and required metadata keys
#   USES       formula constructs it depends on
#   NORMS      normative statements in the JUDGMENT SURFACE — role prompts and
#              template fragments, the prose that tells an agent how to decide.
#              The computable half of judgment: every must, never, only and
#              do-not. Task instructions elsewhere in the pack contribute to
#              OPAQUE instead, so command-prefix churn across workflow assets
#              does not drown the signal.
#   OPAQUE     a digest per prose file — the half that cannot be computed.
#              When this moves and nothing else does, the change is
#              UNCLASSIFIED. It is never NONE.
#
# -v ROOT=<pack dir> -v FILE=<file being read> -v REL=<its path within the pack>
function emit(prop, val) { if (val != "") print prop "\t" val }
function norm(s) { gsub(/^[ \t>*-]+/,"",s); gsub(/[ \t]+$/,"",s); gsub(/[ \t]+/," ",s)
                   gsub(/`/,"",s); return s }
{
  line = $0

  # MANDATES — a command the prose tells an agent to run
  if (match(line, /gc [a-z][a-z0-9 -]*(claim|drain-ack)[a-z0-9 -]*/)) {
    c = norm(substr(line, RSTART, RLENGTH))
    sub(/ +$/,"",c); emit("MANDATES", c)
  }
  # DEMANDS — output contracts and reserved metadata the pack requires
  while (match(line, /gc\.(output_json[a-z_]*|run_target|kind|scope_[a-z]+|on_fail|continuation_group)/)) {
    emit("DEMANDS", substr(line, RSTART, RLENGTH)); line = substr(line, RSTART+RLENGTH)
  }
  line = $0
  while (match(line, /"[a-z][a-z0-9_.-]*\.v[0-9]+"/)) {
    emit("DEMANDS", "schema:" substr(line, RSTART+1, RLENGTH-2)); line = substr(line, RSTART+RLENGTH)
  }
  line = $0
  # USES — formula constructs
  if (line ~ /^\[steps\.(check|retry|drain|on_complete|gate|loop)\]/) {
    c = line; gsub(/[][]/,"",c); emit("USES", c)
  }
  if (line ~ /formula_compiler/) emit("USES", "requires.formula_compiler")

  # NORMS — the computable half of judgment. A rule stated in prose is still a
  # rule, and a rule that changes is a behaviour change with no surface change.
  if (REL ~ /(^|\/)(roles\/agents|template-fragments|prompts)\//) {
    l = tolower(line)
    if (l ~ /(^|[^a-z])(must not|must never|must|never|always|do not|only permitted|is the only|may not|shall)([^a-z]|$)/) {
      s = norm(line)
      if (length(s) > 12 && s !~ /^#/ && s !~ /^\/\//) emit("NORMS", REL ": " substr(s, 1, 160))
    }
  }
}
