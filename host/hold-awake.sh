#!/usr/bin/env bash
set -euo pipefail
# Run in a terminal and leave it open during a long session; Ctrl-C releases the inhibitor.
exec systemd-inhibit --what=sleep:idle --mode=block --why='Long-running isolated Unsensored Agent VM task' sleep infinity
