module SMT.Theory where

open import Level
open import Data.List as List using (List; _∷_; [])
open import Data.String using (String)
open import Reflection using (Term)
open import Relation.Nullary using (Dec; yes; no)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)
open import Text.Parser.String


record Signature {Sort : Set} (σ : Sort) : Set where
  field
    ArgTypes : List Sort

open Signature public


module _ {Sort : Set} where

  infix 3 _↦_

  _↦_ : (σs : List Sort) (σ : Sort) → Signature σ
  Σ ↦ _ = record { ArgTypes = Σ }

  Op₁ : (σ : Sort) → Signature σ
  Op₁ σ = σ ∷ [] ↦ σ

  Op₂ : (σ : Sort) → Signature σ
  Op₂ σ = σ ∷ σ ∷ [] ↦ σ

  map : {CoreSort : Set} {φ : CoreSort} (CORE : CoreSort → Sort) → Signature φ → Signature (CORE φ)
  map CORE Φ = record { ArgTypes = List.map CORE (ArgTypes Φ) }


record Theory : Set₁ where
  field
    Sort       : Set
    _≟-Sort_   : (σ σ′ : Sort) → Dec (σ ≡ σ′)
    BOOL       : Sort
    Value      : Sort → Set
    Literal    : Sort → Set
    Identifier : {σ : Sort} → Signature σ → Set
    quoteSort  : Sort → Term
    quoteValue : (σ : Sort) → Value σ → Term

record Printable (theory : Theory) : Set where
  open Theory theory
  field
    showSort       : Sort → String
    showLiteral    : {σ : Sort} → Literal σ → String
    showIdentifier : {σ : Sort} {Σ : Signature σ} → Identifier Σ → String

record Parsable (theory : Theory) : Set₁ where
  open Theory theory
  field
    readSort   : ∀[ Parser Sort ]
    readValue  : (σ : Sort) → ∀[ Parser (Value σ) ]
