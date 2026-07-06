///|
fn expect_failure(f : () -> Unit raise) -> Bool {
  try f() catch {
    _ => true
  } noraise {
    _ => false
  }
}

///|
test "account lifecycle" {
  let a = @account.Account::open(100)
  a.deposit(50)
  a.withdraw(120)
  @debug.assert_eq(a.balance(), 30)
}

///|
test "invariant violations raise and leave balance unchanged" {
  assert_true(expect_failure(() => @account.Account::open(-1) |> ignore))
  let a = @account.Account::open(10)
  assert_true(expect_failure(() => a.withdraw(11)))
  assert_true(expect_failure(() => a.deposit(0)))
  assert_true(expect_failure(() => a.withdraw(-5)))
  @debug.assert_eq(a.balance(), 10)
}
