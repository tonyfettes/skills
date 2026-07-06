///|
/// A payment account. Abstract outside this package: the balance can only
/// change through the API below, which maintains balance >= 0.
struct Account {
  mut balance : Int
}

///|
pub suberror AccountError {
  NegativeInitial(Int)
  NonPositiveAmount(Int)
  InsufficientFunds(balance~ : Int, requested~ : Int)
} derive(Debug)

///|
pub fn Account::open(initial : Int) -> Account raise AccountError {
  guard initial >= 0 else { raise NegativeInitial(initial) }
  { balance: initial }
}

///|
pub fn Account::deposit(self : Account, amount : Int) -> Unit raise AccountError {
  guard amount > 0 else { raise NonPositiveAmount(amount) }
  self.balance += amount
}

///|
pub fn Account::withdraw(self : Account, amount : Int) -> Unit raise AccountError {
  guard amount > 0 else { raise NonPositiveAmount(amount) }
  guard amount <= self.balance else {
    raise InsufficientFunds(balance=self.balance, requested=amount)
  }
  self.balance -= amount
}

///|
pub fn Account::balance(self : Account) -> Int {
  self.balance
}
