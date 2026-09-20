#!/usr/bin/env bash
set -euo pipefail

# Drop build-time COPR definitions so the runtime image has no third-party repos.
rm -f /etc/yum.repos.d/{dtutila,washkinazy,mineiro,agaspar,whelanh}-*.repo
