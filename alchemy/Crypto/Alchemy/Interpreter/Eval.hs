{-# LANGUAGE DeriveFunctor              #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE NoImplicitPrelude          #-}
{-# LANGUAGE RankNTypes                 #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE UndecidableInstances, ScopedTypeVariables       #-}

module Crypto.Alchemy.Interpreter.Eval ( E, eval) where

import Control.Applicative
import Control.Monad.State
import Data.Tuple

import Algebra.Additive as Additive
import Algebra.Ring     as Ring

import Crypto.Alchemy.Language.Arithmetic
import Crypto.Alchemy.Language.Lambda
import Crypto.Alchemy.Language.SHE
import Crypto.Alchemy.Language.Wrap

import Crypto.Lol hiding (lift)
import qualified Crypto.Lol.Applications.SymmSHE as SHE
import           Crypto.Lol.Applications.SymmSHE (CT, ToSDCtx)

-- | Metacircular evaluator.
newtype E e a = E { unE :: e -> a } deriving (Functor, Applicative)

-- | Evaluate a closed expression (i.e., one not having any unbound
-- variables)
eval :: E () a -> a
eval = flip unE ()

instance Lambda E where
  lam f  = E $ curry $ unE f
  ($:) = (<*>)

instance DB E a where
  v0  = E snd
  s a = E $ unE a . fst

instance (Additive.C a) => Add E (Wrap a) where
  --x +: y = (+) <$> x <*> y
  negate' x = (fmap negate) <$> x

instance (Additive.C a) => AddLit E a where
  addLit x y = (fmap (x +)) <$> y

instance (Ring.C a) => Mul E (Wrap a) where
  type PreMul E (Wrap a) = (Wrap a)
  --x *: y = (*) <$> x <*> y

instance (Ring.C a) => MulLit E a where
  mulLit x y = (fmap (x *)) <$> y

instance SHE E where

  type ModSwitchPTCtx   E (Wrap (CT m zp (Cyc t m' zq))) zp' = (SHE.ModSwitchPTCtx t m' zp zp' zq)
  type RescaleLinearCtx E (Wrap (CT m zp (Cyc t m' zq))) zq' = (RescaleCyc (Cyc t) zq' zq, ToSDCtx t m' zp zq')
  type AddPublicCtx E (Wrap (CT m zp (Cyc t m' zq)))         = (SHE.AddPublicCtx t m m' zp zq)
  type MulPublicCtx E (Wrap (CT m zp (Cyc t m' zq)))         = (SHE.MulPublicCtx t m m' zp zq)
  type KeySwitchQuadCtx E (Wrap (CT m zp (Cyc t m' zq))) zq' gad = (SHE.KeySwitchCtx gad t m' zp zq zq')
  type TunnelCtx    E t e r s e' r' s' zp zq gad      = (SHE.TunnelCtx t r s e' r' s' zp zq gad)

  modSwitchPT     = fmap (fmap SHE.modSwitchPT)
  rescaleLinear = fmap (fmap SHE.rescaleLinearCT)
  addPublic      a = fmap $ fmap (SHE.addPublic a)
  mulPublic      a = fmap $ fmap (SHE.mulPublic a)
  keySwitchQuad  h = fmap $ fmap (SHE.keySwitchQuadCirc h)
  tunnel         f = fmap $ fmap (SHE.tunnelCT f)
