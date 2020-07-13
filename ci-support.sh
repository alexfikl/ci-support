set -e

ci_support="https://gitlab.tiker.net/inducer/ci-support/raw/master"

if [ "$PY_EXE" == "" ]; then
  if [ "$py_version" == "" ]; then
    PY_EXE=python3
  else
    PY_EXE=python${py_version}
  fi
fi


if [ "$(uname)" = "Darwin" ]; then
  PLATFORM=MacOSX
else
  PLATFORM=Linux
fi


# {{{ utilities

function get_proj_name()
{
  if [ -n "$CI_PROJECT_NAME" ]; then
    echo "$CI_PROJECT_NAME"
  else
    basename "$GITHUB_REPOSITORY"
  fi
}

print_status_message()
{
  echo "-----------------------------------------------"
  echo "Current directory: $(pwd)"
  echo "Python executable: ${PY_EXE}"
  echo "PYOPENCL_TEST: ${PYOPENCL_TEST}"
  echo "PYTEST_ADDOPTS: ${PYTEST_ADDOPTS}"
  echo "PROJECT_INSTALL_FLAGS: ${PROJECT_INSTALL_FLAGS}"
  echo "git revision: $(git rev-parse --short HEAD)"
  echo "git status:"
  git status -s
  echo "-----------------------------------------------"
}


create_and_set_up_virtualenv()
{
  ${PY_EXE} -m venv .env
  . .env/bin/activate
  ${PY_EXE} -m ensurepip

  # https://github.com/pypa/pip/issues/5345#issuecomment-386443351
  export XDG_CACHE_HOME=$HOME/.cache/$CI_RUNNER_ID

  $PY_EXE -m pip install --upgrade pip
  $PY_EXE -m pip install setuptools
}


install_miniforge()
{
  MINIFORGE_VERSION=3
  MINIFORGE_INSTALL_DIR=.miniforge${MINIFORGE_VERSION}

  MINIFORGE_INSTALL_SH=Miniforge3-$PLATFORM-x86_64.sh
  curl -L -O "https://github.com/conda-forge/miniforge/releases/latest/download/$MINIFORGE_INSTALL_SH"

  rm -Rf "$MINIFORGE_INSTALL_DIR"

  bash "$MINIFORGE_INSTALL_SH" -b -p "$MINIFORGE_INSTALL_DIR"
}


handle_extra_install()
{
  if test "$EXTRA_INSTALL" != ""; then
    for i in $EXTRA_INSTALL ; do
      # numpypy no longer recommended: https://doc.pypy.org/en/latest/faq.html#should-i-install-numpy-or-numpypy
      # 2020-03-12 AK
      #if [ "$i" = "numpy" ] && [[ "${PY_EXE}" == pypy* ]]; then
      #  $PY_EXE -m pip install git+https://bitbucket.org/pypy/numpy.git
      if [[ "$i" = *pybind11* ]] && [[ "${PY_EXE}" == pypy* ]]; then
        # Work around https://github.com/pypa/virtualenv/issues/1198
        # (nominally fixed, but not really it appears. --Mar 28, 2020 AK)
        # Running virtualenv --always-copy or -m venv --copies should also do the trick.
        L=$(readlink .env/include)
        rm .env/include
        cp -R $L .env/include

        # context:
        # https://github.com/conda-forge/pyopencl-feedstock/pull/45
        # https://github.com/pybind/pybind11/pull/2146
        $PY_EXE -m pip install git+https://github.com/isuruf/pybind11@pypy3
      else
        $PY_EXE -m pip install $i
      fi
    done
  fi
}


pip_install_project()
{
  handle_extra_install

  if test -f .conda-ci-build-configure.sh; then
    source .conda-ci-build-configure.sh
  fi

  if test -f .ci-build-configure.sh; then
    source .ci-build-configure.sh
  fi

  # Append --editable to PROJECT_INSTALL_FLAGS, if not there already.
  # See: https://gitlab.tiker.net/inducer/ci-support/-/issues/3
  # Can be removed after https://github.com/pypa/pip/issues/2195 is resolved.
  if [[ ! $PROJECT_INSTALL_FLAGS =~ (^|[[:space:]]*)(--editable|-e)[[:space:]]*$ ]]; then
      PROJECT_INSTALL_FLAGS="$PROJECT_INSTALL_FLAGS --editable"
  fi

  if test "$REQUIREMENTS_TXT" == ""; then
    REQUIREMENTS_TXT="requirements.txt"
  fi

  if test -f "$REQUIREMENTS_TXT"; then
    pip install -r "$REQUIREMENTS_TXT"
  fi

  $PY_EXE -m pip install $PROJECT_INSTALL_FLAGS .
}


# }}}


# {{{ cleanup

clean_up_repo_and_working_env()
{
  rm -Rf .env
  rm -Rf build
  find . -name '*.pyc' -delete

  rm -Rf env
  git clean -fdx \
    -e siteconf.py \
    -e boost-numeric-bindings \
    -e '.pylintrc.yml' \
    -e 'prepare-and-run-*.sh' \
    -e 'run-*.py' \
    -e '.test-*.yml' \
    $GIT_CLEAN_EXCLUDE


  if test `find "siteconf.py" -mmin +1`; then
    echo "siteconf.py older than a minute, assumed stale, deleted"
    rm -f siteconf.py
  fi

  if [[ "$NO_SUBMODULES" = "" ]]; then
    git submodule update --init --recursive
  fi
}

# }}}


# {{{ virtualenv build

build_py_project_in_venv()
{
  print_status_message
  clean_up_repo_and_working_env
  create_and_set_up_virtualenv

  $PY_EXE -m pip install pytest pytest-xdist

  pip_install_project
}

# }}}


# {{{ miniconda build

build_py_project_in_conda_env()
{
  print_status_message
  clean_up_repo_and_working_env
  install_miniforge

  PATH="$MINIFORGE_INSTALL_DIR/bin/:$PATH" conda update conda --yes --quiet

  PATH="$MINIFORGE_INSTALL_DIR/bin/:$PATH" conda update --all --yes --quiet

  PATH="$MINIFORGE_INSTALL_DIR/bin:$PATH" conda env create --file "$CONDA_ENVIRONMENT" --name testing

  source "$MINIFORGE_INSTALL_DIR/bin/activate" testing

  # https://github.com/conda-forge/ocl-icd-feedstock/issues/11#issuecomment-456270634
  rm -f $MINIFORGE_INSTALL_DIR/envs/testing/etc/OpenCL/vendors/system-*.icd
  # https://gitlab.tiker.net/inducer/pytential/issues/112
  rm -f $MINIFORGE_INSTALL_DIR/envs/testing/etc/OpenCL/vendors/apple.icd

  # https://github.com/pypa/pip/issues/5345#issuecomment-386443351
  export XDG_CACHE_HOME=$HOME/.cache/$CI_RUNNER_ID

  conda install --quiet --yes pip
  conda list

  # Using pip instead of conda here avoids ridiculous uninstall chains
  # like these: https://gitlab.tiker.net/inducer/pyopencl/-/jobs/61543
  $PY_EXE -m pip install pytest pytest-xdist

  pip_install_project
}

# }}}


# {{{ generic build

build_py_project()
{
  if test "$USE_CONDA_BUILD" == "1"; then
    build_py_project_in_conda_env
  else
    build_py_project_in_venv
  fi
}

# }}}


# {{{ test

test_py_project()
{
  AK_PROJ_NAME="$(get_proj_name)"

  TESTABLES=""
  if [ -d test ]; then
    cd test

    if ! [ -f .not-actually-ci-tests ]; then
      TESTABLES="$TESTABLES ."
    fi

    if [ -z "$NO_DOCTESTS" ]; then
      RST_FILES=(../doc/*.rst)

      if [ -e "${RST_FILES[0]}" ]; then
        TESTABLES="$TESTABLES ${RST_FILES[*]}"
      fi

      # macOS bash is too old for mapfile: Oh well, no doctests on mac.
      if [ "$(uname)" != "Darwin" ]; then
        mapfile -t DOCTEST_MODULES < <( git grep -l doctest -- ":(glob,top)$AK_PROJ_NAME/**/*.py" )
        TESTABLES="$TESTABLES ${DOCTEST_MODULES[@]}"
      fi
    fi

    if [[ -n "$TESTABLES" ]]; then
      echo "TESTABLES: $TESTABLES"

      # Core dumps? Sure, take them.
      ulimit -c unlimited

      # 10 GiB should be enough for just about anyone :)
      ulimit -m $(python -c 'print(1024*1024*10)')

      ${PY_EXE} -m pytest \
        --durations=10 \
        --tb=native  \
        --junitxml=pytest.xml \
        --doctest-modules \
        -rxsw \
        $PYTEST_FLAGS $TESTABLES
    fi
  fi
}

# }}}


# {{{ run examples

run_examples()
{
  cd examples
  for i in $(find . -name '*.py' -exec grep -q __main__ '{}' \; -print ); do
    echo "-----------------------------------------------------------------------"
    echo "RUNNING $i"
    echo "-----------------------------------------------------------------------"
    dn=$(dirname "$i")
    bn=$(basename "$i")
    (cd $dn; time ${PY_EXE} "$bn")
  done
}

# }}}

# vim: foldmethod=marker