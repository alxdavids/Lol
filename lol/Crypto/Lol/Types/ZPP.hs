{-|
Module      : Crypto.Lol.Types.ZPP
Description : A class for integers mod a prime power.
Copyright   : (c) Eric Crockett, 2011-2017
                  Chris Peikert, 2011-2017
License     : GPL-2
Maintainer  : ecrockett0@email.com
Stability   : experimental
Portability : POSIX

\( \def\Z{\mathbb{Z}} \)
A class for integers mod a prime power.
-}

{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeFamilies     #-}

module Crypto.Lol.Types.ZPP
( ZPP(..)
) where

import Crypto.Lol.Prelude
import Crypto.Lol.Types.FiniteField

-- | Represents integers modulo a prime power.
class (PrimeField (ZpOf zq), Ring zq) => ZPP zq where

  -- | An implementation of the integers modulo the prime base.
  type ZpOf zq

  -- | The prime and exponent of the modulus.
  modulusZPP :: Tagged zq PP

  -- | Lift from \(\Z_p\) to a representative.
  liftZp :: ZpOf zq -> zq

