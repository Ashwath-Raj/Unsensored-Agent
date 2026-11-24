# Control Room implementation

Host-only Python standard-library HTTP server and static UI. Run `./control-plane/install.sh` from the existing VM project root to install its systemd user service. The Python process reads the existing VM QEMU PID/disk paths plus guest task API and Ollama status. It never submits LLM prompts. Hourly pulse entries are deterministic snapshots written to `~/.local/state/unsensored-agent-control/hourly-pulse.jsonl`.

See the bundle root `README.md` for installation, lifecycle, ports, and safety notes.
