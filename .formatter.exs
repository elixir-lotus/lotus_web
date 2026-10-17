# Used by "mix format"
locals_without_parens = [lotus_dashboard: 1, lotus_dashboard: 2]

[
  import_deps: [:sake],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
