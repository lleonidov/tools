#!/bin/bash
set -e

python3 -m venv .venv
touch init/requirements.txt
.venv/bin/python -m pip install -r init/requirements.txt