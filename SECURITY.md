# Security

## Reporting a vulnerability

Do not open a public issue for a security problem. Report it privately
through GitHub: [Report a vulnerability](https://github.com/elixir-lotus/lotus_web/security/advisories/new).

Say what an attacker can do, and how: the page, the event or the request,
the mount options and resolver involved, and the steps or the payload. We
answer within a week, agree on a fix and a date, and credit you in the
advisory unless you ask us not to.

A problem in how Lotus itself runs a query (read-only transactions,
visibility rules, adapters, the cache) is fixed in
[Lotus](https://github.com/elixir-lotus/lotus); report it there the same
way, or here if you are not sure which one it is.

## Supported versions

Security fixes are made to the latest release. Whether a fix is also
released for an earlier line is decided with the advisory.

## What is in scope

Lotus Web is mounted in your Phoenix router and runs SQL against your
databases through Lotus. It takes LiveView events and HTTP requests from
the browser, which any person can craft. A problem is in scope when such
an event or request can:

- run a query, or a statement that writes, that the mount, the resolver or
  Lotus's `read_only` setting should stop;
- show tables, columns or rows that Lotus's visibility rules or the
  resolver's scope hide from the person, including through the schema
  explorer, a CSV export, the cache, the AI assistant or MCP;
- reach the dashboard, or do an action, that `resolve_access/1` or
  `authorize/3` denies, or act as another person;
- run script in another person's browser (XSS): through query results,
  column names, saved query and dashboard names, text cards, markdown,
  AI answers or charts;
- reuse or forge an export token, or get past a Content Security Policy
  that the nonce options should satisfy;
- crash the LiveView, or make the server or a database do unbounded work.

Who may open the dashboard is decided by the app: mount it behind your
authentication, as the README's [Security](README.md#security) section
says. A dashboard mounted without authentication, or a resolver that
allows everything, is a configuration choice, not a vulnerability in
Lotus Web.
