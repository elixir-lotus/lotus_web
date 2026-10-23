## Why

<!-- The problem this solves, for whom, and what happened before it (an error, a crash, a wrong result). -->

Fixes #<!-- the issue; see CONTRIBUTING.md for when a pull request needs one -->

## What

<!-- The change, in a few lines. A screenshot for a change to the UI. -->

## How it was tested

<!-- The tests added, and what you ran by hand. -->

## Checklist

- [ ] One change: anything unrelated is in its own pull request.
- [ ] A bug fix has a test that fails on `main` and passes here.
- [ ] `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo`, `mix docs`, `mix test` and `mix dialyzer` pass.
- [ ] `npm test --prefix assets` passes, for a change to `assets/js`.
- [ ] The guides and `CHANGELOG.md` are updated, for a change a user can see.
- [ ] Says so here if it changes the public API, who may do what, or what the dashboard does today.
- [ ] No changes to the version or the release headings of the changelog (the maintainers keep those).
