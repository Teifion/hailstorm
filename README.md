# Beans
An integration test suite for [Teiserver](https://github.com/beyond-all-reason/teiserver). Designed to be easily extended and contributed. Beans will fire up a set of concurrent modules and collate the results.

## Installation and usage
Beans does not require anything other than an [Elixir](https://elixir-lang.org/) installation and a Teiserver installation. Assuming you have elixir installed you should be able to run it like so:

```sh
git clone git@github.com:beyond-all-reason/beans.git
cd beans
mix deps.get
mix beans
```

The final command `mix beans` will run the Beans program and output the results.

## Local development
Todo:
- Creating a new test
- Documentation