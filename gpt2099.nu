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

def conditional-pipe [
  condition: bool
  action: closure
] {
  if $condition {do $action} else {$in}
}

export-env {
  # Coerce the provider to a record if it's a string.
  $env.GPT2099_PROVIDER = match ($env.GPT2099_PROVIDER? | describe -d | get type) {
    "string" => ($env.GPT2099_PROVIDER | from json)
    _ => ($env.GPT2099_PROVIDER?)
  }

  $env.GPT2099_PROVIDERS = {
    openai: {
      models: {||
        (
          http get https://api.openai.com/v1/models
          -H { Authorization: $"Bearer ($env.OPENAI_API_KEY)" }
          | get data
          | select id created
          | update created {$in * 1_000_000_000 | into datetime}
          | sort-by -r created
        )
      }

      # todo: help fix tree-sitter:
      # ]: list<record<role: string content: string>> -> string {
      call: {|model: string|
        let data = {
          model: $model
          stream: true
          messages: $in
        }

        (
          http post
          --content-type application/json
          -H { Authorization: $"Bearer ($env.OPENAI_API_KEY)" }
          https://api.openai.com/v1/chat/completions
          $data
          | lines
          | each {|line|
            if $line == "data: [DONE]" { return }
            if ($line | is-empty) { return }
            $line | str substring 6.. | from json | get choices.0.delta | if ($in | is-not-empty) {$in.content}
          }
        )
      }
    }

    anthropic : {
      models: {||
        (
          http get
          -H {
            "x-api-key": $env.ANTHROPIC_API_KEY
            "anthropic-version": "2023-06-01"
          }
          https://api.anthropic.com/v1/models
          | get data
          | select id created_at
          | rename -c { created_at: "created" }
          | update created {into datetime}
          | sort-by -r created
        )
      }

      call: {|model: string|
        let data = {
          model: $model
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
          | lines
          | each {|line| $line | split row -n 2 "data: " | get 1?}
          | each {|x| $x | from json}
          | where type == "content_block_delta"
          | each {|x| $x | get delta.text}
        )
      }
    }

    cerebras : {
      models: {||
        (
          http get https://api.cerebras.ai/v1/models
          -H { Authorization: $"Bearer ($env.CEREBRAS_API_KEY)" }
          | get data
          | select id created
          | update created {$in * 1_000_000_000 | into datetime}
          | sort-by -r created
        )
      }

      call: {|model: string|
        let data = {
          model: $model
          stream: true
          messages: $in
        }

        (
          http post
          --content-type application/json
          -H { Authorization: $"Bearer ($env.CEREBRAS_API_KEY)" }
          https://api.cerebras.ai/v1/chat/completions
          $data
          | lines | each {|line| $line | split row -n 2 "data: " | get 1?} | | each {|x| $x | from json | get choices.0.delta.content?}
        )
      }
    }
  }
}

export def id-to-messages [id: string] {
  let frame = .get $id
  let role = $frame | get meta | if ($in | is-not-empty) {$in} else {{}} | default "user" role | get role
  let content = (.cas $frame.hash)
  let message = {
    role: $role
    content: $content
  }

  let next_id = $frame | get meta?.continues?

  match ($next_id | describe -d | get type) {
    "string" => (id-to-messages $next_id | append $message)
    "list" => ($next_id | each {|id| id-to-messages $id} | flatten | append $message)
    "nothing" => [$message]
    _ => ( error make { msg: "TBD" })
  }
}

def id-to-message [id: string] {
  let frame = .get $id
  let role = $frame | get meta | if ($in | is-not-empty) {$in} else {{}} | default "user" role | get role
  return {
    role: $role
    content: (.cas $frame.hash)
  }
}

export def call [ --streamer: closure] {
  let content = $in

  let config = $env.GPT2099_PROVIDER
  let caller = $env.GPT2099_PROVIDERS | get $config.name | get call

  (
    $content
    | do $caller $config.model
    | conditional-pipe ($streamer | is-not-empty) {|| tee {each {do $streamer}}}
    | str join
  )
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


export def is-interactive [] {
  (is-terminal --stdin) and ($env.GPT2099_INTERACTIVE? | default true)
}

export def --env run-thread [id: string] {
  let messages = id-to-messages $id

  mut streamer = {|| return }
  # Only enable interactivity if we're attached to a terminal.
  if (is-interactive) {
    ensure-provider
    $streamer = {|| print -n $in}
    print "Context:"
    print $messages
  }

  let res = $messages | call --streamer $streamer
  $res | .append message --meta {
    provider: $env.GPT2099_PROVIDER
    role: "assistant"
    continues: $id
  }
  return
}

export def --env new [] {
  let content = read-input
  let frame = $content | .append message --meta { role: "user" }
  run-thread $frame.id
  return
}

export def --env resume [ --id: string] {
  let content = read-input
  let id = $id | or-else {|| .cat | where topic == "message" | last | get id}
  let frame = $content | .append message --meta { role: "user" continues: $id }
  run-thread $frame.id
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

export def --env ensure-api-key [name: string] {
  let key_name = $"($name | str upcase)_API_KEY"
  if not ($key_name in $env) {
    let key = input -s $"\nRequired API key: $env.($key_name) = \"...\"\n\nIf you like, I can set it for you. Paste key: "
    set-env $key_name $key
    print "key set 👍\n"
  }
}

export def --env select-provider [] {
  print "Select a provider:"
  let name = $env.GPT2099_PROVIDERS | columns | input list
  print $"Selected provider: ($name)"

  let provider = $env.GPT2099_PROVIDERS | get $name
  ensure-api-key $name

  print -n "Select model:"
  let model = do $provider.models | get id | input list --fuzzy
  print $"Selected model: ($model)"
  $env.GPT2099_PROVIDER = { name: $name model: $model }
}

export def --env ensure-provider [] {
  if not ("GPT2099_PROVIDER" in $env) {select-provider}
  ensure-api-key $env.GPT2099_PROVIDER.name
}
