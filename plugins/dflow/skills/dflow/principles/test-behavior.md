# 测行为 (test behavior, not implementation)

A test calls the code as its users do and asserts what they can observe:
return values, errors, state they read back, and outside effects (a request
sent, a row written). Judge each test against two imagined edits:

- **Break the behavior**: return a wrong value, skip an effect, or do it
  twice. A test that still passes proves nothing. Usual causes: an assertion
  looser than the contract, an expected value computed by the code under
  test, a restated constant or prompt string, assertions on data the test
  built.
- **Change only the internals**, every observable result the same. A test
  that now fails is pinned to the implementation.

Rewrite or delete a test that fails either check.

The contract decides, not the shape of the assertion. When the promise is
"X never happens", asserting no call is behavior; pair it with a case where
X happens, so the test shows it can see a call. An empty list is the exact
answer when nothing should match. An exact error message pins wording no
caller reads; the error type callers branch on is the contract.

Fix: one concrete input, the literal output or effect. For a mock, assert the
payload it received. Prefer no new test over a bad one; never change a test to
match a wrong implementation.
