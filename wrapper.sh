#!/bin/bash
source functions.sh
# Deliberately unsafe: pass everything to shell
# shellcheck disable=SC2048
$*
