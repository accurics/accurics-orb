#!/bin/sh -l

REPORT_NAME=accurics_report.json

process_args() {
  while getopts "m:t:d:a:e:k:r:u:v:f:" opt; do
    case $opt in
      m) INPUT_DEBUG_MODE="$OPTARG"
      ;;
      t) INPUT_TERRAFORM_VERSION="$OPTARG"
      ;;
      d) INPUT_DIRECTORIES="$OPTARG"
      ;;
      a) INPUT_PLAN_ARGS="$OPTARG"
      ;;
      e) INPUT_ENV_ID="$OPTARG"
      ;;
      k) INPUT_APP_ID="$OPTARG"
      ;;
      r) INPUT_REPO_NAME="$OPTARG"
      ;;
      u) INPUT_URL="$OPTARG"
      ;;
      v) INPUT_FAIL_ON_VIOLATIONS="$OPTARG"
      ;;
      f) INPUT_FAIL_ON_ALL_ERRORS="$OPTARG"
      ;;
      ?) exit 4
      ;;
    esac
  done

  # If all config parameters are specified, use the config params passed in instead of the config file checked into the repository
  [ "$INPUT_ENV_ID" = "" ]    && echo "Error: The env-id parameter is required and not set." && exit 1
  [ "$INPUT_APP_ID" = "" ]    && echo "Error: The app-id parameter is required and not set." && exit 2
  [ "$INPUT_URL" = "" ]       && echo "Error: The url parameter is required and not set."    && exit 3
  [ "$INPUT_REPO_NAME" = "" ] && INPUT_REPO_NAME=__empty__

  export ACCURICS_URL=$INPUT_URL
  export ACCURICS_ENV_ID=$INPUT_ENV_ID
  export ACCURICS_APP_ID=$INPUT_APP_ID
  export ACCURICS_REPO_NAME=$INPUT_REPO_NAME
}

install_terraform() {
  local terraform_ver=$1
  [ "$terraform_ver" = "latest" ] && terraform_ver=`curl -sL https://releases.hashicorp.com/terraform/index.json | jq -r '.versions[].version' | grep -v '[-].*' | sort -rV | head -n 1`
  local url="https://releases.hashicorp.com/terraform/$terraform_ver/terraform_${terraform_ver}_linux_amd64.zip"

  echo "Downloading Terraform: $terraform_ver"
  curl -s -S -L -o /tmp/terraform_${terraform_ver}_linux_amd64.zip ${url}

  [ "$?" -ne 0 ] && echo "Error while downloading Terraform $terraform_ver" && exit 150

  unzip -d /usr/local/bin /tmp/terraform_${terraform_ver}_linux_amd64.zip
  [ "$?" -ne 0 ] && echo "Error while unzipping Terraform $terraform_ver" && exit 151
}

run_accurics() {
  local params=$1
  local plan_args=$2

  accurics init

  # Run accurics plan
  accurics plan $params $plan_args
  ACCURICS_PLAN_ERR=$?
}

process_errors() {
  # Default error code
  EXIT_CODE=0

  # If INPUT_FAIL_ON_ALL_ERRORS is set and accurics plan returns an error, propagate that error
  [ "$INPUT_FAIL_ON_ALL_ERRORS" = "true" ] && [ "$ACCURICS_PLAN_ERR" -ne 0 ] && EXIT_CODE=100

  # If INPUT_FAIL_ON_VIOLATIONS is set and violations are found, return an error
  VIOLATIONS=`grep violation $REPORT_NAME | head -1 | awk '{ print $2 }' |cut -d, -f1`
  [ "$INPUT_FAIL_ON_VIOLATIONS" = "true" ] && [ "$VIOLATIONS" != "null" ] && [ "$VIOLATIONS" -gt 0 ] && EXIT_CODE=101
}

process_output() {
  num_violations=$VIOLATIONS
  env_name=`grep envName $REPORT_NAME | head -1 | cut -d\" -f4`
  num_resources=`grep resources $REPORT_NAME | head -1 | awk '{ print $2 }' | cut -d, -f1`
  high=`grep high $REPORT_NAME | head -1 | awk '{ print $2 }' | cut -d, -f1`
  medium=`grep medium $REPORT_NAME | head -1 | awk '{ print $2 }' | cut -d, -f1`
  low=`grep low $REPORT_NAME | head -1 | awk '{ print $2 }' | cut -d, -f1`
  native=`grep native $REPORT_NAME | head -1 | awk '{ print $2 }' | cut -d, -f1`
  inherited=`grep inherit $REPORT_NAME | head -1 | awk '{ print $2 }' | cut -d, -f1`
  drift=`grep drift $REPORT_NAME | head -1 | awk '{ print $2 }' | cut -d, -f1`
  iac_drift=`grep iacdrift $REPORT_NAME | head -1 | awk '{ print $2 }' | cut -d, -f1`
  cloud_drift=`grep clouddrift $REPORT_NAME | head -1 | awk '{ print $2 }' | cut -d, -f1`
  has_errors=`grep HasErrors $REPORT_NAME | head -1 | awk '{ print $2 }' | cut -d, -f1`

  echo "::set-output name=env-name::$env_name"
  echo "::set-output name=num-violations::$num_violations"
  echo "::set-output name=num-resources::$num_resources"
  echo "::set-output name=high::$high"
  echo "::set-output name=medium::$medium"
  echo "::set-output name=low::$low"
  echo "::set-output name=native::$native"
  echo "::set-output name=inherited::$inherited"
  echo "::set-output name=drift::$drift"
  echo "::set-output name=iacdrift::$iacdrift"
  echo "::set-output name=clouddrift::$clouddrift"
  echo "::set-output name=has-errors::$has_errors"
}

process_args "$@"

[ "$INPUT_DEBUG_MODE" = "true" ] && set -x

install_terraform $INPUT_TERRAFORM_VERSION

for d in $INPUT_DIRECTORIES; do
  cd $d

  run_params=""

  echo "======================================================================"
  echo " Running the Accurics Action for directory: "
  echo "   $d"
  echo "======================================================================"

  run_accurics "$run_params" "$INPUT_PLAN_ARGS"

  echo "======================================================================"
  echo " Done!"
  echo "======================================================================"

  process_errors
  process_output

  cd -

  [ "$EXIT_CODE" -ne 0 ] && break
done

exit $EXIT_CODE
