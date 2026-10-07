# oMLX Local AI Server

Turn an Apple Silicon Mac into a private, OpenAI-compatible local inference server using **oMLX**, **MLX models**, optional **Lightning MTP acceleration**, and **SSH tunneling**.

This repository is intended as a reproducible setup guide for developers who want to:

- run capable LLMs locally on Apple Silicon;
- expose them through an OpenAI-compatible API;
- keep the inference server bound to `localhost`;
- access the server securely from another Mac or workstation over SSH;
- benchmark real prompt/decode performance;
- tune memory usage on constrained unified-memory systems;
- automate start/stop/status/test workflows with a `Makefile`.

> Tested profile: **Mac mini M5 Pro, 24 GB unified memory, macOS 27.0, oMLX 0.7.0, Qwen3.8-27B-oQ4e-mtp**.

---

## Table of contents

- [What this builds](#what-this-builds)
- [Tested hardware and software](#tested-hardware-and-software)
- [Observed performance](#observed-performance)
- [Requirements](#requirements)
- [1. Install oMLX](#1-install-omlx)
- [2. Verify oMLX](#2-verify-omlx)
- [3. Start the server manually](#3-start-the-server-manually)
- [4. Install the Hugging Face CLI](#4-install-the-hugging-face-cli)
- [5. Download a model](#5-download-a-model)
- [6. Verify model discovery](#6-verify-model-discovery)
- [7. Configure the oMLX API key](#7-configure-the-omlx-api-key)
- [8. Store the API key safely in your shell](#8-store-the-api-key-safely-in-your-shell)
- [9. Test the OpenAI-compatible API](#9-test-the-openai-compatible-api)
- [10. Access the Mac remotely through SSH](#10-access-the-mac-remotely-through-ssh)
- [11. Configure Lightning MTP](#11-configure-lightning-mtp)
- [12. Memory tuning](#12-memory-tuning)
- [13. Benchmarking](#13-benchmarking)
- [14. Run oMLX as a background service](#14-run-omlx-as-a-background-service)
- [15. Makefile automation](#15-makefile-automation)
- [16. Use it from Python](#16-use-it-from-python)
- [17. Troubleshooting](#17-troubleshooting)
- [18. Security notes](#18-security-notes)
- [19. Useful paths](#19-useful-paths)
- [20. Known-good M5 Pro 24 GB profile](#20-known-good-m5-pro-24-gb-profile)

---

## What this builds

```text
┌──────────────────────────┐
│ Client Mac / workstation │
│                          │
│ localhost:18000          │
└────────────┬─────────────┘
             │
             │ SSH tunnel
             │
             ▼
┌──────────────────────────┐
│ Apple Silicon Mac        │
│                          │
│ oMLX                     │
│ 127.0.0.1:8000           │
│        │                 │
│        ▼                 │
│ Qwen / MLX model         │
│ GPU + Unified Memory     │
└──────────────────────────┘
```

The inference machine remains reachable only through its own localhost interface. The client connects through an encrypted SSH tunnel.

This gives local applications an endpoint such as:

```text
http://localhost:18000/v1
```

while the model actually runs on the remote Mac.

---

## Tested hardware and software

The reference setup used while writing this guide:

```text
Machine:        Mac mini
SoC:            Apple M5 Pro
Architecture:   arm64
Unified memory: 24 GiB
macOS:          27.0
oMLX:           0.7.0
Model:          Jundot/Qwen3.8-27B-oQ4e-mtp
Model size:     ~16 GiB on disk
Quantization:   oQ4e / 4-bit class
Lightning MTP:  enabled
MTP depth:      adaptive max depth 3
```

Check your own machine:

```bash
sw_vers
uname -m
sysctl -n hw.memsize
```

Convert memory bytes to GiB if needed:

```bash
python3 - <<'PY'
import subprocess
b = int(subprocess.check_output(["sysctl", "-n", "hw.memsize"]))
print(f"{b / 1024**3:.0f} GiB")
PY
```

---

## Observed performance

These numbers are **measurements from one M5 Pro 24 GB machine**, not guarantees for other Macs.

### Baseline without Lightning MTP

Long code-generation request:

```text
generation: ~16.9 tok/s
TTFT:       ~0.53 s
```

### Lightning MTP enabled, adaptive depth 3

Warm run:

```text
generation: 26.09 tok/s
TTFT:       0.27 s
total:      38.60 s for a 1000-token completion
```

Second long prompt:

```text
generation: 27.07 tok/s
TTFT:       0.83 s
total:      45.16 s for a 1200-token completion
```

The tested machine therefore sustained roughly:

```text
26–27 output tokens/second
```

with Lightning MTP enabled.

The baseline and MTP tests used the same model. Actual performance depends on model, quantization, prompt length, cache state, context size, thermals, OS version, oMLX version, and memory pressure.

---

# Requirements

You need:

- Apple Silicon Mac;
- a supported recent macOS version;
- Homebrew;
- SSH enabled if you want remote access;
- enough disk space for your model;
- enough unified memory for the chosen quantization.

Check Homebrew:

```bash
brew --version
```

Check free disk space:

```bash
df -h ~
```

---

# 1. Install oMLX

Add the official oMLX Homebrew tap:

```bash
brew tap jundot/omlx https://github.com/jundot/omlx
```

Install oMLX:

```bash
brew install jundot/omlx/omlx
```

The Homebrew formula may install development/runtime dependencies such as Python, Rust and LLVM. This can consume several gigabytes.

Verify:

```bash
omlx --version
which omlx
```

Example tested output:

```text
0.7.0
/opt/homebrew/bin/omlx
```

Check service state:

```bash
brew services info omlx
```

For the initial setup, it is easier to leave the background service stopped and run the server manually.

---

# 2. Verify oMLX

Create the default model directory:

```bash
mkdir -p ~/.omlx/models
```

Start oMLX in the foreground:

```bash
omlx serve
```

Leave that terminal open.

In another terminal on the inference Mac:

```bash
curl -s http://localhost:8000/v1/models
```

Before installing models, a healthy server should return something similar to:

```json
{
  "object": "list",
  "data": []
}
```

Stop the foreground server with:

```text
Ctrl+C
```

---

# 3. Start the server manually

The simplest development workflow is:

```bash
omlx serve
```

The default API endpoint is:

```text
http://localhost:8000/v1
```

The admin UI is:

```text
http://localhost:8000/admin
```

Running in the foreground is useful during initial setup because logs and errors are immediately visible.

---

# 4. Install the Hugging Face CLI

Install the current Hugging Face CLI through Homebrew:

```bash
brew install hf
```

Verify:

```bash
hf version
```

Authentication is not required for public models, although anonymous downloads can have lower rate limits.

Optional login:

```bash
hf auth login
```

Never commit Hugging Face access tokens.

---

# 5. Download a model

This guide used:

```text
Jundot/Qwen3.8-27B-oQ4e-mtp
```

Download it into the directory watched by oMLX:

```bash
hf download Jundot/Qwen3.8-27B-oQ4e-mtp \
  --local-dir ~/.omlx/models/Qwen3.8-27B-oQ4e-mtp
```

The tested download reconstructed approximately 17 GB of model data and occupied about 16 GiB on disk.

Verify:

```bash
du -sh ~/.omlx/models/Qwen3.8-27B-oQ4e-mtp
```

Inspect the files:

```bash
ls -lh ~/.omlx/models/Qwen3.8-27B-oQ4e-mtp
```

A complete sharded model should contain files such as:

```text
config.json
tokenizer.json
chat_template.jinja
model.safetensors.index.json
model-00001-of-00004.safetensors
model-00002-of-00004.safetensors
model-00003-of-00004.safetensors
model-00004-of-00004.safetensors
```

Do not interrupt Hugging Face while it is still reconstructing model files.

---

# 6. Verify model discovery

Start oMLX again:

```bash
omlx serve
```

Then:

```bash
curl -s http://localhost:8000/v1/models
```

Before configuring API authentication, the tested setup returned:

```json
{
  "object": "list",
  "data": [
    {
      "id": "Qwen3.8-27B-oQ4e-mtp",
      "object": "model",
      "owned_by": "omlx",
      "max_model_len": 262144
    }
  ]
}
```

`max_model_len` is the model's advertised maximum. It is **not** a recommendation to use that entire context window on a memory-constrained Mac.

On 24 GB machines, start with a much smaller practical context.

---

# 7. Configure the oMLX API key

The admin dashboard may ask you to create an API key on first use.

Generate a strong local key:

```bash
openssl rand -hex 32
```

This generates 32 random bytes represented as 64 hexadecimal characters.

Example format:

```text
f4c2...64-hex-characters...91ab
```

Do **not** reuse the example above.

Do **not** paste your real key into issues, screenshots, chat messages, Git commits, shell scripts, or public repositories.

Open the dashboard:

```text
http://localhost:8000/admin
```

If the inference Mac is remote, use the SSH tunnel described later in this guide.

On the first-access screen:

1. paste the generated key into **API Key**;
2. paste it again into **Confirm API Key**;
3. click **Set API Key**.

After authentication is enabled, API calls should send:

```http
Authorization: Bearer YOUR_API_KEY
```

---

# 8. Store the API key safely in your shell

For a temporary shell session on macOS/zsh:

```bash
read -s "OMLX_API_KEY?oMLX API key: "
echo
export OMLX_API_KEY
```

The key is not echoed to the terminal while you type it.

Confirm only that the variable exists:

```bash
test -n "$OMLX_API_KEY" && echo "OMLX_API_KEY is set"
```

Do not print the key itself.

To remove it from the current shell:

```bash
unset OMLX_API_KEY
```

---

# 9. Test the OpenAI-compatible API

## List models

```bash
curl -s http://localhost:8000/v1/models \
  -H "Authorization: Bearer $OMLX_API_KEY" \
  | python3 -m json.tool
```

## Chat completion

```bash
curl -s http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer $OMLX_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3.8-27B-oQ4e-mtp",
    "messages": [
      {
        "role": "user",
        "content": "Write a concise Python function that returns the nth Fibonacci number iteratively."
      }
    ],
    "temperature": 0.2,
    "max_tokens": 200
  }' \
  | python3 -m json.tool
```

## Streaming

```bash
curl -N http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer $OMLX_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3.8-27B-oQ4e-mtp",
    "messages": [
      {
        "role": "user",
        "content": "Explain dependency injection in FastAPI."
      }
    ],
    "stream": true,
    "max_tokens": 500
  }'
```

---

# 10. Access the Mac remotely through SSH

A good security model is:

```text
oMLX -> localhost only
remote access -> SSH tunnel
```

Avoid exposing the oMLX port directly to the Internet.

## Tunnel using the same local port

On the **client machine**, not inside the remote SSH shell:

```bash
ssh -N -L 8000:localhost:8000 user@MAC_IP
```

Then the remote oMLX server appears locally at:

```text
http://localhost:8000
```

## Recommended tunnel using a different local port

Using `18000` locally avoids conflicts if port 8000 is already occupied:

```bash
ssh -N -L 18000:localhost:8000 user@MAC_IP
```

Then use:

```text
API:   http://localhost:18000/v1
Admin: http://localhost:18000/admin
```

The architecture is:

```text
Client
localhost:18000
      │
      │ encrypted SSH tunnel
      ▼
Inference Mac
localhost:8000
      │
      ▼
oMLX
```

Keep the SSH process running while you use the tunnel.

---

# 11. Configure Lightning MTP

The tested Qwen model includes support for Lightning MTP.

Open:

```text
http://localhost:8000/admin
```

If remote:

```text
http://localhost:18000/admin
```

Select:

```text
Qwen3.8-27B-oQ4e-mtp
```

Open the model settings and enable:

```text
Lightning MTP: ON
Adaptive max depth: 3
```

For the tested 24 GB machine, **depth 3** was a good balance between performance and memory usage.

Do not assume that higher depth is automatically better. Benchmark each setting on your own hardware.

Changing MTP settings can cause the model/runtime to reload. Ignore the first run as a warm-up when comparing steady-state performance.

---

# 12. Memory tuning

Large models can fit in unified memory while still leaving too little headroom for macOS.

Useful commands:

```bash
top -l 1 | grep -E "PhysMem|VM:"
```

```bash
memory_pressure
```

```bash
vm_stat
```

```bash
sysctl vm.swapusage
```

Inspect the oMLX process:

```bash
ps -axo pid,rss,vsz,command | grep '[o]mlx'
```

### Important Apple Silicon note

The process RSS is **not** the whole story.

MLX/Metal allocations can appear as large amounts of system-wide wired/unified memory, so:

```text
ps RSS
```

may look much smaller than the actual memory footprint of the loaded model.

Use `memory_pressure`, swap usage, and overall system behavior together.

---

## Memory guard

oMLX includes a prefill memory guard.

Available tiers include:

```text
safe
balanced
aggressive
custom
```

The tested 24 GB machine initially aborted a Qwen3.8-27B request under a conservative memory guard because the process crossed the dynamic prefill watermark.

Switching to the **aggressive** tier allowed the model to run successfully.

This does **not** mean aggressive is universally appropriate.

Use it only after checking:

```bash
memory_pressure
sysctl vm.swapusage
```

and avoid disabling memory protection entirely unless you understand the consequences.

On a 24 GB system, an OOM condition can make the entire desktop unresponsive.

---

# 13. Benchmarking

Do not benchmark only one tiny response.

Measure at least:

- model load time;
- time to first token (TTFT);
- prompt processing speed;
- generation/decode speed;
- total request time;
- memory pressure;
- swap usage;
- cold vs warm requests.

oMLX responses expose useful metrics in `usage`, for example:

```json
{
  "time_to_first_token": 0.27,
  "generation_tokens_per_second": 26.09,
  "total_time": 38.60
}
```

## Repeatable long-generation benchmark

```bash
curl -s http://localhost:8000/v1/chat/completions \
  -H "Authorization: Bearer $OMLX_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen3.8-27B-oQ4e-mtp",
    "messages": [
      {
        "role": "user",
        "content": "Create a production-style FastAPI endpoint for creating users. Use Pydantic validation, proper HTTP status codes, dependency injection, error handling, and explain the important design decisions. Keep the code self-contained."
      }
    ],
    "temperature": 0.2,
    "max_tokens": 1000
  }' \
  | python3 -m json.tool
```

Run it at least twice:

```text
Run 1 -> cold/reconfigured runtime
Run 2 -> warm runtime
```

Use the warm run for steady-state comparisons.

---

# 14. Run oMLX as a background service

After the configuration is stable:

```bash
omlx start
```

Stop:

```bash
omlx stop
```

Restart:

```bash
omlx restart
```

Status:

```bash
brew services info omlx
```

Equivalent Homebrew commands:

```bash
brew services start omlx
brew services stop omlx
brew services restart omlx
brew services info omlx
```

oMLX's Homebrew service uses its persisted settings.

---

# 15. Makefile automation

A reusable `Makefile` is included with this repository.

Typical commands:

```bash
make help
make serve
make start
make stop
make restart
make status
make models
make test
make memory
make logs
```

The Makefile expects:

```text
OMLX_API_KEY
```

for authenticated API operations.

Load it securely into the current shell:

```bash
read -s "OMLX_API_KEY?oMLX API key: "
echo
export OMLX_API_KEY
```

Then:

```bash
make models
make test
```

---

# 16. Use it from Python

Install the OpenAI Python client in your project:

```bash
python3 -m pip install openai
```

Example:

```python
import os
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8000/v1",
    api_key=os.environ["OMLX_API_KEY"],
)

response = client.chat.completions.create(
    model="Qwen3.8-27B-oQ4e-mtp",
    messages=[
        {
            "role": "user",
            "content": "Explain hexagonal architecture in Python.",
        }
    ],
)

print(response.choices[0].message.content)
```

When using an SSH tunnel on local port `18000`:

```python
base_url="http://localhost:18000/v1"
```

Your application does not need to know that inference is running on another Mac.

---

# 17. Troubleshooting

## `hf: command not found`

Install:

```bash
brew install hf
```

Verify:

```bash
hf version
```

---

## `/v1/models` returns an empty array

Example:

```json
{"object":"list","data":[]}
```

Check that your model directory exists:

```bash
ls ~/.omlx/models
```

Check the model:

```bash
ls ~/.omlx/models/Qwen3.8-27B-oQ4e-mtp
```

Restart the server:

```bash
omlx restart
```

or restart the foreground process.

---

## API key error

Once authentication is configured, include:

```bash
-H "Authorization: Bearer $OMLX_API_KEY"
```

Verify that the variable exists:

```bash
test -n "$OMLX_API_KEY" && echo "API key loaded"
```

Do not print the secret.

---

## Memory guard abort

An error can look similar to:

```text
oMLX memory guard aborted this request mid-prefill
```

First inspect:

```bash
memory_pressure
sysctl vm.swapusage
```

Then consider, in order:

1. closing memory-heavy applications;
2. reducing context;
3. reducing concurrent requests;
4. using a smaller/lower-memory model;
5. moving the memory guard from safe/balanced to aggressive if your system has sufficient headroom.

Do not disable safeguards as the first solution.

---

## Model loads but macOS shows almost all RAM used

This can be normal with large MLX models.

Check:

```bash
memory_pressure
sysctl vm.swapusage
```

A large `PhysMem used` value alone does not prove the system is thrashing.

---

## `brew services` warns about SSH

When running Homebrew service commands from an SSH session you may see a warning about `/dev/console` ownership and the `user/*` domain.

That warning does not necessarily mean oMLX failed.

Check the actual state:

```bash
brew services info omlx
```

---

## Port 8000 is already in use

Find the process:

```bash
lsof -nP -iTCP:8000 -sTCP:LISTEN
```

For a remote tunnel, simply use another local port:

```bash
ssh -N -L 18000:localhost:8000 user@MAC_IP
```

---

# 18. Security notes

Recommended:

- bind oMLX to localhost unless LAN exposure is intentional;
- use SSH tunneling for remote access;
- configure an API key;
- generate secrets with a cryptographically secure tool such as `openssl`;
- keep secrets out of Git;
- keep `.env` ignored;
- avoid exposing port 8000 directly to the public Internet;
- use a VPN/Tailscale-style private network if you need broader remote access;
- rotate a key if it is ever exposed.

Generate a replacement key:

```bash
openssl rand -hex 32
```

Never put the real key in:

```text
README.md
Makefile
.env.example
GitHub issues
screenshots
shell scripts committed to Git
```

---

# 19. Useful paths

Default model directory:

```text
~/.omlx/models
```

Global settings:

```text
~/.omlx/settings.json
```

Server application log:

```text
~/.omlx/logs/server.log
```

Homebrew service log:

```bash
$(brew --prefix)/var/log/omlx.log
```

oMLX binary in the tested Homebrew setup:

```text
/opt/homebrew/bin/omlx
```

---

# 20. Known-good M5 Pro 24 GB profile

This is the tested configuration, not a universal recommendation.

```text
Hardware
--------
Apple M5 Pro
24 GB unified memory

Software
--------
macOS 27.0
oMLX 0.7.0

Model
-----
Jundot/Qwen3.8-27B-oQ4e-mtp
~16 GiB on disk

oMLX
----
API authentication: enabled
Memory guard: aggressive

Model settings
--------------
Lightning MTP: enabled
Adaptive max depth: 3
```

### Measured long-generation results

Without MTP:

```text
~16.9 tok/s generation
```

With Lightning MTP depth 3:

```text
26.09 tok/s warm benchmark
27.07 tok/s second long benchmark
```

Observed memory state with the model loaded and MTP active:

```text
memory_pressure free percentage: 24%
pages throttled: 0
swap used during observed session: ~183 MB
```

The system remained responsive in the tested session.

Do not treat those exact memory numbers as a requirement or guarantee. macOS memory behavior varies dynamically.

---

# Repository metadata

Suggested repository name:

```text
omlx-local-ai-server
```

Suggested GitHub description:

```text
Turn an Apple Silicon Mac into a private OpenAI-compatible local inference server with oMLX + Qwen, SSH tunneling, API auth, Lightning MTP tuning, benchmarks, and Makefile automation.
```

Suggested GitHub topics:

```text
apple-silicon
macos
mlx
omlx
qwen
qwen3
local-llm
llm-inference
inference-server
openai-api
self-hosted
ssh-tunnel
homebrew
developer-tools
ai
```

---

## References

- oMLX: https://github.com/jundot/omlx
- Hugging Face: https://huggingface.co/
- Tested model: https://huggingface.co/Jundot/Qwen3.8-27B-oQ4e-mtp

---

## Contributing

Hardware results are especially useful.

When submitting a benchmark, include:

```text
Mac model:
SoC:
GPU cores:
Unified memory:
macOS:
oMLX version:
Model:
Quantization:
Context:
MTP enabled:
MTP depth:
TTFT:
Prompt tok/s:
Generation tok/s:
Peak/observed memory:
Swap:
```

This makes results comparable instead of anecdotal.

---

## Disclaimer

Local inference performance and memory behavior can change significantly between macOS, MLX, oMLX, model, and quantization versions.

Always benchmark the exact configuration you intend to use.
