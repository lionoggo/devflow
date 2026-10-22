# 测行为 (test behavior, not implementation)

A test calls the code as its users do and asserts the exact result they see.
Rewrite or delete a test that would still pass if every called function
returned nothing or a wrong value. These shapes fail that check:

- loose or no assertion (`toBeDefined`, `toBeTruthy`, `> 0`, "no exception");
- call or absence only (`toHaveBeenCalled`, empty list);
- expected value computed by the code under test;
- a restated constant, config default, or prompt string;
- assertions on data the test itself built.

Fix: one concrete input, the literal output or effect. For a mock, assert the
payload it received. Prefer no new test over a bad one; never change a test to
match a wrong implementation.
