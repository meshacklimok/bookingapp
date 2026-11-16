/// Deposit percentages offered in the service form.
const depositOptions = [10, 20, 25, 30, 50];

/// What the customer pays online for [fullCents] with a [pct] deposit: rounded up to whole shillings and never more
/// than the price. Mirrors `set_payment_plan` in the database, which is the one that decides.
int depositCents(int fullCents, int pct) {
  if (fullCents <= 0) return 0;
  final shillings = (fullCents * pct / 10000).ceil();
  final cents = shillings * 100;
  return cents > fullCents ? fullCents : cents;
}
