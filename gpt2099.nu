def iff [
  action: closure
  --else: closure
]: any -> any {
  if ($in | is-not-empty) {do $action} else {
    if ($else | is-not-empty) {do $else}
  }
}

def or-else [or_else: closure] {
  if ($in | is-not-empty) {$in} else {do $or_else}
}

export-env {
  $env.GPT2099_PROVIDERS = {
    openai: {
      call: {||
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

          $line | str substring 6.. | from json | get choices.0.delta | if ($in | is-not-empty) {$in.content}
        }
      }
    }

    anthropic : {
      call: {||
        let data = {
          model: "claude-3-5-sonnet-20241022"
          max_tokens: 1024
          stream: true
          messages: $in
        }

        (
          http post
          --content-type application/json
          -H {
            "x-api-key": $env.ANTHROPIC_API_KEY
            "anthropic-version": "2023-06-01"
          }
          https://api.anthropic.com/v1/messages
          $data
        ) | lines | each {|line|
          $line | split row -n 2 "data: " | get 1?
        } | each {|x|
          $x | from json
        } | where type == "content_block_delta" | each {|x|
          $x | get delta.text
        }
      }
    }
  }
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
export def --env call [ --streamer: closure] {
  let content = $in
  ensure-provider
  $content | do $env.GPT2099_PROVIDER.call | tee {
    each {if ($streamer | is-not-empty) {do $streamer}}
  } | str join
}

export def read-input [] {
  iff {||
    match ($in | describe -d | get type) {
      "string" => $in
      "list" => ($in | str join "\n\n----\n\n")
      _ => ( error make { msg: "TBD" })
    }
  } --else {|| input "prompt: "}
}

export def --env new [] {
  let content = read-input
  let frame = $content | .append message --meta { role: "user" }
  id-to-messages $frame.id | call --streamer {|| print -n $in} | .append message --meta { role: "assistant" continues: $frame.id }
  return
}

export def --env resume [ --id: string] {
  let content = read-input
  let id = $id | or-else {|| .cat | where topic == "message" | last | get id}
  let frame = $content | .append message --meta { role: "user" continues: $id }
  id-to-messages $frame.id | tee {print $in} | call --streamer {|| print -n $in} | .append message --meta { role: "assistant" continues: $frame.id }
  return
}

export def --env system [] {
  let content = read-input
  let frame = .cat | where {|frame| ($frame.topic == "messages") and (($frame | get meta.role?) == "system")} | input list --fuzzy -d meta.description
  $content | resume --id $frame.id
}

export def prep [...names: string] {
  $names | each {|name| $"($name):\n\n``````\n(open $name | str trim)\n``````\n"} | str join "\n"
}

def --env select-provider [] {
  print "Select a provider:"
  let choice = $env.GPT2099_PROVIDERS | columns | input list
  print $"Selected provider: ($choice)"
  $env.GPT2099_PROVIDER = $env.GPT2099_PROVIDERS | get $choice
}

export def --env ensure-provider [] {
    if not ("GPT2099_PROVIDER" in $env) { select-provider }
}
