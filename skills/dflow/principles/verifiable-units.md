# 小步可验证 (sequence verifiable units)

- Split multi-step work into small units that each end in a state you can
  check. Known-good state, one change, run the check, then go on.
- Riskiest unknown first; scaffold and verification before features.
- Commit each verified unit on its own, in an order that proves the work:
  failing test then fix, removal then reshape, baseline then treatment.
- A unit that did not move its check is reverted, not left to ride.
