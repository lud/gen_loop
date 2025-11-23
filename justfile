install:
  mix deps.get

format:
  mix format --migrate

_git_status:
    git status

test:
  mix test --warnings-as-errors

compile-warnings:
  mix compile --force --warnings-as-errors

dialyzer:
  mix dialyzer

credo:
  mix credo

check: install format compile-warnings test credo dialyzer _git_status
