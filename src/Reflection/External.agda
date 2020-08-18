------------------------------------------------------------------------
-- The Agda standard library
--
-- Support for system calls as part of reflection
------------------------------------------------------------------------

{-# OPTIONS --without-K --safe #-}

module Reflection.External where

import Agda.Builtin.Reflection.External as Builtin

open import Data.Nat.Base using (ℕ; suc; zero; NonZero)
open import Data.List.Base using (List; _∷_; [])
open import Data.Product using (_,_)
open import Data.String.Base using (String; _++_)
open import Data.Unit.Base using (⊤; tt)
open import Function using (case_of_; _$_)
open import Reflection hiding (name)
  -- using (TC; return; _>>=_; unify; Term; con; lit; nat; string; unknown; vArg; hArg)

-- |Representation for exit codes, assuming 0 is consistently used to indicate
--  success across platforms.
data ExitCode : Set where
  exitSuccess : ExitCode
  exitFailure : (n : ℕ) {n≢0 : NonZero n} → ExitCode

-- |Specification for a command.
record CmdSpec : Set where
  constructor cmdSpec
  field
    name  : String      -- ^ Executable name (see ~/.agda/executables)
    args  : List String -- ^ Command-line arguments for executable
    input : String      -- ^ Contents of standard input

-- |Result of running a command.
record Result : Set where
  constructor result
  field
    exitCode : ExitCode -- ^ Exit code returned by the process
    output   : String   -- ^ Contents of standard output
    error    : String   -- ^ Contents of standard error

-- |Convert a natural number to an exit code.
toExitCode : ℕ → ExitCode
toExitCode zero    = exitSuccess
toExitCode (suc n) = exitFailure (suc n)

-- |Quote an exit code as an Agda term.
quoteExitCode : ExitCode → Term
quoteExitCode exitSuccess =
  con (quote exitSuccess) []
quoteExitCode (exitFailure n) =
  con (quote exitFailure) (vArg (lit (nat n)) ∷ hArg (con (quote tt) []) ∷ [])

-- |Quote a result as an Agda term.
quoteResult : Result → Term
quoteResult (result exitCode output error) =
  con (quote result) ( vArg (quoteExitCode exitCode)
                     ∷ vArg (lit (string output))
                     ∷ vArg (lit (string error))
                     ∷ [])

-- |Run command from specification in TC monad.
runCmdTC : CmdSpec → TC Result
runCmdTC c = do
  (exitCode , (stdOut , stdErr))
    ← Builtin.execTC (CmdSpec.name c) (CmdSpec.args c) (CmdSpec.input c)
  return $ result (toExitCode exitCode) stdOut stdErr

-- |Run command from specification and return the full result.
--
--  NOTE: If the command fails, this macro still succeeds, and returns the
--        full result, including exit code and the contents of stderr.
--
macro
  unsafeRunCmd : CmdSpec → Term → TC ⊤
  unsafeRunCmd c hole = do
    r ← runCmdTC c
    unify hole $ quoteResult r

-- |Run command from specification. If the command succeeds, it returns the
--  contents of stdout. Otherwise, it throws a type error with the contents
--  of stderr.
macro
  runCmd : CmdSpec → Term → TC ⊤
  runCmd c hole = do
    r ← runCmdTC c
    let debugPrefix = ("user." ++ CmdSpec.name c)
    case Result.exitCode r of λ
      { exitSuccess → do
        debugPrint (debugPrefix ++ ".stderr") 10 (strErr (Result.error r) ∷ [])
        unify hole $ lit (string (Result.output r))
      ; (exitFailure n) → do
        debugPrint (debugPrefix ++ ".stdout") 10 (strErr (Result.output r) ∷ [])
        typeError (strErr (Result.error r) ∷ [])
      }
