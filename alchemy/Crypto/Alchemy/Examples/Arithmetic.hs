{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE PolyKinds             #-}
{-# LANGUAGE RebindableSyntax      #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE TypeApplications      #-}
{-# LANGUAGE TypeFamilies          #-}

module Crypto.Alchemy.Examples.Arithmetic where

import Control.Monad.Reader

import Crypto.Alchemy.Interpreter.Compiler.Noise
import Crypto.Alchemy.Interpreter.Compiler.PT2CT
import Crypto.Alchemy.Interpreter.DedupRescale
import Crypto.Alchemy.Interpreter.Dup
import Crypto.Alchemy.Interpreter.Eval
import Crypto.Alchemy.Interpreter.Print

import Crypto.Alchemy.Language.Arithmetic
import Crypto.Alchemy.Language.Lambda
import Crypto.Alchemy.Language.Wrap

import Crypto.Lol                       hiding (Pos (..))
import Crypto.Lol.Cyclotomic.Tensor.CPP
import Crypto.Lol.Types

import Data.Maybe
import Data.Type.Natural (Nat (Z))

-- EAC: We can get rid of signatures once #13524 is fixed (should be in 8.2)

-- we give a type signature for easy partial type application
pt1 :: forall b e expr a .
  (a ~ PreMul expr b, Mul expr b, Add expr a, DB expr a, Lambda expr)
  => expr e (a -> a -> b)
pt1 = lam $ lam $ v0 *: (v0 +: (s v0))

type Zq q = ZqBasic q Int64

main :: IO ()
main = do
  -- no types needed to show a function!
  putStrLn $ pprint pt1
  -- evaluate a DSL function to a Haskell function, then apply to arguments
  putStrLn $ show $ eval (pt1 @(Wrap (Cyc CT F4 (Zq 7)))) (injectCyc 7) (injectCyc 11)

  -- compile the un-applied function to CT, then print it out
  (x,st) <- pt2ct
         @'[ '(F4, F8) ]
         @'[ Zq $(mkTLNatNat $ 2^(15 :: Int)), Zq $(mkTLNatNat $ 2^(15 :: Int)+1) ]
         @(Zq $(mkTLNatNat 13))
         @TrivGad
         @Double
         1.0
         (pt1 @(Wrap (PNoise 'Z (Cyc CT F4 (Zq 7)))))

  -- duplicate the compiled expression
  let (z1,z2) = dup x
      (w1,w2) = dup z1
  -- encrypt some arguments
  arg1 <- fromJust $ encryptArg st 7
  arg2 <- fromJust $ encryptArg st 11
  -- print the compiled function
  putStrLn $ pprint w1
  -- if the first modulus is large enough, this will remove the rescales!
  putStrLn $ pprint $ dedupRescale w2
  -- evaluate the compiled function, then apply it to encrypted inputs
  let result = eval z2 arg1 arg2
  -- show the encrypted result
  putStrLn $ show result
  -- show the decrypted result
  putStrLn $ show $ decryptP2C st $ unwrap result

-- EAC: TODO
-- encapsulation for compile CTs? (CTWrapper?)
-- tunneling example
-- print out intermediate error ratios