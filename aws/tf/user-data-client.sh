#!/bin/bash

set -e

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
bash /ops/shared/scripts/client.sh "aws" "${retry_join}" "${nomad_binary}"
