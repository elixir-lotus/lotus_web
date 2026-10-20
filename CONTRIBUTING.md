# Contributing to Lotus Web

Thank you for helping. This page says what to open (an issue, a pull
request, or a security report), what a pull request needs, and what the
maintainers keep for themselves. How to run the dev server and the tests
is in the README, under [Development](README.md#development). The query
engine itself, with its adapters, visibility rules and caching, lives in
[Lotus](https://github.com/elixir-lotus/lotus); its
[contributing guide](https://github.com/elixir-lotus/lotus/blob/main/guides/contributing.md)
explains how a query runs, and the commit and branch conventions both
repositories use.

## Questions, bugs and ideas

- **A bug.** Open an issue with the bug report form. The Lotus and Lotus
  Web versions, the steps in the dashboard and the error from the server
  log or the browser console are the most useful things you can give.
- **An idea or a change of behaviour.** Open an issue with the feature
  request form, and say the problem before the solution.
- **A security problem.** Do not open an issue. See
  [SECURITY.md](SECURITY.md).

Search the open and closed issues first: the idea may already be planned,
or turned down for a reason given there. A bug in how a query runs, in an
adapter or in visibility rules may belong to Lotus rather than Lotus Web;
if you are not sure, open it here.

## When a pull request needs an issue first

Open an issue, and agree on the change there, before a pull request that:

- adds a feature, a mount option, a feature flag or a resolver callback;
- changes what the dashboard does, who may do what, or the public API
  (`lotus_dashboard/2`, `Lotus.Web.Resolver`, `Lotus.Web.MCP`);
- adds a dependency, Elixir or JavaScript;
- touches many files, or needs a design decision.

A pull request does not need an issue when it is small and its reason is
plain from the diff: a typo, a broken link, a wrong sentence in a guide,
a translation fix, or a bug fix with a test that fails without it. When in
doubt, open the issue: a short discussion costs less than a pull request
that is not merged.

A pull request with an issue says so: `Fixes #123` or `Closes #123`.

## A pull request

- **One change.** A fix, the guides for an unrelated case and a README
  edit are three pull requests. Each is reviewed, reverted and released
  on its own.
- **Why, not only what.** The description says the problem the change
  solves, for whom, and what happened before it: an error, a crash, a
  wrong result. A change to the UI has a screenshot.
- **Tests.** A bug fix has a test that fails on `main` and passes with
  the fix. A feature has tests of what it does, and of its errors. A
  change to who may do what has a test with a resolver that denies it.
- **Docs.** A change a user can see updates the guide it belongs to
  (under `guides/`) and [CHANGELOG.md](https://github.com/elixir-lotus/lotus_web/blob/main/CHANGELOG.md). New text in the UI
  goes through Gettext.
- **The checks pass.** CI runs them on Elixir 1.18, 1.19 and 1.20, with
  PostgreSQL on port 2346 (`docker compose up -d db`); run them first:

  ```sh
  mix format --check-formatted
  mix compile --warnings-as-errors
  mix credo
  mix docs
  mix test
  mix dialyzer
  ```

  CI does not run the JavaScript tests; a change to `assets/js` runs
  them with `npm test --prefix assets`.

The pull request template has these as a checklist.

## What the maintainers keep

- **Releases.** The version in `mix.exs`, the release headings of the
  changelog, the release branches and the tags are changed by the
  maintainers, at a release (see [Releasing](README.md#releasing)).

## Style

Match the code around your change: its naming, its comments and the way
its guides are written. `mix format` and `mix credo` settle the rest.

## License

By contributing, you agree that your contribution is released under the
MIT License of the project (see [LICENSE](https://github.com/elixir-lotus/lotus_web/blob/main/LICENSE)).
