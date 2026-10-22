# 先定结构 (sketch)

**Before writing logic, fix the shape: how a caller uses it, then the types,
signatures, and module boundaries with empty bodies. Implement against that
sketch, and throw it out when it keeps fighting the code.** From pstack
`architect`, without its parallel runners (parallel versions only when the
user asks, see `playbooks/plan.md`). Principles: 先减后加, 通用解, 小步可验证.

Run it from 实施 (and from 排查 when the fix needs new structure) when the
change adds a module, a type, or a public interface, or reshapes code that two
or more modules call. A change inside one function body skips it.

1. **Ground.** Know every system the new code touches. For anything you have
   not read this session, run the **how** part of `playbooks/research.md` on
   it. When the change moves ownership or layering, also find out why the
   current shape is the way it is; that reason is a constraint.
2. **Usage first.** Write two or three realistic call sites the way a caller
   would write them: what they import, call, and get back. The usage is the
   spec; when the types disagree with it, change the types.
3. **Sketch twice.** Write two structurally different whole shapes (not two
   variants of one), each as types and signatures with `NotImplementedError`
   / `todo!()` / `throw` bodies, in the scratch directory. One shape is enough
   only when the constraints force it; say why.
4. **Screen** each shape against `references/design-red-flags.md`. Prefer the
   one that hides more behind a smaller public surface, and where a change
   that looks right from one file is right for the whole repo.
5. **Write the choice down** (in the reply, or in the plan doc when there is
   one): the usage, the shape, what it deliberately does not do, the losing
   shape and why it lost, open questions. Then continue without waiting,
   unless the user asked to see the structure first ("先给我看结构").
6. **Implement against the sketch.** Copy the chosen skeleton into the source
   tree and fill bodies unit by unit; commit only filled, checked units, as
   in 实施. A parameter or type the sketch did not foresee is a signal: say
   whether the sketch was wrong, the requirement was missed, or the code is
   overreaching.
7. **Scrap when it is wrong.** The same workaround in unrelated places, edge
   cases that each need a special branch, escape hatches (`Any`, casts,
   optional fields that are always set) to make it compile, callers needing
   the internals, or two deviations of the same kind: stop patching. Re-run
   step 1 on what exists, redesign as if the new facts were known on day one,
   make the new sketch smaller than the old, and log the decision.
