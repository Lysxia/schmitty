open import SMT.Theory

module SMT.Script (theory : Theory) where

open import Data.Fin as Fin using (Fin)
open import Data.List as List using (List; _∷_; [])
open import Data.Product using (∃; ∃-syntax; _,_)
open import Level using (Lift; lift; lower; _⊔_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)
open import SMT.Logics

open Theory theory


-------------------
-- SMT-LIB Terms --
-------------------

-- |Typing contexts.
Ctxt : Set
Ctxt = List Sort

private
  variable
    σ σ′    : Sort
    Γ Γ′ Γ″ : Ctxt
    Δ Δ′    : Ctxt
    Σ       : Signature σ
    Σ′      : Signature σ′

-- |Well-typed variables.
_∋_ : (Γ : Ctxt) (σ : Sort) → Set
Γ ∋ σ = ∃[ i ] (List.lookup Γ i ≡ σ)

-- |SMT-LIB terms.
--
--  NOTE: match expressions are omitted, since we have no plans at the moment
--        to support datatype sorts.
mutual
  data Term (Γ : Ctxt) : (σ : Sort) → Set where
    var    : ∀ {σ} (x : Γ ∋ σ) → Term Γ σ
    lit    : ∀ {σ} (l : Literal σ) → Term Γ σ
    app    : ∀ {σ} {Σ : Signature σ} (x : Identifier Σ) (xs : Args Γ (ArgTypes Σ)) → Term Γ σ
    forAll : ∀ {σ} (x : Term (σ ∷ Γ) BOOL) → Term Γ BOOL
    exists : ∀ {σ} (x : Term (σ ∷ Γ) BOOL) → Term Γ BOOL

  data Args (Γ : Ctxt) : (Δ : Ctxt) → Set where
    []  : Args Γ []
    _∷_ : Term Γ σ → Args Γ Δ → Args Γ (σ ∷ Δ)

pattern app₁ f x     = app f (x ∷ [])
pattern app₂ f x y   = app f (x ∷ y ∷ [])
pattern app₃ f x y z = app f (x ∷ y ∷ z ∷ [])

---------------------
-- SMT-LIB Results --
---------------------

-- |Possible results.
data OutputType : Set where
  SAT   : OutputType
  MODEL : Ctxt → OutputType

-- |Result contexts.
OutputCtxt : Set
OutputCtxt = List OutputType

private
  variable
    ξ ξ′    : OutputType
    Ξ Ξ′    : OutputCtxt

-- |SMT-LIB satisfiability.
data Sat : Set where
  sat     : Sat
  unsat   : Sat
  unknown : Sat

-- |SMT-LIB models.
data Model : (Γ : Ctxt) → Set where
  []  : Model []
  _∷_ : Term [] σ → Model Γ → Model (σ ∷ Γ)

-- |SMT-LIB script result.
Result : OutputType → Set
Result SAT       = Sat
Result (MODEL Γ) = Model Γ

-- |List of SMT-LIB results.
data Results : (Ξ : OutputCtxt) → Set where
  []  : Results []
  _∷_ : Result ξ → Results Ξ → Results (ξ ∷ Ξ)


----------------------
-- SMT-LIB Commands --
----------------------

-- |SMT-LIB commands.
--
--  NOTE: It is most natural to think of scripts as a list of commands,
--        but unfortunatly, commands such as `declare-const` bind a new
--        variable. Therefore, Command has two type-level arguments, `Γ`
--        and `Γ′`, which represent the binding context before and after
--        executing the command. Similarly, scripts have outputs. Therefore,
--        Commands have two more type-level arguments, `Ξ` and `Ξ′`, which
--        represent the list of outputs given by the SMT solver in order.
--
data Command (Γ : Ctxt) : (Ξ : OutputCtxt) (Γ′ : Ctxt) (Ξ′ : OutputCtxt) → Set where
  set-logic     : (l : Logic) → Command Γ Ξ Γ Ξ
  declare-const : (σ : Sort) → Command Γ Ξ (σ ∷ Γ) Ξ
  assert        : Term Γ BOOL → Command Γ Ξ Γ Ξ
  check-sat     : Command Γ Ξ Γ (SAT ∷ Ξ)
  get-model     : Command Γ (SAT ∷ Ξ) Γ (MODEL Γ ∷ SAT ∷ Ξ)


---------------------
-- SMT-LIB Scripts --
---------------------

-- |SMT-LIB scripts.
data Script (Γ : Ctxt) : (Γ″ : Ctxt) (Ξ : OutputCtxt) → Set where
  []  : Script Γ Γ []
  _∷_ : Command Γ Ξ Γ′ Ξ′ → Script Γ′ Γ″ Ξ → Script Γ Γ″ Ξ′


--------------------------
-- Printing and Parsing --
--------------------------

module Interaction
  (printable : Printable theory)
  where

  open import Category.Monad.State using (RawIMonadState; StateTIMonadState; IStateT)
  open import Codata.Musical.Stream as Stream using (Stream)
  open import Data.Char as Char using (Char)
  open import Data.Nat as Nat using (ℕ)
  open import Data.Nat.Show renaming (show to showℕ)
  open import Data.Product as Product using (_×_; _,_; proj₁; proj₂)
  open import Data.String as String using (String; _++_)
  open import Data.Unit as Unit using (⊤)
  open import Function using (const; id; _∘_)
  import Function.Identity.Categorical as Identity
  open import Relation.Unary
  import Text.Parser.Types as Parser
  open import Text.Parser.Combinators using ()
  open import Text.Parser.Combinators.Char
  open import Text.Parser.Monad

  open Printable printable

  private
    variable
      T : Sort → Set

  -- |Environments, i.e., lists where the types of the elements
  --  are determined by a type-level list.
  data Env (T : Sort → Set) : (Γ : Ctxt) → Set where
    []  : Env T []
    _∷_ : T σ → Env T Γ → Env T (σ ∷ Γ)

  -- |Get the first element in a non-empty environment.
  head : Env T (σ ∷ Γ) → T σ
  head (x ∷ _env) = x

  -- |Remove the first element from a non-empty environment.
  tail : Env T (σ ∷ Γ) → Env T Γ
  tail (_x ∷ env) = env

  -- |Get the i'th element from an environment.
  lookup : (env : Env T Γ) (i : Fin _) → T (List.lookup Γ i)
  lookup []          ()
  lookup ( x ∷ _env) Fin.zero    = x
  lookup (_x ∷  env) (Fin.suc i) = lookup env i

  -- |Name states, i.e., an environment of names, one for every
  --  variable in the context Γ, and a supply  of fresh names.
  --
  --  NOTE: the current implementation does not guarantee that
  --        each name in the supply is distinct. If we need this
  --        in the future, there is `Data.List.Fresh`.
  --
  record Names (Γ : Ctxt) : Set where
    field
      nameEnv    : Env (const String) Γ
      nameSupply : Stream String

  open Names -- bring `nameEnv` and `nameSupply` in scope

  -- When showing terms, we need to pass around a name state,
  -- for which we'll use an indexed monad, indexed by the context,
  -- so we bring the functions from the indexed monad in scope.
  open RawIMonadState (StateTIMonadState Names Identity.monad)

  -- |Add a fresh name to the front of the name environment.
  pushFreshName : (σ : Sort) → IStateT Names id Γ (σ ∷ Γ) String
  pushFreshName σ = do
    names ← get
    let names′ = pushFreshName′ σ names
    put names′
    return (head (nameEnv names′))
    where
      pushFreshName′ : (σ : Sort) → Names Γ → Names (σ ∷ Γ)
      nameEnv    (pushFreshName′ σ names) = Stream.head (nameSupply names) ∷ nameEnv names
      nameSupply (pushFreshName′ σ names) = Stream.tail (nameSupply names)


  -- |Remove first name from the name environment.
  popName : IStateT Names id (σ ∷ Γ) Γ ⊤
  popName = do modify popName′; return _
    where
      popName′ : Names (σ ∷ Γ) → Names Γ
      nameEnv    (popName′ names) = tail (nameEnv names)
      nameSupply (popName′ names) = nameSupply names


  -- |Get i'th name from the name environment in the state monad.
  getName : (i : Γ ∋ σ) → IStateT Names id Γ Γ String
  getName (i , _prf) = do
    names ← get
    return (lookup (nameEnv names) i)

  -- |Create an S-expression from a list of strings.
  --
  -- @
  --   mkSTerm ("*" ∷ "4" ∷ "5") ≡ "(* 4 5)"
  -- @
  --
  mkSTerm : List String → String
  mkSTerm = String.parens ∘ String.unwords

  -- |Parser monad.
  Parser : (A : Set) (n : ℕ) → Set
  Parser = Parser.Parser (Agdarsec′.vec Char)

  -- pTermS : Term Γ σ → IStateT Names id Γ Γ (String × ∀[ Parser {!!} ]) 
  -- pTermS = {!!}

  mutual

    -- |Show a term as an S-expression. The code below passes a name state in
    --  a state monad. For the pure version, see `showTerm` below.
    --
    showTermS : Term Γ σ → IStateT Names id Γ Γ String
    showTermS (var i) =
      getName i
    showTermS (lit l) =
      return (showLiteral l)
    showTermS (app x xs) = do
      let x′ = showIdentifier x
      xs′ ← showArgsS xs
      return (mkSTerm (x′ ∷ xs′))
    showTermS (forAll {σ} x) = do
      n′ ← pushFreshName σ
      let σ′ = showSort σ
      x′ ← showTermS x
      popName
      let nσs′ = mkSTerm (mkSTerm (n′ ∷ σ′ ∷ []) ∷ [])
      return (mkSTerm ("forall" ∷ nσs′ ∷ x′ ∷ []))
    showTermS (exists {σ} x) = do
      n′ ← pushFreshName σ
      let σ′ = showSort σ
      x′ ← showTermS x
      popName
      let nσs′ = mkSTerm (mkSTerm (n′ ∷ σ′ ∷ []) ∷ [])
      return (mkSTerm ("exists" ∷ nσs′ ∷ x′ ∷ []))

    -- |Show a series of terms as S-expression.
    --
    --  This is explicit to avoid sized-types, as Agda cannot infer that the call
    --  `mapM showTermS xs` terminates.
    --
    showArgsS : Args Γ Δ → IStateT Names id Γ Γ (List String)
    showArgsS [] = pure []
    showArgsS (x ∷ xs) = _∷_ <$> showTermS x ⊛ showArgsS xs

  -- |Show a command as an S-expression. The code below passes a name state in
  --  a state monad. For the pure version, see `showCommand` below.
  showCommandS : Command Γ′ Ξ′ Γ Ξ → IStateT Names id Γ′ Γ String
  showCommandS (set-logic l) =
    return (mkSTerm ("set-logic" ∷ showLogic l ∷ []))
  showCommandS (declare-const σ) = do
    n′ ← pushFreshName σ
    let σ′ = showSort σ
    return (mkSTerm ("declare-const" ∷ n′ ∷ σ′ ∷ []))
  showCommandS (assert x) = do
    x′ ← showTermS x
    return (mkSTerm ("assert" ∷ x′ ∷ []))
  showCommandS check-sat =
    return (mkSTerm ("check-sat" ∷ []))
  showCommandS get-model =
    return (mkSTerm ("get-model" ∷ []))

  -- |Show a script as an S-expression. The code below passes a name state in
  --  a state monad. For the pure version, see `showScript` below.
  showScriptS : Script Γ Γ′ Ξ → IStateT Names id Γ Γ′ (List String)
  showScriptS [] = pure []
  showScriptS (cmd ∷ cmds) = _∷_ <$> showCommandS cmd ⊛ showScriptS cmds

  -- |A name state for the empty context, which supplies the names x0, x1, x2, ...
  x′es : Names []
  nameEnv    x′es = []
  nameSupply x′es = Stream.map (λ n → "x" ++ showℕ n) (Stream.iterate ℕ.suc 0)

  -- |Show a term as an S-expression.
  showTerm : Names Γ → Term Γ σ → String
  showTerm names x = proj₁ (showTermS x names)

  -- |Show a command as an S-expression.
  showCommand : Names Γ → Command Γ Ξ Γ′ Ξ′ → String
  showCommand names cmd = proj₁ (showCommandS cmd names)

  -- |Show a script as an S-expression.
  showScript : Names Γ → Script Γ Γ′ Ξ → String
  showScript names cmd = String.unlines (proj₁ (showScriptS cmd names))
