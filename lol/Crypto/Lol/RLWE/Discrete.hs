{-# LANGUAGE ConstraintKinds, FlexibleContexts, MultiParamTypeClasses,
             RebindableSyntax, ScopedTypeVariables #-}

-- | Functions and types for working with discretized ring-LWE samples.

module Crypto.Lol.RLWE.Discrete where

import Crypto.Lol.Cyclotomic.Cyc
import Crypto.Lol.Prelude
import Crypto.Lol.RLWE.Continuous as C (errorBound)

import Control.Applicative
import Control.Monad.Random

-- | A discrete RLWE sample \( (a,b) \in R_q \times R_q\).
type Sample t m zq = (Cyc t m zq, Cyc t m zq)

-- | Common constraints for working with discrete RLWE.
type RLWECtx t m zq =
  (Fact m, Ring zq, Lift' zq, ToInteger (LiftOf zq),
   CElt t zq, CElt t (LiftOf zq))

-- | A discrete RLWE sample with the given scaled variance and secret.
sample :: forall rnd v t m zq .
  (RLWECtx t m zq, Random zq, MonadRandom rnd, ToRational v)
  => v -> Cyc t m zq -> rnd (Sample t m zq)
{-# INLINABLE sample #-}
sample svar s = let s' = adviseCRT s in do
  a <- getRandom
  e :: Cyc t m (LiftOf zq) <- errorRounded svar
  return (a, a * s' + reduce e)

-- | The error term of an RLWE sample, given the purported secret.
errorTerm :: (RLWECtx t m zq)
             => Cyc t m zq -> Sample t m zq -> Cyc t m (LiftOf zq)
{-# INLINABLE errorTerm #-}
errorTerm s = let s' = adviseCRT s
              in \(a,b) -> liftDec $ b - a * s'

-- | The 'gSqNorm' of the error term of an RLWE sample, given the
-- purported secret.
errorGSqNorm :: (RLWECtx t m zq)
                => Cyc t m zq -> Sample t m zq -> LiftOf zq
{-# INLINABLE errorGSqNorm #-}
errorGSqNorm s = gSqNorm . errorTerm s

-- | A bound such that the 'gSqNorm' of a discretized error term
-- generated by 'errorRounded' with scaled variance \(v\)
-- (over the \(m\)th cyclotomic field) is less than the
-- bound except with probability approximately \(\epsilon\).
errorBound :: (RealRing v, Transcendental v, Fact m)
              => v              -- ^ the scaled variance
              -> v              -- ^ \(\epsilon\)
              -> Tagged m Int64
errorBound v eps = do
  n <- fromIntegral <$> totientFact
  cont <- C.errorBound v eps -- continuous bound
  ps <- filter (/= 2) . fmap fst <$> ppsFact -- odd primes dividing m
  let stabilize x =
        let x' = (1/2 + log(2 * pi * x)/2 - log eps)/pi
        in if x'-x < 0.0001 then x' else stabilize x'
  return $ ceiling $ (2 ^ length ps) * n * stabilize (1/(2*pi)) + cont

