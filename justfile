_mix_deps:
  mix deps.get

format:
  mix format --migrate

test:
  mix test --warnings-as-errors

compile-warnings:
  mix compile --force --warnings-as-errors

dialyzer:
  mix dialyzer

credo:
  mix credo

_libdev_check:
  mix libdev.check

_git_status:
  git status

check: _mix_deps format _libdev_check _git_status
