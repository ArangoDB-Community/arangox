# Deliberately empty. Warnings dialyzer is wrong about are suppressed
# in-source with a `@dialyzer` attribute on the affected function, beside a
# comment giving the reason: attributes are honored by everything that runs
# dialyzer (dialyxir and ElixirLS alike), while entries here are honored by
# `mix dialyzer` only and still surface in an editor.
#
# Nothing goes in either place to silence a warning that is right.
[]
