#! /bin/bash

curl -L -O -k https://gitlab.tiker.net/inducer/ci-support/raw/main/ci-support.sh
source ci-support.sh

build_py_project_in_conda_env

# See https://github.com/airspeed-velocity/asv/pull/965
pip install git+https://github.com/isuruf/asv@e87267acd2bc302097cb56286464dafc1983db54#egg=asv

conda list

if [[ -z "$PROJECT" ]]; then
    echo "PROJECT env var not set"
    exit 1
fi

if [[ -z "$PYOPENCL_TEST" ]]; then
    echo "PYOPENCL_TEST env var not set"
    exit 1
fi

mkdir -p ~/.$PROJECT/asv/results

if [[ ! -z "$CI" ]]; then
  mkdir -p .asv/env
  if [[ "$CI_PROJECT_NAMESPACE" == "inducer" ]]; then
    ln -s ~/.$PROJECT/asv/results .asv/results
  else
    # Copy, so that the original folder is not changed.
    cp -r ~/.$PROJECT/asv/results .asv/results
  fi
  rm -rf .asv/env

  # Fetch the main branch if the git repository in the gitlab CI env does not have it.
  if ! git rev-parse --verify main > /dev/null 2>&1; then
    git fetch origin main || true
    git branch main origin/main
  fi
fi

if [[ ! -f ~/.asv-machine.json ]]; then
  asv machine --yes
fi

main_commit=`git rev-parse main`
test_commit=`git rev-parse HEAD`

# cf. https://github.com/pandas-dev/pandas/pull/25237
# for reasoning on --launch-method=spawn
asv run $main_commit...$main_commit~ --skip-existing --verbose --show-stderr --launch-method=spawn
asv run $test_commit...$test_commit~ --skip-existing --verbose --show-stderr --launch-method=spawn

output=`asv compare $main_commit $test_commit --factor ${ASV_FACTOR:-1} -s`
echo "$output"

if [[ "$output" = *"worse"* ]]; then
  echo "Some of the benchmarks have gotten worse"
  exit 1
fi

if [[ "$CI_PROJECT_NAMESPACE" == "inducer" ]]; then
  git branch -v
  asv publish --html-dir ~/.scicomp-benchmarks/asv/$PROJECT
fi
