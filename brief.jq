# Renders the private brief: what Tom reads before opening the PR. None of this is posted.
def bullets(f): if length == 0 then "- none" else map("- " + f) | join("\n") end;
def marks: .votes | map({CONFIRMED: "✓", REFUTED: "✗"}[.verdict] // "?") | join("");

($votes[0] | INDEX(.id)) as $by_id
| def finding: "**\(.severity)** \((.ids // []) | map(($by_id[.] // {votes: []}) | marks) | join(" ")) `\(.path):\(.line)`: \(.body)";
  (.findings | map(select(.severity == "Important"))) as $posted
| (.findings - $posted) as $held
| "# \($repo)#\($pr): \($title)\n\n"
+ "**Risk: \(.risk).** \(.risk_reason)\n\n"
+ "## To fix before merge (\($posted | length))\n\nThese make up your pending review.\n\n\($posted | bullets(finding))\n\n"
+ "## Minor, not posted (\($held | length))\n\nAdd any of these when you reply, for example \"comment, and add the nit\".\n\n\($held | bullets(finding))\n\n"
+ "## Look at these yourself\n\n\(.look_yourself | bullets(.))\n\n"
+ "## What the change does\n\n\(.explainer)\n\n"
+ "## Already raised by others\n\n\(.already_raised | bullets(.))\n\n"
+ "## Verification votes\n\n✓ confirmed, ✗ refuted, ? unsure. A candidate needs \($need) confirmations to survive.\n\n"
+ "\($votes[0] | bullets("\(.id) \(marks) \(if .kept then "kept" else "dropped" end): \(.claim) `\(.path):\(.line)`, found by \(.found_by | join(", "))"))\n\n"
+ "## Filtered before verification\n\n\($filtered[0].dropped | bullets("\(.claim): \(.reason)"))\n\n"
+ "## Dropped while writing\n\n\(.dropped | bullets("\(.claim): \(.reason)"))\n\n"
+ "---\n\nRun took \($mins) min; API-equivalent cost $\($cost), counted against your Claude plan. Review range: `\($range)`."
+ (if $failed == "" then "" else " Stages that failed:\($failed)." end) + "\n"
