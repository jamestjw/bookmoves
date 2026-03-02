# Bookmoves

Bookmoves is a Phoenix LiveView app for spaced repetition of chess openings.

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## What Is Implemented

* Opening cards with `name`, `ECO`, and move sequence.
* LiveView review queue at `/openings` showing cards due now.
* Rating actions: `Again`, `Hard`, `Good`, `Easy`.
* Automatic rescheduling using a simplified SM-2 style interval update.
* Card detail/edit pages at `/openings/:id`.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
