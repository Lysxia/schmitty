# Schmitty the Solver

```agda
{-# OPTIONS --allow-exec #-}

open import Data.Integer
open import Data.List
open import Data.Product
open import Relation.Binary.PropositionalEquality
open import SMT.Theories.Ints as Ints
open import SMT.Backend.Z3 Ints.reflectable
```
If you wanna solve some problems, you’re in luck! Schmitty is an Agda library which gives you bindings to SMT solvers! I know, cool right?!
```agda
verycool : ∀ (x y : ℤ) → x ≤ y → y ≤ x → x ≡ y
verycool = solveZ3
```
So, basically, what Schmitty offers you is a well-typed embedding of *some* of the SMT-LIB language in Agda. That means you can't *just* shout “solve” at your problems, you can also write SMT queries yourself!
```agda
blegh : Script [] (INT ∷ INT ∷ []) (SAT ∷ [])
blegh = declare-const "x" INT
      ∷ declare-const "y" INT
      ∷ assert (app₂ leq (# 0) (# 1))
      ∷ assert (app₂ leq (# 1) (# 0))
      ∷ assert (app₁ not (app₂ eq (# 0) (# 1)))
      ∷ check-sat
      ∷ []
```
Ohh, that's *almost* the script that our call to `solveZ3` above generates! What a lucky coincidence! You see, top-level constants are existentially quantified, so that script asks Z3 to see if `∃[ x ] ∃[ y ] (x ≤ y → y ≤ x → x ≢ y)` is satisfiable… and if it is, then, well, there *must* be a counter-example to our original goal!
```agda
_ : z3 blegh ≡ unsat ∷ []
_ = refl
```
Lucky us! It's *very* unsatisfiable… Wait, how did that work?! Did you just *call Z3 while type checking?!* Yes, dear reader, I did. You might’ve seen that I recently extended Agda with the `execTC` primitive, which allows you to make arbitrary system calls during type checking… well, within reason at least. Schmitty lets you take the script above, print it as an SMT-LIB term, and pass it to Z3!

Did you pick up on that `unsat` there? Schmitty doesn’t just give you back the solver’s output… she’s kind enough to actually parse the output for you! In fact, when Schmitty prints the term, she also builds you an output parser, which parses the expected solver output, including models! Let’s make sure our next query is satisfiable!
```agda
yesss : Script [] (INT ∷ INT ∷ []) (MODEL (INT ∷ INT ∷ []) ∷ [])
yesss = declare-const "x" INT
      ∷ declare-const "y" INT
      ∷ assert (app₂ leq (app₂ sub (# 0) (# 1)) (app₂ add (# 0) (# 1)))
      ∷ assert (app₁ not (app₂ eq (# 0) (# 1)))
      ∷ get-model
      ∷ []
```
If we call `get-model` instead of `check-sat`, Schmitty will give us back a valid model!
```agda
_ : z3 yesss ≡ ((sat , + 1 ∷ + 0 ∷ []) ∷ [])
_ = refl
```
Okay, I know that wasn’t a particularly hard problem, but I was in a rush. Send me a pull-request if you’ve got more interesting questions for Schmitty!

Wait, we can get models? Cool! We could use that to get counter-examples, if you try to prove something that *isn't* true! We, uh… We do:
```agda
woops : ∀ (x y : ℤ) → x - y ≤ x + y → x ≡ y
woops = solveZ3

-- > Found counter-example:
--     x = + 1
--     y = + 0
--   refuting (z : + 1 ≤ + 1) → + 1 ≡ + 0
--   when checking that the expression unquote solveZ3 has type
--   (x y : ℤ) → x - y ≤ x + y → x ≡ y
```

Right now, Schmitty supports three theories—[Core][SMT.Theories.Core], [Ints][SMT.Theories.Ints], and [Reals][SMT.Theories.Reals]—and two backends—[Z3][SMT.Backend.Z3], and [CVC4][SMT.Backend.CVC4]. If you’re missing your favourite theory or solver, your contribution is more than welcome!

If you’d like to work with Schmitty, a good place to start are the examples. You can find them in [`SMT.Theories.Core.Example`][SMT.Theories.Core.Example], [`SMT.Theories.Ints.Example`][SMT.Theories.Ints.Example], [`SMT.Theories.Reals.Example`][SMT.Theories.Reals.Example]!

# Installation

- [Agda][agda] ([>= 2.6.2-0f4538][agda-version])
- [agda-stdlib][agda-stdlib] ([>= experimental-af9d1d][agda-stdlib-version])
- [agdarsec][agdarsec] ([>= master-d91a32][agdarsec-version])

# Roadmap

- [ ] Upstream: merge [`Reflection.External`][Reflection.External] into [agda-stdlib][agda-stdlib];
- [ ] Upstream: merge [`Text.Parser.String`][Text.Parser.String] into [agdarsec][agdarsec];
- [ ] Issue: add names to `forAll` and `exists`, similar to `declare-const` (easy);
- [ ] Issue: parse `BOOL` values to `Set` instead of `Bool` using [agdarsec][agdarsec]’s new Large parsers (easy);
- [ ] Issue: reflect Π- and Σ-types to `forAll` and `exists` in [`SMT.Theories.Raw.Reflection`][SMT.Theories.Raw.Reflection] (easy);
- [ ] Enhancement: parser with error reporting (see [`Text.Parser.String`][Text.Parser.String]);
- [ ] Enhancement: add backends for other SMT-LIB compliant solvers (easy);
- [ ] Enhancement: add a testing framework which supports negative tests (easy);
- [ ] Enhancement: add theory of real arithmetic linked to Agda rational numbers (easy);
- [ ] Enhancement: add theory of floating-point numbers linked to Agda floats (easy);
- [ ] Enhancement: add theory of strings linked to Agda strings (easy);
- [ ] Enhancement: add theory of sequences linked to Agda lists (moderate);
- [ ] Enhancement: add theory of uninterpreted functions and constants linked to Agda names (moderate);
- [ ] Enhancement: add theory of regular expressions linked to [[https://github.com/gallais/aGdaREP | gallais/aGdaREP]] (moderate);
- [ ] Enhancement: add theory of algebraic datatypes linked to Agda datatypes (moderate);
- [ ] Enhancement: add theory of arrays linked to an axiomatisation of Haskell arrays (moderate);
- [ ] Enhancement: add support for [combined theories][CombinedTheories] (moderate);
- [ ] Enhancement: add support for [logic declarations][LogicDeclarations] (moderate);
- [ ] Enhancement: add proof reconstruction for SAT using [@kazkansouh][kazkansouh]’s [Kanso.Boolean.SatSolver][SatSolver] (moderate);
- [ ] Enhancement: add proof reconstruction for [Z3 proofs](http://ceur-ws.org/Vol-418/paper10.pdf) (cf. [*Proof Reconstruction for Z3 in Isabelle/HOL*][IsabelleHol]) (hard).

[Data.Float]: https://agda.github.io/agda-stdlib/Data.Float.html
[Data.Rational]: https://agda.github.io/agda-stdlib/Data.Rational.html
[SMT.Theory]: https://wenkokke.github.io/schmitty/SMT.Theory.html
[SMT.Theories.Core]: https://wenkokke.github.io/schmitty/SMT.Theories.Core.html
[SMT.Theories.Core.Extensions]: https://wenkokke.github.io/schmitty/SMT.Theories.Core.Extensions.html
[SMT.Theories.Core.Example]: https://wenkokke.github.io/schmitty/SMT.Theories.Core.Example.html
[SMT.Theories.Ints]: https://wenkokke.github.io/schmitty/SMT.Theories.Ints.html
[SMT.Theories.Ints.Example]: https://wenkokke.github.io/schmitty/SMT.Theories.Ints.Example.html
[SMT.Theories.Reals]: https://wenkokke.github.io/schmitty/SMT.Theories.Reals.html
[SMT.Theories.Reals.Example]: https://wenkokke.github.io/schmitty/SMT.Theories.Reals.Example.html
[SMT.Theories.Raw.Reflection]: https://wenkokke.github.io/schmitty/SMT.Theories.Raw.Reflection.html
[SMT.Script]: https://wenkokke.github.io/schmitty/SMT.Script.html
[SMT.Logics]: https://wenkokke.github.io/schmitty/SMT.Logics.html
[SMT.Backend.Z3]: https://wenkokke.github.io/schmitty/SMT.Backend.Z3.html
[SMT.Backend.CVC4]: https://wenkokke.github.io/schmitty/SMT.Backend.CVC4.html
[Text.Parser.String]: https://wenkokke.github.io/schmitty/Text.Parser.String.html
[Reflection.External]: https://wenkokke.github.io/schmitty/Reflection.External.html
[gallais]: https://github.com/gallais
[kazkansouh]: https://github.com/kazkansouh
[satsolver]: https://github.com/wenkokke/schmitty/tree/master/extra/Kanso
[agda]: https://github.com/agda/agda
[agda-version]: https://github.com/agda/agda/commit/0f4538c8dcd175b92acd577ca0bdca232f5cd17f
[agda-stdlib]: https://github.com/agda/agda-stdlib
[agda-stdlib-version]: https://github.com/agda/agda-stdlib/pull/1285/commits/af9d1da0f78f2b9cc84e531afc8615d16d9a1cf4
[agdarsec]: https://github.com/gallais/agdarsec
[agdarsec-version]: https://github.com/gallais/agdarsec/commit/d91a32e3256ceded84bc0bbf551ab8a710c6092e
[FloatingPoint]: http://www.philipp.ruemmer.org/publications/smt-fpa.pdf
[IsabelleHol]: http://www21.in.tum.de/~boehmes/proofrec.pdf
[SatSolver]: https://github.com/wenkokke/schmitty/blob/master/extra/Kanso/Boolean/SatSolver.agda
[CombinedTheories]: http://smtlib.cs.uiowa.edu/papers/smt-lib-reference-v2.6-r2017-07-18.pdf#subsection.5.4.1
[LogicDeclarations]: http://smtlib.cs.uiowa.edu/papers/smt-lib-reference-v2.6-r2017-07-18.pdf#subsection.5.5.1
