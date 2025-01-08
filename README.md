## gpt2099 [![Discord](https://img.shields.io/discord/1182364431435436042?logo=discord)](https://discord.com/invite/YNbScHBHrh)

[Nushell](https://www.nushell.sh) + [cross-stream](https://github.com/cablehead/xs) + llms

## Requirements

- [Nushell](https://www.nushell.sh)
- Install [cross-stream](https://cablehead.github.io/xs/getting-started/installation/) and get familar with the [basics](https://cablehead.github.io/xs/getting-started/first-stream/)

## Getting started

- Clone this repository
- `use gpt2099.nu *`
- start a cross-stream store in a dedicated window: `xs serve ./store`

- In the same directory, select a provider: `select-provider`

https://github.com/user-attachments/assets/dd99e920-480c-4d47-ba52-6c62217d1194

- Start a chat thread: `"hello" | new`
- Continue the thread `resume`

## Original intro

https://github.com/user-attachments/assets/4c74e5e6-c413-402b-8283-45a3a149bce5

## Threaded conversations

```mermaid
flowchart TD
    A[Message ID 1: Start] -->|continues| B[Message ID 2]
    B -->|continues| C[Message ID 3]
    C -->|continues| D[Message ID 4]

    C -->|forks| E[Message ID 5: Detail Thread 1]
    E -->|continues| F[Message ID 6: Detail Thread 1]

    B -->|forks| G[Message ID 7: Detail Thread 2]
    G -->|continues| H[Message ID 8: Detail Thread 2]
    H -->|continues| I[Message ID 9: Detail Thread 2]
```
