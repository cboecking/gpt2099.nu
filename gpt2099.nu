def or-else [or_else: closure] {
  if ($in | is-not-empty) {$in} else {do $or_else}
}

export def id-to-messages [id: string] {
  mut messages = []
  mut current_id = $id

  while $current_id != null {
    let frame = .get $current_id
    let role = $frame | get meta | if ($in | is-not-empty) {$in} else {{}} | default "user" role | get role
    let content = (.cas $frame.hash)
    let message = {
      role: $role
      content: $content
    }
    $messages = $messages | prepend $message

    # Get the next ID from the continues field or stop if it doesn't exist
    let next_id = $frame | get meta?.continues?
    if $next_id == null {
      break
    }
    $current_id = $next_id
  }

  return $messages
}

def id-to-message [id: string] {
  let frame = .get $id
  let role = $frame | get meta | if ($in | is-not-empty) {$in} else {{}} | default "user" role | get role
  return {
    role: $role
    content: (.cas $frame.hash)
  }
}

# todo: help fix tree-sitter:
# ]: list<record<role: string content: string>> -> string {
def call-openai [ --streamer: closure] {
  let data = {
    model: "gpt-4o"
    stream: true
    messages: $in
  }

  (
    http post
    --content-type application/json
    -H { "Authorization": $"Bearer ($env.OPENAI_API_KEY)" }
    https://api.openai.com/v1/chat/completions
    $data
  ) | lines | each {|line|

    if $line == "data: [DONE]" { return }
    if ($line | is-empty) { return }

    $line | str substring 6.. | from json | get choices.0.delta | if ($in | is-not-empty) {$in.content} | tee {
      each {if ($streamer | is-not-empty) {do $streamer}}
    }
  } | str join
}

export def new [] {
  let content = or-else {|| input "prompt: "}
  let frame = $content | .append message --meta { role: "user" }
  id-to-messages $frame.id | call-openai --streamer {|| print -n $in} | .append message --meta { role: "assistant" continues: $frame.id }
  return
}

export def continue [ --id: string] {
  let content = or-else {|| input "prompt: "}
  let thread = $id | or-else {|| .cat | where topic == "message" | last}
  let frame = $content | .append message --meta { role: "user" continues: $thread.id }
  id-to-messages $frame.id | tee {print $in} | call-openai --streamer {|| print -n $in} | .append message --meta { role: "assistant" continues: $frame.id }
  return
}
