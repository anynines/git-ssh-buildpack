#!/usr/bin/env bash

set -eu
set -o pipefail

readonly PROGDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BUILDPACKDIR="$(cd "${PROGDIR}/.." && pwd)"

# shellcheck source=SCRIPTDIR/.util/tools.sh
source "${PROGDIR}/.util/tools.sh"

# shellcheck source=SCRIPTDIR/.util/print.sh
source "${PROGDIR}/.util/print.sh"

# shellcheck source=SCRIPTDIR/.util/git.sh
source "${PROGDIR}/.util/git.sh"

# shellcheck source=SCRIPTDIR/.util/builder.sh
source "${PROGDIR}/.util/builder.sh"

function main() {
  while [[ "${#}" != 0 ]]; do
    case "${1}" in
      --use-token|-t)
        shift 1
        token::fetch
        ;;

      --help|-h)
        shift 1
        usage
        exit 0
        ;;

      "")
        # skip if the argument is empty
        shift 1
        ;;

      *)
        util::print::error "unknown argument \"${1}\""
    esac
  done

  if [[ ! -d "${BUILDPACKDIR}/integration" ]]; then
      util::print::warn "** WARNING  No Integration tests **"
  fi

  tools::install
  util::builder::stack::build
  util::builder::builder::build
  images::pull
  tests::run
}

function usage() {
  cat <<-USAGE
integration.sh [OPTIONS]

Runs the integration test suite.

OPTIONS
  --help       -h  prints the command usage
  --use-token  -t  use GIT_TOKEN from lastpass
USAGE
}

function tools::install() {
  util::tools::pack::install \
    --directory "${BUILDPACKDIR}/.bin"

  util::tools::jam::install \
    --directory "${BUILDPACKDIR}/.bin"

  if [[ ! -f "${BUILDPACKDIR}/.packit" ]]; then
    util::tools::packager::install \
      --directory "${BUILDPACKDIR}/.bin"
  fi
}

function images::pull() {
  local builder
  builder=""

  if [[ -f "${BUILDPACKDIR}/integration.json" ]]; then
    builder="$(jq -r .builder "${BUILDPACKDIR}/integration.json")"
  fi

  if [[ "${builder}" == "null" || -z "${builder}" ]]; then
    builder="index.docker.io/paketobuildpacks/builder:base"
  fi

  util::print::title "Setting default pack builder image..."
  pack config default-builder "${builder}"

  local run_image lifecycle_image
  run_image="$(
    pack inspect-builder "${builder}" --output json \
      | jq -r '.local_info.run_images[0].name'
  )"
  lifecycle_image="index.docker.io/buildpacksio/lifecycle:$(
    pack inspect-builder "${builder}" --output json \
      | jq -r '.local_info.lifecycle.version'
  )"

  util::print::title "Pulling lifecycle image..."
  docker pull "${lifecycle_image}"
}

function token::fetch() {
  GIT_TOKEN="$(util::git::token::fetch)"
  export GIT_TOKEN
}

function tests::run() {
  util::print::title "Run Buildpack Runtime Integration Tests"

  testout=$(mktemp)
  pushd "${BUILDPACKDIR}" > /dev/null
    if GOMAXPROCS="${GOMAXPROCS:-4}" go test -count=1 -timeout 0 ./integration/... -v -run Integration | tee "${testout}"; then
      util::tools::tests::checkfocus "${testout}"
      util::print::success "** GO Test Succeeded **"
    else
      util::print::error "** GO Test Failed **"
    fi
  popd > /dev/null
}

main "${@:-}"
