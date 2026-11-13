# Turns the agent's draft into a GitHub review payload. With no "event" field, GitHub creates it as PENDING.
# Only Important findings and questions for the author are posted; Nits and Pre-existing ones stay in the brief.
# Findings on a line outside the PR diff can't be inline comments, so they go in the review body.
($lines | split("\n") | map(select(length > 0)) | INDEX(.)) as $in
| (.findings | map(select(.severity == "Important"))) as $f
| (.author_questions // []) as $q
| ($f | map(select($in["\(.path):\(.line)"] and $in["\(.path):\(.start_line // .line)"]))) as $inline
| ($f - $inline) as $loose
| {
    commit_id: $sha,
    body: (
      (if ($f | length) == 0 then (if $q == [] then "Nothing to fix before merge." else "Nothing to fix, but please check these before merge:" end)
       elif ($f | length) == 1 then "One thing to fix before merge."
       else "\($f | length) things to fix before merge." end)
      + ($loose | map("\n\n`\(.path):\(.line)`: \(.body)") | join(""))
      + (if $q == [] then "" elif ($f | length) == 0 then "\n\n" else "\n\nAlso, please check these before merge:\n\n" end)
      + ($q | map("- " + .) | join("\n"))
    ),
    comments: ($inline | map(
      {path, line, side: "RIGHT", body}
      + (if .start_line and .start_line != .line then {start_line, start_side: "RIGHT"} else {} end)
    ))
  }
