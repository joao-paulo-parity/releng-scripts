#!/usr/bin/env bash

set -Eeu -o pipefail
shopt -s inherit_errexit

this_file="${BASH_SOURCE[0]}"
subcmds_dir="${this_file%/*}"
cmd_dir="${subcmds_dir%/*}"
project_root="${cmd_dir%/*}"
this_filename="${this_file:$(( ${#subcmds_dir} + 1 ))}"
this_subcommand="${this_filename%.*}"
run="${subcmds_dir:$(( ${#cmd_dir} + 1 ))} $this_subcommand"

# shellcheck source=../../lib.sh
. "$project_root/lib.sh"

# shellcheck source=./lib.sh
. "$subcmds_dir/lib.sh"

# Functions for deleting files from the target backends.
# Those functions receive arguments in a predefined order.

delete_from_s3() {
  local bucket="$1"
  local bucket_key="$2"

  local destination="s3://$bucket/$bucket_key"
  local cmd=(
    aws s3 rm
    "${general_backend_options[@]}"
    "${backend_upload_options[@]}"
    "$destination"
  )

  if [ "${DRY_RUN:-}" ]; then
    log "${cmd[*]}"
    return 0
  fi

  "${cmd[@]}"
}

# Usage guidance

print_help() {
  echo "
Usage: $run [OPTIONS] \\
  OPERATION [OPERATION_ARGS] \\
  BACKEND [BACKEND_ARGS] [- [BACKEND_CLI_ARGS] --] \\
  FILE...


[OPTIONS]

  * --bucket
    The bucket which the files will be uploaded to. The bucket can also be
    inferred from environment variables depending on the backend.

  * --dry
    Process the arguments but don't actually delete the files, i.e. a test run

  * --help
    Print this help


$(print_shared_options_usage "$run")


FILE...

  The file names to be deleted from the target bucket.

  In case you pass a file path rather than a file name, only the file name is
  considered from it.
"
}

# Script entrypoint

main() {
  # shellcheck disable=SC2034 # FALLBACK_TO_HELP is used in ../rs
  FALLBACK_TO_HELP="$run --help"

  get_opt consume-optional-bool help "$@"
  if [ "${__get_opt_value:-}" ]; then
    print_help
    exit
  fi

  local bucket
  get_opt consume-optional bucket "$@"
  if [ "${__get_opt_value:-}" ]; then
    bucket="$__get_opt_value"
    set -- "${__get_opt_args[@]}"
  fi

  unset DRY_RUN
  get_opt consume-optional-bool dry "$@"
  if [ "${__get_opt_value:-}" ]; then
    set -- "${__get_opt_args[@]}"
    DRY_RUN=true
  fi

  handle_operation "$@"
  set -- "${__handle_operation[@]}"

  handle_backend_options "$this_subcommand" "" "$@"
  set -- "${__handle_backend_options[@]}"

  unset FALLBACK_TO_HELP

  local exit_code

  # Delete all the input locations

  for location in "$@"; do
    local filename
    filename="$(basename "$location")"

    local remote_destination="$upload_dir/$filename"

    if [ ! "${DRY_RUN:-}" ]; then
      log "For input file: $filename"
      log "Deleting destination: $remote_destination"
    fi

    if "$delete_fn" "$bucket" "$remote_destination"; then
      log "Deletion exit code: $?"
    else
      if [ "${exit_code:-0}" -eq 0 ]; then
        exit_code=1
      else
        exit_code=$?
      fi
      log error "Deletion command failed for file: $filename"
      log +error "Exit code: $exit_code"
    fi
  done

  exit "${exit_code:-0}"
}

main "$@"
