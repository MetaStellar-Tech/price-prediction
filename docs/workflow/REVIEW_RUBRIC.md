# Review Rubric

Review protocol changes in this order:

1. State-machine safety: invalid transitions must revert.
2. Permission safety: admin and operator powers must stay narrow.
3. Funds safety: accounting must not overpay, double-pay, or trap expected payouts.
4. Settlement safety: winner, loser, draw, and fee semantics must match docs.
5. Oracle boundary: CoreRead usage must stay explicit and testable.
6. Test quality: important paths need deterministic tests; economic assumptions need simulation where practical.
