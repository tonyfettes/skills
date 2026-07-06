This MoonBit project is the accounting core of a payments service. Other
teams' packages will depend on it.

Implement in `account/account.mbt` a type `Account` with this API (exact
names and signatures):

- `Account::open(initial : Int) -> Account raise` — a negative `initial`
  raises.
- `Account::deposit(self : Account, amount : Int) -> Unit raise` — a
  non-positive `amount` raises.
- `Account::withdraw(self : Account, amount : Int) -> Unit raise` — a
  non-positive `amount` or insufficient funds raises.
- `Account::balance(self : Account) -> Int`

Hard requirement: the invariant **balance is never negative** must be
impossible to violate from *outside* this package — code in other packages
that depends on `eval/ledger/account` must have no way to construct an
`Account` in a bad state or reach around the API, no matter what it writes.
Design the package's public surface accordingly and review it before
finishing.

The project must pass `moon check` when you are done. You may add tests of
your own.

Work only inside the current directory.
