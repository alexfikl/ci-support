#! /bin/bash

set -e
set -x

PY_EXE=python3.5

echo "-----------------------------------------------"
echo "Current directory: $(pwd)"
echo "Python executable: ${PY_EXE}"
echo "-----------------------------------------------"

# {{{ clean up

rm -Rf .env
rm -Rf build
find . -name '*.pyc' -delete

rm -Rf env
git clean -fdx -e siteconf.py -e boost-numeric-bindings -e local_settings.py

if test `find "siteconf.py" -mmin +1`; then
  echo "siteconf.py older than a minute, assumed stale, deleted"
  rm -f siteconf.py
fi

# }}}

git submodule update --init --recursive

# {{{ virtualenv

${PY_EXE} -m venv .env
. .env/bin/activate

${PY_EXE} -m ensurepip

# }}}

# Pinned to 0.5.0 for
# https://github.com/PyCQA/pep8-naming/issues/53
# fixed by
# https://github.com/PyCQA/pep8-naming/pull/55
# (but not released as of May 5, 2018)
$PY_EXE -m pip install flake8 pep8-naming==0.5.0

python -m flake8 "$@"
