# SSH Monitor

A compact, dependency-free macOS system monitor designed for use locally or over SSH. It refreshes every **5 seconds** in the same terminal window.

It displays CPU usage, RAM, the macOS memory-availability indicator, swap usage, disk space, local IP address, thermal warnings, and the three processes using the most resident memory.

**Requirements:** macOS, `zsh`, and a terminal. No Homebrew packages or `sudo` privileges are needed.

## 1. Connect over SSH (optional)

If you're configuring another Mac, first enable **System Settings → General → Sharing → Remote Login** on that device. Then connect from your computer:

```bash
ssh your-user@device.ip.address
```

Replace `your-user` with the remote macOS account username and `device.ip.address` with its IP address. The rest of the installation commands run **on the Mac you want to monitor**.

## 2. Install the monitor script

Copy and paste the entire block into the remote Mac's terminal:

```bash
cat > ~/macmon.sh <<'EOF'
#!/bin/zsh

chip=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
[[ -z "$chip" ]] && chip=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F ': ' '/Chip:/ {print $2; exit}')

cpu=$(top -l 1 -n 0 | awk '/CPU usage/ {printf "%.1f%%", 100 - $(NF-1)}')
mem=$(top -l 1 -n 0 | grep 'PhysMem')
ram_used=$(printf '%s\n' "$mem" | sed -nE 's/.*PhysMem: ([0-9.]+[GM]).*/\1/p')
ram_free=$(printf '%s\n' "$mem" | sed -nE 's/.* ([0-9.]+[GM]) unused.*/\1/p')
ram_total=$(sysctl -n hw.memsize | awk '{printf "%.0f", $1/1073741824}')
pressure=$(memory_pressure | awk -F ': ' '/System-wide memory free percentage/ {print $2; exit}')
swap=$(sysctl vm.swapusage | sed -nE 's/.*used = ([0-9.]+[A-Za-z]+).*/\1/p')
disk=$(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')
iface=$(route -n get default 2>/dev/null | awk '/interface:/ {print $2; exit}')
ip=$([[ -n "$iface" ]] && ipconfig getifaddr "$iface" 2>/dev/null)

printf 'MAC MONITOR · %s\n' "${chip:-Unknown chip}"
printf '%s · 5s refresh\n' "$(date '+%Y-%m-%d %H:%M:%S')"
echo '────────────────────────────────'
printf 'CPU        %s\n' "${cpu:-N/A}"
printf 'RAM        %s / %s GiB\n' "${ram_used:-N/A}" "${ram_total:-N/A}"
printf 'UNUSED     %s\n' "${ram_free:-N/A}"
printf 'MEM AVAIL  %s (indicator)\n' "${pressure:-N/A}"
printf 'SWAP       %s\n' "${swap:-N/A}"
printf 'DISK       %s\n' "${disk:-N/A}"
printf 'NETWORK    %s\n' "${ip:-N/A}"

therm=$(pmset -g therm 2>/dev/null)
if [[ -z "$therm" ]]; then
  echo 'THERMAL    N/A'
elif print -r -- "$therm" | grep -qiE 'warning level: [1-9]|thermal pressure: (heavy|critical)'; then
  echo 'THERMAL    Check warnings'
else
  echo 'THERMAL    No alerts detected*'
fi

echo '────────────────────────────────'
echo 'TOP RAM PROCESSES'
ps -axo rss=,comm= | sort -k1,1nr | head -3 | awk '{
  name=$2
  sub(/^.*\//,"",name)
  printf "%-15.15s %6.0f MiB\n",name,$1/1024
}'
echo '────────────────────────────────'
echo 'Ctrl+C to exit'
EOF

chmod +x ~/macmon.sh
```

Test it once:

```bash
~/macmon.sh
```

## 3. Set up the `monitor` command

Add this alias to the **remote Mac's** `~/.zshrc` (run only once):

```bash
echo "alias monitor='while true; do printf \"\\033[H\\033[J\"; ~/macmon.sh; sleep 5; done'" >> ~/.zshrc
```

Reload the configuration:

```bash
source ~/.zshrc
```

Start monitoring:

```bash
monitor
```

The display refreshes in place every **5 seconds**. Press **Ctrl+C** to stop it. Some terminals may briefly flicker when the screen redraws.

## 4. Run it remotely

Connect and run the alias interactively:

```bash
ssh your-user@device.ip.address
monitor
```

Or start the monitor in one command from your own computer:

```bash
ssh -t your-user@device.ip.address 'zsh -ic monitor'
```

SSH must be enabled on the remote Mac. The `-t` flag allocates a terminal for the live display.

## 5. Example output

Illustrative values only:

```text
MAC MONITOR · Apple M5 Pro
2026-10-07 18:54:27 · 5s refresh
────────────────────────────────
CPU        21.3%
RAM        19G / 24 GiB
UNUSED     4045M
MEM AVAIL  84% (indicator)
SWAP       0.00M
DISK       13Gi / 460Gi (5%)
NETWORK    192.168.1.25
THERMAL    No alerts detected*
────────────────────────────────
TOP RAM PROCESSES
Python             654 MiB
mediaanalysisd     308 MiB
Siri               178 MiB
────────────────────────────────
Ctrl+C to exit
```

**Reading the metrics:**

- **RAM / UNUSED:** the physical-memory summary reported by `top`. The used figure includes memory macOS may be able to reclaim.
- **MEM AVAIL:** macOS's `memory_pressure` indicator. **84% does not mean 84% of physical RAM is unused.**
- **SWAP:** disk-backed swap currently in use.
- **THERMAL:** a basic warning check, **not** a CPU temperature reading in °C. `*` means no alerts were detected by the script's check; it does not guarantee ideal temperatures.
- **TOP RAM PROCESSES:** resident memory (RSS), which does not necessarily include every allocation associated with GPU/Metal workloads.

## 6. Troubleshooting

Check script syntax:

```bash
zsh -n ~/macmon.sh
```

Check the alias:

```bash
alias monitor
```

If `monitor` is not found, reload `~/.zshrc` with `source ~/.zshrc` or open a new interactive `zsh` session.

For detailed thermal status, run:

```bash
pmset -g therm
```

The monitor does **not** provide GPU utilization, exact hardware temperatures, or LLM tokens-per-second metrics.

## 7. Uninstall

Remove the script:

```bash
rm ~/macmon.sh
```

Open your shell configuration:

```bash
nano ~/.zshrc
```

Delete the line beginning with `alias monitor=`, save the file, and reload your shell:

```bash
source ~/.zshrc
```
