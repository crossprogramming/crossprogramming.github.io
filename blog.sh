#!/bin/bash

set -e

# opens this Jekyll blog inside the system default browser
# usage from CLI:
#   sh blog.sh
jekyll serve --watch --host 0.0.0.0 --port 4000 --open-url --limit_posts 10
