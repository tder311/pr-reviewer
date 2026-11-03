# Turns the agent's draft into a GitHub review payload. With no "event" field, GitHub creates it as PENDING.
# Only Important findings are posted; Nits and Pre-existing ones stay in the brief.
# Findings on a line outside the PR diff can't be inline comments, so they go in the review body.
($lines | split("\n") | map(select(length > 0)) | INDEX(.)) as $in
| (.findings | map(select(.severity == "Important"))) as $f
| ($f | map(select($in["\(.path):\(.line)"] and $in["\(.path):\(.start_line // .line)"]))) as $inline
| ($f - $inline) as $loose
| {
    commit_id: $sha,
    body: (
      (if ($f | length) == 1 then "One thing to fix before merge." else "\($f | length) things to fix before merge." end)
      + ($loose | map("\n\n`\(.path):\(.line)`: \(.body)") | join(""))
    ),
    comments: ($inline | map(
      {path, line, side: "RIGHT", body}
      + (if .start_line and .start_line != .line then {start_line, start_side: "RIGHT"} else {} end)
    ))
  }
