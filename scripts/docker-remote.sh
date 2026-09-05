#!/usr/bin/env bash
exec ssh -p 8022 127.0.0.1 "$(printf '%q ' sudo "${0##*/}" "$@")"
