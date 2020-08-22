module SMT.Theories.Reals where

open import Data.Bool.Base as Bool using (Bool; false; true)
open import Data.Integer as Int using (ℤ; +_; -[1+_])
open import Data.Nat.Base as Nat using (ℕ)
open import Data.Nat.Show renaming (show to showℕ)
open import Data.List as List using (List; _∷_; [])
open import Data.Rational.Unnormalised as Rat using (ℚᵘ)
open import Data.String as String using (String)
open import Function.Equivalence using (equivalence)
open import Relation.Nullary using (Dec; yes; no)
open import Reflection using (Term; con; lit; nat; vArg)
import Relation.Nullary.Decidable as Dec
open import Relation.Binary.PropositionalEquality using (_≡_; refl; cong)
open import SMT.Theory
open import SMT.Theories.Core hiding (BOOL)
open import SMT.Theories.Core.Extensions


-- Sorts

data Sort : Set where
   CORE : (φ : CoreSort) → Sort
   REAL  : Sort

open Sorts Sort CORE

private
  variable
    σ : Sort
    Σ : Signature σ
    φ φ′ : CoreSort
    Φ : Signature φ

CORE-injective : CORE φ ≡ CORE φ′ → φ ≡ φ′
CORE-injective refl = refl

_≟-Sort_ : (σ σ′ : Sort) → Dec (σ ≡ σ′)
CORE φ ≟-Sort CORE φ′ = Dec.map (equivalence (cong CORE) CORE-injective) (φ ≟-CoreSort φ′)
CORE φ ≟-Sort REAL    = no (λ ())
REAL   ≟-Sort CORE φ  = no (λ ())
REAL   ≟-Sort REAL    = yes refl

showSort : Sort → String
showSort (CORE φ) = showCoreSort φ
showSort REAL     = "Real"


-- Values

Value : Sort → Set
Value (CORE φ) = CoreValue φ
Value REAL     = ℚᵘ

quoteSort : Sort → Term
quoteSort (CORE φ) = con (quote CORE) (vArg (quoteCoreSort φ) ∷ [])
quoteSort REAL     = con (quote REAL) []

quoteRat : ℚᵘ → Term
quoteRat (Rat.mkℚᵘ n d-1) =
  con (quote Rat.mkℚᵘ) (vArg (quoteInt n) ∷ vArg (lit (nat d-1)) ∷ [])
  where
    quoteInt : ℤ → Term
    quoteInt (+ n)    = con (quote +_) (vArg (lit (nat n)) ∷ [])
    quoteInt -[1+ n ] = con (quote -[1+_]) (vArg (lit (nat n)) ∷ [])

quoteValue : (σ : Sort) → Value σ → Term
quoteValue (CORE φ) = quoteCoreValue φ
quoteValue REAL     = quoteRat


-- Literals

data Literal : Sort → Set where
  core : CoreLiteral φ → Literal (CORE φ)
  real : ℕ → Literal REAL

open Literals Sort CORE Literal core

showLiteral : Literal σ → String
showLiteral (core x) = showCoreLiteral x
showLiteral (real x) = showℕ x

private
  variable
    l : Literal σ


-- Identifiers

data Identifier : (Σ : Signature σ) → Set where
  -- Core theory
  core : CoreIdentifier Φ → Identifier (map CORE Φ)
  eq   : Identifier (Rel REAL)
  neq  : Identifier (Rel REAL)
  ite  : Identifier (ITE σ)
  -- Reals theory
  neg  : Identifier (Op₁ REAL)
  sub  : Identifier (Op₂ REAL)
  add  : Identifier (Op₂ REAL)
  mul  : Identifier (Op₂ REAL)
  div  : Identifier (Op₂ REAL)
  leq  : Identifier (Rel REAL)
  lt   : Identifier (Rel REAL)
  geq  : Identifier (Rel REAL)
  gt   : Identifier (Rel REAL)

open Identifiers Sort CORE Identifier core

showIdentifier : Identifier Σ → String
showIdentifier (core x) = showCoreIdentifier x
showIdentifier eq       = "="
showIdentifier neq      = "distinct"
showIdentifier ite      = "ite"
showIdentifier neg      = "-"
showIdentifier sub      = "-"
showIdentifier add      = "+"
showIdentifier mul      = "*"
showIdentifier div      = "/"
showIdentifier leq      = "<="
showIdentifier lt       = "<"
showIdentifier geq      = ">="
showIdentifier gt       = ">"

private
  variable
    i : Identifier Σ


-- Instances

theory : Theory
Theory.Sort       theory = Sort
Theory._≟-Sort_   theory = _≟-Sort_
Theory.BOOL       theory = BOOL
Theory.Value      theory = Value
Theory.Literal    theory = Literal
Theory.Identifier theory = Identifier
Theory.quoteSort  theory = quoteSort
Theory.quoteValue theory = quoteValue

printable : Printable theory
Printable.showSort       printable = showSort
Printable.showLiteral    printable = showLiteral
Printable.showIdentifier printable = showIdentifier
