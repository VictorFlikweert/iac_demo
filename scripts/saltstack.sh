#!/usr/bin/env bash
set -euo pipefail

CMD="$(basename "$0")"
COMPOSE=(docker compose)
SALT_SERVICES=(salt-master salt-minion-qg-1 salt-minion-qg-2)
DEFAULT_SCHEDULE_STATE="site"
DEFAULT_SCHEDULE_MINUTES=1
SCHEDULE_JOB_PREFIX="enforce"

saltctl() {
  "${COMPOSE[@]}" exec salt-master salt "$@"
}

schedule_job_name() {
  local state="$1"
  local sanitized="${state//[^A-Za-z0-9_-]/_}"
  printf '%s_%s' "$SCHEDULE_JOB_PREFIX" "${sanitized:-state}"
}

usage() {
  cat <<EOF
Usage: $CMD <command> [args...]

Commands:
  start          Start the Salt master and worker minion containers
  stop           Stop the Salt containers
  status         Show the Salt containers status
  state [TARGET] [ARGS]
                 Run salt <target> state.apply (default target: '*')
  shell [CMD]    Open a shell (default: bash) in the salt-master container
  apply-logs [SERVICES...]
                 Tail docker logs for the Salt containers (default: all Salt nodes)
  schedule-enable [TARGET] [MINUTES] [STATE]
                 Add/refresh a periodic state.apply job (defaults: '*', 1 minute, demo)
  schedule-disable [TARGET] [STATE]
                 Remove the helper schedule job (defaults: '*', demo)
  schedule-status [TARGET]
                 Show the current schedule configuration (default target: '*')
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

command="$1"
shift

case "$command" in
  start)
    "${COMPOSE[@]}" up -d "${SALT_SERVICES[@]}"
    ;;
  stop)
    "${COMPOSE[@]}" stop "${SALT_SERVICES[@]}"
    ;;
  status)
    "${COMPOSE[@]}" ps "${SALT_SERVICES[@]}"
    ;;
  state)
    target="*"
    if [[ $# -gt 0 && "$1" != -* ]]; then
      target="$1"
      shift
    fi
    "${COMPOSE[@]}" exec salt-master salt "$target" state.apply "$@"
    ;;
  shell)
    if [[ $# -eq 0 ]]; then
      "${COMPOSE[@]}" exec -it salt-master bash
    else
      "${COMPOSE[@]}" exec -it salt-master "$@"
    fi
    ;;
  apply-logs)
    if [[ $# -gt 0 ]]; then
      services=("$@")
    else
      services=("${SALT_SERVICES[@]}")
    fi
    "${COMPOSE[@]}" logs -f "${services[@]}"
    ;;
  schedule-enable)
    target='*'
    if [[ $# -gt 0 ]]; then
      target="$1"
      shift
    fi
    minutes="$DEFAULT_SCHEDULE_MINUTES"
    if [[ $# -gt 0 ]]; then
      minutes="$1"
      shift
    fi
    state="$DEFAULT_SCHEDULE_STATE"
    if [[ $# -gt 0 ]]; then
      state="$1"
      shift
    fi
    job_name="$(schedule_job_name "$state")"
    job_kwargs=$(printf '{"mods": "%s"}' "$state")
    saltctl "$target" schedule.add "$job_name" \
      function=state.apply \
      job_kwargs="$job_kwargs" \
      minutes="$minutes" \
      run_on_start=True \
      maxrunning=1
    ;;
  schedule-disable)
    target='*'
    if [[ $# -gt 0 ]]; then
      target="$1"
      shift
    fi
    state="$DEFAULT_SCHEDULE_STATE"
    if [[ $# -gt 0 ]]; then
      state="$1"
      shift
    fi
    job_name="$(schedule_job_name "$state")"
    saltctl "$target" schedule.delete "$job_name"
    ;;
  schedule-status)
    target='*'
    if [[ $# -gt 0 ]]; then
      target="$1"
      shift
    fi
    saltctl "$target" schedule.list
    ;;
  *)
    usage
    exit 1
    ;;
esac
