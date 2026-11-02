# Turns the agent's draft into a GitHub review payload. With no "event" field, GitHub creates it as PENDING.
# Findings on a line outside the PR diff can't be inline comments, so they go in the review body.
($lines | split("\n") | map(select(length > 0)) | INDEX(.)) as $in
| .findings as $f
| ($f | map(select($in["\(.path):\(.line)"] and $in["\(.path):\(.start_line // .line)"]))) as $inline
| ($f - $inline) as $loose
| ($f | map(.severity)) as $s
| {
    commit_id: $sha,
    body: (
      if ($f | length) == 0 then "Nothing needs fixing."
      else "\($f | length) finding(s): \($s | map(select(. == "Important")) | length) important, \($s | map(select(. == "Nit")) | length) nit, \($s | map(select(. == "Pre-existing")) | length) pre-existing."
        + ($loose | map("\n\n**\(.severity)** `\(.path):\(.line)`: \(.body)") | join(""))
      end
    ),
    comments: ($inline | map(
      {path, line, side: "RIGHT", body: "**\(.severity):** \(.body)"}
      + (if .start_line and .start_line != .line then {start_line, start_side: "RIGHT"} else {} end)
    ))
  }
