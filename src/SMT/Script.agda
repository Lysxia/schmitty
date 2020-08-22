open import SMT.Theory

module SMT.Script (theory : Theory) where

open import Data.Fin as Fin using (Fin)
open import Data.List as List using (List; _∷_; []; _++_)
open import Data.List.NonEmpty as List⁺ using (List⁺; _∷_)
open import Data.Product as Prod using (∃; ∃-syntax; _,_)
open import Relation.Nullary using (Dec; yes; no)
open import Relation.Nullary.Decidable using (True)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)
open import SMT.Logics
open import Data.Environment as Env using (Env; _∷_; [])

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
    Γ Γ′ δΓ : Ctxt
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

  Args : (Γ Δ : Ctxt) → Set
  Args Γ = Env (λ σ _Δ → Term Γ σ)

pattern app₁ f x     = app f (x ∷ [])
pattern app₂ f x y   = app f (x ∷ y ∷ [])
pattern app₃ f x y z = app f (x ∷ y ∷ z ∷ [])

Rename : (Γ Δ : Ctxt) → Set
Rename Γ Δ = ∀ {σ} → Γ ∋ σ → Δ ∋ σ

extendVar : Γ ∋ σ → (σ′ ∷ Γ) ∋ σ
extendVar (i , p) = Fin.suc i , p

extendRename : Rename Γ Γ′ → Rename (σ ∷ Γ) (σ ∷ Γ′)
extendRename r (Fin.zero  , p) = Fin.zero , p
extendRename r (Fin.suc i , p) = extendVar (r (i , p))

mutual
  rename : Rename Γ Γ′ → Term Γ σ → Term Γ′ σ
  rename r (var i)    = var (r i)
  rename r (lit l)    = lit l
  rename r (app x xs) = app x (renameArgs r xs)
  rename r (forAll x) = forAll (rename (extendRename r) x)
  rename r (exists x) = exists (rename (extendRename r) x)

  renameArgs : Rename Γ Γ′ → Args Γ Δ → Args Γ′ Δ
  renameArgs r [] = []
  renameArgs r (x ∷ xs) = rename r x ∷ renameArgs r xs

weaken : Term Γ σ → Term (σ′ ∷ Γ) σ
weaken = rename extendVar

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
    Ξ Ξ′ δΞ : OutputCtxt

-- |SMT-LIB satisfiability.
data Sat : Set where
  sat     : Sat
  unsat   : Sat
  unknown : Sat

_≟-Sat_ : (s₁ s₂ : Sat) → Dec (s₁ ≡ s₂)
sat     ≟-Sat sat     = yes refl
sat     ≟-Sat unsat   = no (λ ())
sat     ≟-Sat unknown = no (λ ())
unsat   ≟-Sat sat     = no (λ ())
unsat   ≟-Sat unsat   = yes refl
unsat   ≟-Sat unknown = no (λ ())
unknown ≟-Sat sat     = no (λ ())
unknown ≟-Sat unsat   = no (λ ())
unknown ≟-Sat unknown = yes refl

-- |SMT-LIB models.
Model : Ctxt → Set
Model = Env (λ σ _Γ → Term [] σ)

-- |SMT-LIB script result.
Result : OutputType → Set
Result SAT       = Sat
Result (MODEL Γ) = Model Γ

-- |List of SMT-LIB results.
--
-- The Results type *could* be defined as below, but it is defined as a
-- datatype of its own to help Agda's reflection mechanism fill in the
-- implicit arguments during unquoting.
--
-- @
--   Results : (Ξ : OutputCtxt) → Set
--   Results = Env (λ ξ _Ξ → Result ξ)
-- @
--
data Results : (Ξ : OutputCtxt) → Set where
  []  : Results []
  _∷_ : Result ξ → Results Ξ → Results (ξ ∷ Ξ)


----------------------
-- SMT-LIB Commands --
----------------------

-- |SMT-LIB commands.
--
--  NOTE: Scripts are lists of commands. Unfortunately, some commands,
--        such as `declare-const`, bind variables variables. Command has
--        two type-level arguments, `Γ` and `δΓ`, which represent the binding
--        context before and executing the command, and the new variables bound
--        after executing the command. We use a similar trick to gather the
--        types of the outputs, using `Ξ` and `δΞ`.
--
data Command (Γ : Ctxt) : (Ξ : OutputCtxt) (δΓ : Ctxt) (δΞ : OutputCtxt) → Set where
  set-logic     : (l : Logic) → Command Γ Ξ [] []
  declare-const : (σ : Sort) → Command Γ Ξ (σ ∷ []) []
  assert        : Term Γ BOOL → Command Γ Ξ [] []
  check-sat     : Command Γ Ξ [] (SAT ∷ [])
  get-model     : Command Γ (SAT ∷ Ξ) [] (MODEL Γ ∷ [])


---------------------
-- SMT-LIB Scripts --
---------------------

-- |SMT-LIB scripts.
data Script (Γ : Ctxt) : (Γ′ : Ctxt) (Ξ : OutputCtxt) → Set where
  []  : Script Γ Γ []
  _∷_ : Command Γ Ξ δΓ δΞ → Script (δΓ ++ Γ) Γ′ Ξ → Script Γ Γ′ (δΞ ++ Ξ)


--------------------------
-- Printing and Parsing --
--------------------------

module Interaction
  (printable : Printable theory)
  (parsable : Parsable theory)
  where

  open import Category.Monad
  open import Category.Monad.State as StateCat using (RawIMonadState; IStateT)
  open import Codata.Musical.Stream as Stream using (Stream)
  open import Data.Char as Char using (Char)
  open import Data.Maybe as Maybe using (Maybe; just; nothing)
  open import Data.Nat as Nat using (ℕ)
  open import Data.Nat.Show renaming (show to showℕ)
  open import Data.Product as Product using (_×_; _,_; -,_; proj₁; proj₂)
  open import Data.String as String using (String)
  open import Data.Unit as Unit using (⊤)
  open import Data.Vec as Vec using (Vec)
  open import Function using (const; id; _∘_; _$_)
  import Function.Identity.Categorical as Identity
  open import Text.Parser.String as P hiding (_>>=_)
  open import Reflection using (con; vArg)

  open Printable printable
  open Parsable parsable

  -- |Names.
  Name : Set
  Name = List⁺ Char

  -- |Show names.
  showName : Name → String
  showName = String.fromList ∘ List⁺.toList

  -- |Name environments, i.e., lists where the types of the elements
  --  are determined by a type-level list.
  NameEnv : Ctxt → Set
  NameEnv = Env (λ _σ _Γ → Name)

  -- |Name states, i.e., an environment of names, one for every
  --  variable in the context Γ, and a supply  of fresh names.
  --
  --  NOTE: the current implementation does not guarantee that
  --        each name in the supply is distinct. If we need this
  --        in the future, there is `Data.List.Fresh`.
  --
  record Names (Γ : Ctxt) : Set where
    field
      nameEnv    : NameEnv Γ
      nameSupply : Stream Name

  open Names -- bring `nameEnv` and `nameSupply` in scope

  -- When showing terms, we need to pass around a name state,
  -- for which we'll use an indexed monad, indexed by the context,
  -- so we bring the functions from the indexed monad in scope.
  private
    monadStateNameState = StateCat.StateTIMonadState Names Identity.monad

  open RawIMonadState monadStateNameState
    using (return; _>>=_; _>>_; put; get; modify)


  -- |Add a fresh name to the front of the name environment.
  pushFreshName : (σ : Sort) → IStateT Names id Γ (σ ∷ Γ) Name
  pushFreshName σ = do
    names ← get
    let names′ = pushFreshName′ σ names
    put names′
    return (Env.head (nameEnv names′))
    where
      pushFreshName′ : (σ : Sort) → Names Γ → Names (σ ∷ Γ)
      nameEnv    (pushFreshName′ σ names) = Stream.head (nameSupply names) ∷ nameEnv names
      nameSupply (pushFreshName′ σ names) = Stream.tail (nameSupply names)


  -- |Remove first name from the name environment.
  popName : IStateT Names id (σ ∷ Γ) Γ ⊤
  popName = do modify popName′; return _
    where
      popName′ : Names (σ ∷ Γ) → Names Γ
      nameEnv    (popName′ names) = Env.tail (nameEnv names)
      nameSupply (popName′ names) = nameSupply names


  -- |Get i'th name from the name environment in the state monad.
  getName : (i : Γ ∋ σ) → IStateT Names id Γ Γ Name
  getName (i , _prf) = do
    names ← get
    return (Env.lookup (nameEnv names) i)


  -- |Create an S-expression from a list of strings.
  --
  -- @
  --   mkSTerm ("*" ∷ "4" ∷ "5") ≡ "(* 4 5)"
  -- @
  --
  mkSTerm : List String → String
  mkSTerm = String.parens ∘ String.unwords

  ParserEnv : Ctxt → Set
  ParserEnv = Env (λ σ Γ → ∀[ Parser ((σ ∷ Γ) ∋ σ) ])

  -- |Extend an environment with a number of failing parsers.
  extendPE : (δΓ : Ctxt) → ParserEnv Γ → ParserEnv (δΓ ++ Γ)
  extendPE []       env = env
  extendPE (σ ∷ δΓ) env = fail ∷ extendPE δΓ env

  -- |An environment of failing variable parsers.
  failPE : (Γ : Ctxt) → ParserEnv Γ
  failPE []      = []
  failPE (σ ∷ Γ) = fail ∷ failPE Γ

  -- |A singleton variable parser.
  varPE : Name → Γ ∋ σ → ParserEnv Γ
  varPE {σ′ ∷ Γ} n x@(Fin.zero  , refl) = (x <$ exacts n) ∷ failPE Γ
  varPE {σ′ ∷ Γ} n   (Fin.suc i , p)    = fail ∷ varPE {Γ} n (i , p)

  -- |Merge two environments of variable parsers.
  _<||>_ : ParserEnv Γ → ParserEnv Γ → ParserEnv Γ
  [] <||> [] = []
  (p₁ ∷ env₁) <||> (p₂ ∷ env₂) = (p₁ <|> p₂) ∷ (env₁ <||> env₂)

  -- |Fold an ParserEnv to a variable parser.
  foldPE : ParserEnv Γ → ∀[ Parser (∃[ σ ] (Γ ∋ σ)) ]
  foldPE []            = fail
  foldPE (p ∷ env) {x} = (-,_ <$> p {x}) <|> (Prod.map id extendVar <$> foldPE env {x})

  mutual

    -- |Show a term as an S-expression. The code below passes a name state in
    --  a state monad. For the pure version, see `showTerm` below.
    showTermS : Term Γ σ → IStateT Names id Γ Γ (String × ParserEnv Γ)
    showTermS {Γ} {σ} (var i) = do
      n ← getName i
      return (showName n , varPE n i)
    showTermS {Γ} {σ} (lit l) =
      return (showLiteral l , failPE Γ)
    showTermS (app x xs) = do
      let x = showIdentifier x
      (xs , p) ← showArgsS xs
      return (mkSTerm (x ∷ xs) , p)
    showTermS (forAll {σ} x) = do
      n ← pushFreshName σ
      (x , p) ← showTermS x
      popName
      let nσs = mkSTerm (mkSTerm (showName n ∷ showSort σ ∷ []) ∷ [])
      return (mkSTerm ("forall" ∷ nσs ∷ x ∷ []) , Env.tail p)
    showTermS (exists {σ} x) = do
      n ← pushFreshName σ
      (x , p) ← showTermS x
      popName
      let nσs = mkSTerm (mkSTerm (showName n ∷ showSort σ ∷ []) ∷ [])
      return (mkSTerm ("exists" ∷ nσs ∷ x ∷ []) , Env.tail p)

    -- |Show a series of terms as S-expression.
    --
    --  This is explicit to avoid sized-types, as Agda cannot infer that the call
    --  `mapM showTermS xs` terminates.
    --
    showArgsS : Args Γ Δ → IStateT Names id Γ Γ (List String × ParserEnv Γ)
    showArgsS {Γ} {Δ} [] =
      return ([] , failPE Γ)
    showArgsS {Γ} {Δ} (x ∷ xs) = do
      (x , p₁) ← showTermS x
      (xs , p₂) ← showArgsS xs
      return (x ∷ xs , (p₁ <||> p₂))


  -- |Show a command as an S-expression. The code below passes a name state in
  --  a state monad. For the pure version, see `showCommand` below.
  showCommandS : Command Γ Ξ δΓ δΞ → IStateT Names id Γ (δΓ ++ Γ) (String × ParserEnv (δΓ ++ Γ))
  showCommandS {Γ′} {Ξ′} (set-logic l) =
    return (mkSTerm ("set-logic" ∷ showLogic l ∷ []) , failPE Γ′)
  showCommandS {Γ′} {Ξ′} (declare-const σ) = do
    n ← pushFreshName σ
    let p = varPE n (Fin.zero , refl)
    return (mkSTerm ("declare-const" ∷ showName n ∷ showSort σ ∷ []) , p)
  showCommandS {Γ′} {Ξ′} (assert x) = do
    (x , p) ← showTermS x
    return (mkSTerm ("assert" ∷ x ∷ []) , p)
  showCommandS {Γ′} {Ξ′} check-sat =
    return (mkSTerm ("check-sat" ∷ []) , failPE Γ′)
  showCommandS {Γ′} {Ξ′} get-model =
    return (mkSTerm ("get-model" ∷ []) , failPE Γ′)

  -- |Show a script as an S-expression. The code below passes a name state in
  --  a state monad. For the pure version, see `showScript` below.
  showScriptS : Script Γ Γ′ Ξ → IStateT Names id Γ Γ′ (List String × (ParserEnv Γ → ParserEnv Γ′))
  showScriptS {Γ} [] =
    return ([] , id)
  showScriptS (cmd ∷ scr) = do
    (cmd , p₁) ← showCommandS cmd
    (scr , δp) ← showScriptS scr
    return (cmd ∷ scr , λ p₂ → δp (p₁ <||> extendPE _ p₂))


  -- |A name state for the empty context, which supplies the names x0, x1, x2, ...
  x′es : Names []
  nameEnv    x′es = []
  nameSupply x′es = Stream.map (λ n → 'x' ∷ String.toList (showℕ n)) (Stream.iterate ℕ.suc 0)


  -- |Show a script as an S-expression.
  showScript : Script [] Γ Ξ → String × ∀[ Parser (∃[ σ ] (Γ ∋ σ)) ]
  showScript scr =
    Prod.map String.unlines (λ p → withSpaces (foldPE (p []))) (proj₁ (showScriptS scr x′es))


  -- |Parse a satisfiability result.
  parseSat : ∀[ Parser Sat ]
  parseSat = withSpaces (pSat <|> pUnsat <|> pUnknown)
    where
      pSat     = sat     <$ text "sat"
      pUnsat   = unsat   <$ text "unsat"
      pUnknown = unknown <$ text "unknown"


  _ : parseSat parses "sat" as (_≟-Sat sat)
  _ = _

  _ : parseSat parses "unsat" as (_≟-Sat unsat)
  _ = _

  _ : parseSat parses "unknown" as (_≟-Sat unknown)
  _ = _

  _ : parseSat rejects "dogfood"
  _ = _

  -- |Parse a variable assignment.
  parseVarAssign : ∀[ Parser (∃[ σ ] (Γ ∋ σ)) ] → ∀[ Parser (∃[ σ ] (Γ ∋ σ × Value σ)) ]
  parseVarAssign {Γ} parseVarName = parens (box (guardM checkVarAssign unsafeParseVarAssign))
    where
      -- Parse a pair of a sort and a value of that sort.
      parseSortValue : ∀[ Parser (∃[ σ ] (Value σ)) ]
      parseSortValue = readSort P.>>= λ σ → box (-,_ <$> readValue σ)

      -- Parse a variable assignment, with possibly distinct sorts.
      unsafeParseVarAssign : ∀[ Parser (∃[ σ ] (Γ ∋ σ) × ∃[ σ ] (Value σ)) ]
      unsafeParseVarAssign =
        text "define-fun" &> box (parseVarName <&> box (text "()" &> box parseSortValue))

      -- Check if the expect and actual sorts correspond.
      checkVarAssign : ∃[ σ ] (Γ ∋ σ) × ∃[ σ ] (Value σ) → Maybe (∃[ σ ] (Γ ∋ σ × Value σ))
      checkVarAssign ((σ₁ , x) , (σ₂ , v)) with σ₁ ≟-Sort σ₂
      ... | yes refl = just (σ₂ , x , v)
      ... | no  _    = nothing

  -- TODO: connect the output of showScript, via parseVarAssign, to the parseResults function.
  -- parseModel : ∀[ Parser (∃[ σ ] (Γ ∋ σ)) ] → ∀[ Parser (Model Γ) ]
  -- parseModel parseVarName = {!!}

  -- |Parse a result.
  parseResult : (ξ : OutputType) → ∀[ Parser (Result ξ) ]
  parseResult SAT       = parseSat
  parseResult (MODEL Γ) = notYetImplemented
    where
      postulate
        notYetImplemented : ∀[ Parser (Result (MODEL Γ))]

  -- |Parse a list of results.
  parseResults : (ξ : OutputType) (Ξ : OutputCtxt) → ∀[ Parser (Results (ξ ∷ Ξ)) ]
  parseResults ξ [] = (_∷ []) <$> parseResult ξ
  parseResults ξ (ξ′ ∷ Ξ) = _∷_ <$> parseResult ξ <*> box (parseResults ξ′ Ξ)


  -- |Quote a satisfiability result.
  quoteSat : Sat → Reflection.Term
  quoteSat sat     = con (quote sat) []
  quoteSat unsat   = con (quote unsat) []
  quoteSat unknown = con (quote unknown) []

  -- |Quote a result.
  quoteResult : Result ξ → Reflection.Term
  quoteResult {SAT}     r = quoteSat r
  quoteResult {MODEL Γ} r = notYetImplemented r
    where
      postulate
        notYetImplemented : Result (MODEL Γ) → Reflection.Term

  -- |Quote a list of results.
  quoteResults : Results Ξ → Reflection.Term
  quoteResults [] = con (quote Results.[]) $ []
  quoteResults (r ∷ rs) = con (quote Results._∷_) $ vArg (quoteResult r) ∷ vArg (quoteResults rs) ∷ []

-- -}
-- -}
-- -}
-- -}
-- -}
