#!/usr/bin/env bash

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
allowed_target_environment=( "dev" "stg" "qa" "prod" )

AUTO_APPROVE=0

usage() {
  cat << EOF # remove the space between << and EOF, this is due to web plugin issue
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] [-a] -e environment

This script will prepare terraform initialization for a specific target.
It will check again

Available options:

-h, --help          Print this help and exit
-v, --verbose       Print script debug info
-a, --auto-approve  Auto approve TF apply
-e, --env           Target environment
EOF
  exit
}

cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
  # rm -rf .terraform ./provider.tf
  # rm -rf tf-*.json tf-*.plan
}

setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
  else
    NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
  fi
}

msg() {
  echo >&2 -e "${1-}"
}

die() {
  local msg=$1
  local code=${2-1} # default exit status 1
  msg "$msg"
  exit "$code"
}

parse_params() {
  # default values of variables set from params
  flag=0
  param=''

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) set -x ;;
    --no-color) NO_COLOR=1 ;;
    -a | --auto-approve) AUTO_APPROVE=1 ;;
    -e | --env)
      env="${2-}"
      shift
      ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  args=("$@")

  # check required params and arguments
  [[ -z "${env-}" ]] && die "Missing required target environnet (-e/--env)"
  [[ ! " ${allowed_target_environment[@]} " =~ " ${env} " ]] && die "You selected an invalid target environment, please check it's one of the following: ${allowed_target_environment[*]}"

  return 0
}

parse_params "$@"
setup_colors
####################################################################################
export LOCK_ID=""

# Cleanup before starting
# rm -rf .terraform tf-*.json tf-*.plan ./provider.tf
# debugging purposes
# export TF_LOG=TRACE
echo "folder: "
pwd
# Init
terraform init -backend-config=tf_backend/${env}-env.hcl -reconfigure && [ -n "${LOCK_ID}" ] && echo "Lock found . Removing ..." && terraform force-unlock -force ${LOCK_ID} && echo "continue to plan.." || echo "No LOCK_ID found ..."
# TERRAFORM linters
echo "$> terraform fmt recursively"
terraform fmt --recursive

echo "$> terraform resource graph"
terraform graph > tf_graph.${env}.res
# command -v dot
# if ! command -v dot &> /dev/null
#   cat tf_graph.res | dot -Tpng > tf_graph.png
# then
#   echo "'dot' command could not be found. install graphviz"
# fi

# PLAN
echo "generate terraform plan => terraform plan --var-file=env/${env}/base.tfvars -out tf-${env}.plan"
terraform plan --var-file=env/${env}/base.tfvars -out tf-${env}.plan

echo "print json plan => terraform show -json tf-${env}.plan > tf-${env}.json"
terraform show -json tf-${env}.plan > tf-${env}.json

echo "$> terraform validate"
terraform validate

# Apply
if [[ $AUTO_APPROVE -eq 1 ]]; then
    echo "Apply plan => terraform apply -auto-approve tf-${env}.plan "
    terraform apply -auto-approve tf-${env}.plan
fi